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
	let filters: IndexingIterator<[[HTTPResponseFilter]]>?
	var encoder: HPACKEncoder { return h2Request.session!.encoder }
	var wroteHeaders = false
	
	var h2Request: HTTP2Request { return request as! HTTP2Request }
	var session: HTTP2Session? { return h2Request.session }
	var debug: Bool { return session?.debug ?? false }
	var frameWriter: HTTP2FrameWriter? { return session?.frameWriter }
	var windowSize: Int {
		get { return h2Request.windowSize }
		set { h2Request.windowSize = newValue }
	}
	var maxFrameSize: Int {
		return h2Request.session?.settings.maxFrameSize ?? 16384
	}
	var streamId: UInt32 { return h2Request.streamId }
	
	init(_ request: HTTP2Request, filters: IndexingIterator<[[HTTPResponseFilter]]>? = nil) {
		self.request = request
		self.filters = filters
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
		}
		let frame = HTTP2Frame(type: .headers, flags: flagEndHeaders, streamId: h2Request.streamId, payload: bytes.data)
		frameWriter?.enqueueFrame(frame)
		callback(true)
	}
	
	func pushBody(final: Bool, callback: @escaping (Bool) -> ()) {
		guard h2Request.streamState != .closed else {
			return callback(false)
		}
		guard final || !bodyBytes.isEmpty else {
			return callback(true)
		}
		if !bodyBytes.isEmpty && windowSize == 0 {
			h2Request.windowSizeChanged = {
				Threading.dispatch { //  get off frame read thread
					self.pushBody(final: final, callback: callback)
				}
			}
			return
		}
		let sendBytes: [UInt8]
		let moreToCome: Bool
		let maxSize = min(windowSize, maxFrameSize)
		if bodyBytes.count > maxSize {
			sendBytes = Array(bodyBytes[0..<maxSize])
			bodyBytes = Array(bodyBytes[maxSize..<bodyBytes.count])
			moreToCome = true
		} else {
			sendBytes = bodyBytes
			bodyBytes = []
			moreToCome = false
		}
		windowSize -= sendBytes.count
		var frame = HTTP2Frame(type: .data,
		                       flags: (!moreToCome && final) ? flagEndStream : 0,
		                       streamId: h2Request.streamId,
		                       payload: sendBytes)
		if moreToCome {
			frame.sentCallback = {
				ok in
				guard ok else { return self.removeRequest() }
				self.pushBody(final: final, callback: callback)
			}
		} else {
			frame.sentCallback = {
				ok in
				guard ok else { return self.removeRequest() }
				callback(ok)
			}
		}
		frameWriter?.enqueueFrame(frame)
		
	}
	
	func push(callback: @escaping (Bool) -> ()) {
		pushHeaders {
			ok in
			guard ok else {
				self.removeRequest()
				return callback(false)
			}
			self.pushBody(final: false) {
				ok in
				guard ok else {
					self.removeRequest()
					return callback(false)
				}
				callback(true)
			}
		}
	}
	
	func completed() {
		pushHeaders {
			ok in
			guard ok else { return }
			self.pushBody(final: true) {
				ok in
				guard ok else { return }
				self.removeRequest()
			}
		}
	}
	
	func removeRequest() {
		let req = h2Request
		req.session?.removeRequest(req.streamId)
	}
}
