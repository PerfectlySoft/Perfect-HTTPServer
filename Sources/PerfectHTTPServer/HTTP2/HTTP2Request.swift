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

import PerfectHTTP
import PerfectNet
import PerfectLib

final class HTTP2Request: HTTPRequest {
	var method: HTTPMethod = .get
	var path: String = ""
	var pathComponents: [String] = []
	var queryParams: [(String, String)] = []
	var protocolVersion = (2, 0)
	var remoteAddress = (host: "", port: 0 as UInt16)
	var serverAddress = (host: "", port: 0 as UInt16)
	var serverName = ""
	var documentRoot = ""
	var connection: NetTCP = NetTCP() // !FIX!
	var urlVariables: [String:String] = [:]
	var scratchPad: [String:Any] = [:]
	private var headerStore = Dictionary<HTTPRequestHeader.Name, [UInt8]>()
	var headers: AnyIterator<(HTTPRequestHeader.Name, String)> {
		var g = self.headerStore.makeIterator()
		return AnyIterator<(HTTPRequestHeader.Name, String)> {
			guard let n = g.next() else {
				return nil
			}
			return (n.key, UTF8Encoding.encode(bytes: n.value))
		}
	}
	func header(_ named: HTTPRequestHeader.Name) -> String? {
		return nil
	}
	func addHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	func setHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	var postParams: [(String, String)]  = []
	var postBodyBytes: [UInt8]?  = nil
	var postBodyString: String? = nil
	var postFileUploads: [MimeReader.BodySpec]? = nil
	
	init(connection: NetTCP) {}
	
	let frameWriter: HTTP2FrameWriter
	
	init(_ frame: HTTP2Frame, frameReader: HTTP2FrameReader, frameWriter: HTTP2FrameWriter) {
		self.frameWriter = frameWriter
		frameReader.subscribe(stream: Int(frame.streamId), streamFrameRead)
	}
	
	func streamFrameRead(_ frame: HTTP2Frame) {
		
	}
}




