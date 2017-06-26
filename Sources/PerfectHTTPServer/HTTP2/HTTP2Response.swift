//
//  HTTP2.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 2016-02-18.
//  Copyright © 2016 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PerfectLib
import PerfectHTTP
import PerfectThread

final class HTTP2Response: HTTPResponse {
	var request: HTTPRequest
	var status: HTTPResponseStatus = .ok
	var isStreaming = true // implicitly streamed
	var bodyBytes: [UInt8] = []
	var headerStore = Array<(HTTPResponseHeader.Name, String)>()
	var encoder: HPACKEncoder { return h2Request.session!.encoder }
	var wroteHeaders = false
	var h2Request: HTTP2Request { return request as! HTTP2Request }
	var session: HTTP2Session? { return h2Request.session }
	var debug: Bool { return session?.debug ?? false }
	var filters: IndexingIterator<[[HTTPResponseFilter]]>? {
		guard let f = session?.server.responseFilters, !f.isEmpty else {
			return nil
		}
		return f.makeIterator()
	}
	var frameWriter: HTTP2FrameWriter? { return session?.frameWriter }
	var windowSize: Int {
		get { return h2Request.windowSize }
		set { h2Request.windowSize = newValue }
	}
	var maxFrameSize: Int {
		return h2Request.session?.settings.maxFrameSize ?? 16384
	}
	var streamId: UInt32 { return h2Request.streamId }
	
	init(_ request: HTTP2Request) {
		self.request = request
	}
	
	deinit {
		if debug { print("~HTTP2Response \(streamId)") }
	}
	
	func header(_ named: HTTPResponseHeader.Name) -> String? {
		for (n, v) in headerStore where n == named {
			return v
		}
		return nil
	}
	
	@discardableResult
	func addHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
		headerStore.append((name, value))
		return self
	}
	
	@discardableResult
	func setHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
		var fi = [Int]()
		for i in 0..<headerStore.count {
			let (n, _) = headerStore[i]
			if n == name {
				fi.append(i)
			}
		}
		fi = fi.reversed()
		for i in fi {
			headerStore.remove(at: i)
		}
		return addHeader(name, value: value)
	}
	var headers: AnyIterator<(HTTPResponseHeader.Name, String)> {
		var g = self.headerStore.makeIterator()
		return AnyIterator<(HTTPResponseHeader.Name, String)> {
			g.next()
		}
	}
	
	func pushHeaders(callback: @escaping (Bool) -> ()) {
		guard !wroteHeaders else {
			return callback(true)
		}
		wroteHeaders = true
		guard h2Request.streamState != .closed else {
			return callback(false)
		}
		if let filters = self.filters {
			filterHeaders(allFilters: filters, callback: callback)
		} else {
			finishPushHeaders(callback: callback)
		}
	}
	
	func finishPushHeaders(callback: @escaping (Bool) -> ()) {
		if debug {
			print("response header:")
			print("\tstream: \(streamId)")
			print("\t:status \(status.code)")
			headerStore.forEach {
				(arg0) in
				let (name, value) = arg0
				print("\t\(name.standardName.lowercased()): \(value)")
			}
		}
		let bytes = Bytes()
		do {
			try encoder.encodeHeader(out: bytes, nameStr: ":status", valueStr: "\(status.code)")
			try headerStore.forEach {
				(arg0) in
				let (name, value) = arg0
				try encoder.encodeHeader(out: bytes, nameStr: name.standardName.lowercased(), valueStr: value)
			}
		} catch {
			h2Request.session?.fatalError(streamId: h2Request.streamId, error: .internalError, msg: "Error while encoding headers")
			return callback(false)
		}
		let frame = HTTP2Frame(type: .headers, flags: flagEndHeaders, streamId: h2Request.streamId, payload: bytes.data)
		frameWriter?.enqueueFrame(frame)
		callback(true)
	}
	
	func pushBody(final: Bool, bodyBytes inBodyBytes: [UInt8], callback: @escaping (Bool) -> ()) {
		guard h2Request.streamState != .closed else {
			return callback(false)
		}
		guard final || !inBodyBytes.isEmpty else {
			return callback(true)
		}
		if !inBodyBytes.isEmpty && windowSize == 0 {
			h2Request.windowSizeChanged = {
				Threading.dispatch { //  get off frame read thread
					self.pushBody(final: final, bodyBytes: inBodyBytes, callback: callback)
				}
			}
			return
		}
		if final {
			// !FIX! this needs an API change for response filters to let them know
			// when a call is the last
			request.scratchPad["_flushing_"] = true
		}
		let sendBytes: [UInt8]
		let remainingBodyBytes: [UInt8]
		let moreToCome: Bool
		let maxSize = min(windowSize, maxFrameSize)
		if inBodyBytes.count > maxSize {
			sendBytes = Array(inBodyBytes[0..<maxSize])
			remainingBodyBytes = Array(inBodyBytes[maxSize..<inBodyBytes.count])
			moreToCome = true
		} else {
			sendBytes = inBodyBytes
			remainingBodyBytes = []
			moreToCome = false
		}
		windowSize -= sendBytes.count
		if debug {
			print("response \(streamId) body bytes: \(sendBytes.count), remaining: \(remainingBodyBytes.count), window: \(windowSize)")
		}
		var frame = HTTP2Frame(type: .data,
		                       flags: (!moreToCome && final) ? flagEndStream : 0,
		                       streamId: h2Request.streamId,
		                       payload: sendBytes)
		if !moreToCome {
			frame.sentCallback = {
				ok in
				guard ok else { return self.removeRequest() }
				callback(ok)
			}
		}
		frameWriter?.enqueueFrame(frame)
		if moreToCome {
			pushBody(final: final, bodyBytes: remainingBodyBytes, callback: callback)
		}
	}
	
	func push(final: Bool, callback: @escaping (Bool) -> ()) {
		pushHeaders {
			ok in
			guard ok else {
				self.removeRequest()
				return callback(false)
			}
			self.filteredBodyBytes {
				bytes in
				self.pushBody(final: final, bodyBytes: bytes) {
					ok in
					guard ok else {
						self.removeRequest()
						return callback(false)
					}
					callback(true)
				}
			}
		}
	}
	
	func push(callback: @escaping (Bool) -> ()) {
		push(final: false, callback: callback)
	}
	
	func completed() {
		push(final: true) {
			ok in
			self.removeRequest()
		}
	}
	
	func abort() {
		h2Request.streamState = .closed
		let b = Bytes()
		b.import32Bits(from: HTTP2Error.noError.rawValue)
		var frame = HTTP2Frame(type: .cancelStream, flags: 0, streamId: streamId, payload: b.data)
		frame.sentCallback = {
			ok in
			self.removeRequest()
		}
	}
	
	func removeRequest() {
		let req = h2Request
		req.session?.removeRequest(req.streamId)
	}
}

extension HTTP2Response {
	
	func filterHeaders(allFilters: IndexingIterator<[[HTTPResponseFilter]]>, callback: @escaping (Bool) -> ()) {
		var allFilters = allFilters
		if let prioFilters = allFilters.next() {
			return filterHeaders(allFilters: allFilters, prioFilters: prioFilters.makeIterator(), callback: callback)
		}
		finishPushHeaders(callback: callback)
	}
	
	func filterHeaders(allFilters: IndexingIterator<[[HTTPResponseFilter]]>,
	                   prioFilters: IndexingIterator<[HTTPResponseFilter]>,
	                   callback: @escaping (Bool) -> ()) {
		var prioFilters = prioFilters
		guard let filter = prioFilters.next() else {
			return filterHeaders(allFilters: allFilters, callback: callback)
		}
		filter.filterHeaders(response: self) {
			result in
			switch result {
			case .continue:
				self.filterHeaders(allFilters: allFilters, prioFilters: prioFilters, callback: callback)
			case .done:
				self.finishPushHeaders(callback: callback)
			case .halt:
				self.abort()
			}
		}
	}
	
	func filterBodyBytes(allFilters: IndexingIterator<[[HTTPResponseFilter]]>,
	                     prioFilters: IndexingIterator<[HTTPResponseFilter]>,
	                     callback: ([UInt8]) -> ()) {
		var prioFilters = prioFilters
		guard let filter = prioFilters.next() else {
			return filterBodyBytes(allFilters: allFilters, callback: callback)
		}
		filter.filterBody(response: self) {
			result in
			switch result {
			case .continue:
				self.filterBodyBytes(allFilters: allFilters, prioFilters: prioFilters, callback: callback)
			case .done:
				self.finishFilterBodyBytes(callback: callback)
			case .halt:
				self.abort()
			}
		}
	}
	
	func filterBodyBytes(allFilters: IndexingIterator<[[HTTPResponseFilter]]>, callback: ([UInt8]) -> ()) {
		var allFilters = allFilters
		if let prioFilters = allFilters.next() {
			return filterBodyBytes(allFilters: allFilters, prioFilters: prioFilters.makeIterator(), callback: callback)
		}
		finishFilterBodyBytes(callback: callback)
	}
	
	func finishFilterBodyBytes(callback: (_ bodyBytes: [UInt8]) -> ()) {
		let bytes = bodyBytes
		bodyBytes = []
		callback(bytes)
	}
	
	func filteredBodyBytes(callback: (_ bodyBytes: [UInt8]) -> ()) {
		if let filters = self.filters {
			return filterBodyBytes(allFilters: filters, callback: callback)
		}
		finishFilterBodyBytes(callback: callback)
	}
}
