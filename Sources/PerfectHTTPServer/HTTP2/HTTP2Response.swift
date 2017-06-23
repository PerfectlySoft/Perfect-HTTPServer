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

final class HTTP2Response: HTTPResponse {
	var request: HTTPRequest
	var h2Request: HTTP2Request { return request as! HTTP2Request }
	var status: HTTPResponseStatus = .ok
	var isStreaming = false
	var bodyBytes: [UInt8] = []
	var headerStore = Array<(HTTPResponseHeader.Name, String)>()
	let filters: IndexingIterator<[[HTTPResponseFilter]]>?
	var encoder: HPACKEncoder { return h2Request.session!.encoder }
	var wroteHeaders = false
	
	init(_ request: HTTP2Request, filters: IndexingIterator<[[HTTPResponseFilter]]>? = nil) {
		self.request = request
		self.filters = filters
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
	
	func pushHeaders() {
		guard !wroteHeaders else {
			return
		}
		wroteHeaders = true
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
		h2Request.session?.frameWriter?.enqueueFrame(frame)
	}
	
	func pushBody(final: Bool) {
		let frame = HTTP2Frame(type: .data, flags: final ? flagEndStream : 0, streamId: h2Request.streamId, payload: bodyBytes)
		h2Request.session?.frameWriter?.enqueueFrame(frame)
	}
	
	func push(callback: @escaping (Bool) -> ()) {
		pushHeaders()
		pushBody(final: false)
	}
	
	func completed() {
		pushHeaders()
		pushBody(final: true)
		h2Request.session?.removeRequest(h2Request.streamId)
	}
}
