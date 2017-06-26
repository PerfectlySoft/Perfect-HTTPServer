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
import PerfectThread

final class HTTP2Request: HTTPRequest, HeaderListener {
	var method: HTTPMethod = .get
	var path: String = ""
	var scheme = ""
	var authority = ""
	var pathComponents: [String] { return path.filePathComponents }
	var queryParams: [(String, String)] = []
	var protocolVersion = (2, 0)
	var remoteAddress = (host: "", port: 0 as UInt16)
	var serverAddress = (host: "", port: 0 as UInt16)
	var serverName = ""
	var documentRoot = ""
	var connection: NetTCP
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
		guard let v = headerStore[named] else {
			return nil
		}
		return UTF8Encoding.encode(bytes: v)
	}
	func addHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	func setHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	var postParams: [(String, String)]  = []
	var postBodyBytes: [UInt8]?  = nil
	var postBodyString: String? = nil
	var postFileUploads: [MimeReader.BodySpec]? = nil
	
	weak var session: HTTP2Session?
	var decoder: HPACKDecoder { return session!.decoder }
	let streamId: UInt32
	var streamState = HTTP2StreamState.idle
	var windowSize = Int.max {
		didSet {
			windowSizeChanged?()
		}
	}
	var endOfHeaders = false
	var windowSizeChanged: (() -> ())? = nil
	var debug: Bool { return session?.debug ?? false }
	var mimes: MimeReader?
	
	init(_ streamId: UInt32, session: HTTP2Session) {
		self.connection = session.net
		self.streamId = streamId
		self.session = session
	}
	
	deinit {
		if debug { print("~HTTP2Request \(streamId)") }
	}
	
	func headersFrame(_ frame: HTTP2Frame) {
		let endOfStream = (frame.flags & flagEndStream) != 0
		if endOfStream {
			streamState = .halfClosed
		} else {
			streamState = .open
		}
		endOfHeaders = (frame.flags & flagEndHeaders) != 0
		if debug {
			print("\tstream: \(streamId)")
		}
		let padded = (frame.flags & flagPadded) != 0
		let priority = (frame.flags & flagPriority) != 0
		if let ba = frame.payload, ba.count > 0 {
			let bytes = Bytes(existingBytes: ba)
			var padLength: UInt8 = 0
			if padded {
				padLength = bytes.export8Bits()
				bytes.data.removeLast(Int(padLength))
			}
			if priority {
				let _/*streamDep*/ = bytes.export32Bits()
				let _/*weight*/ = bytes.export8Bits()
			}
			do {
				decoder.reset()
				try decoder.decode(input: bytes, headerListener: self)
			} catch {
				session?.fatalError(streamId: streamId, error: .compressionError, msg: "error while decoding headers \(error)")
				streamState = .closed
			}
		}
		if endOfHeaders && endOfStream {
			processRequest()
		}
	}
	
	func continuationFrame(_ frame: HTTP2Frame) {
		guard !endOfHeaders, streamState == .open else {
			session?.fatalError(streamId: streamId, error: .protocolError, msg: "Invalid frame")
			return
		}
		let endOfStream = (frame.flags & flagEndStream) != 0
		if endOfStream {
			streamState = .halfClosed
		}
		endOfHeaders = (frame.flags & flagEndHeaders) != 0
		if debug {
			print("\tstream: \(streamId)")
		}
		if let ba = frame.payload, ba.count > 0 {
			let bytes = Bytes(existingBytes: ba)
			do {
				try decoder.decode(input: bytes, headerListener: self)
			} catch {
				session?.fatalError(streamId: streamId, error: .compressionError, msg: "error while decoding headers \(error)")
				streamState = .closed
			}
		}
		if endOfHeaders && endOfStream {
			processRequest()
		}
	}
	
	func dataFrame(_ frame: HTTP2Frame) {
		putPostData(frame.payload ?? [])
		let endOfStream = (frame.flags & flagEndStream) != 0
		if endOfStream {
			processRequest()
		}
	}
	
	func priorityFrame(_ frame: HTTP2Frame) {
		
	}
	
	func cancelStreamFrame(_ frame: HTTP2Frame) {
		streamState = .closed
	}
	
	func windowUpdate(_ size: Int) {
		windowSize += size
	}
	
	func putPostData(_ b: [UInt8]) {
		if let mimes = self.mimes {
			return mimes.addToBuffer(bytes: b)
		} else {
			if nil == postBodyBytes {
				postBodyBytes = b
			} else {
				postBodyBytes?.append(contentsOf: b)
			}
		}
	}
	
	func processRequest() {
		let response = HTTP2Response(self)
		Threading.dispatch { // get off the frame read thread
			self.routeRequest(response: response)
		}
	}
	
	func routeRequest(response: HTTPResponse) {
		if let nav = session?.routeNavigator, let handler = nav.findHandler(pathComponents: pathComponents, webRequest: self) {
			handler(self, response)
		} else {
			response.status = .notFound
			response.appendBody(string: "The file \(path) was not found.")
			response.completed()
		}
	}
	
	// scheme, authority
	func addHeader(name: [UInt8], value: [UInt8], sensitive: Bool) {
		let n = String(validatingUTF8: name) ?? ""
		switch n {
		case ":method":
			method = HTTPMethod.from(string: String(validatingUTF8: value) ?? "")
		case ":path":
			path = UTF8Encoding.encode(bytes: value)
		case ":scheme":
			scheme = UTF8Encoding.encode(bytes: value)
		case ":authority":
			authority = UTF8Encoding.encode(bytes: value)
		default:
			let headerName = HTTPRequestHeader.Name.fromStandard(name: n)
			if headerName == .contentType {
				let contentType = String(validatingUTF8: value) ?? ""
				if contentType.characters.starts(with: "multipart/form-data".characters) {
					self.mimes = MimeReader(contentType)
				}
			}
			headerStore[headerName] = value
		}
		if debug {
			print("\t\(n): \(UTF8Encoding.encode(bytes: value))")
		}
	}
	
	func streamFrameRead(_ frame: HTTP2Frame) {
		if !endOfHeaders {
//			guard frame.type == .continuation else {
//				
//			}
		}
	}
}




