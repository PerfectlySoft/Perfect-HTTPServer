//
//  HTTP11Request.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 2016-06-21.
//	Copyright (C) 2016 PerfectlySoft, Inc.
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

import PerfectNet
import PerfectThread
import PerfectLib
import PerfectHTTP
import PerfectCHTTPParser

private let httpMaxHeadersSize = 1024 * 8

private let characterCR: Character = "\r"
private let characterLF: Character = "\n"
private let characterCRLF: Character = "\r\n"
private let characterSP: Character = " "
private let characterHT: Character = "\t"
private let characterColon: Character = ":"

private let httpReadSize = 1024 * 8
private let httpReadTimeout = 5.0

let httpLF: UInt8 = 10
let httpCR: UInt8 = 13

private let httpSpace = UnicodeScalar(32)
private let httpQuestion = UnicodeScalar(63)


class HTTP11Request: HTTPRequest {
	var method: HTTPMethod = .get
	var path: String {
		get {
			var accum = ""
			var lastSlashExplicit = false
			for p in pathComponents {
				if p == "/" {
					accum += p
					lastSlashExplicit = true
				} else {
					if !lastSlashExplicit {
						accum += "/"
					}
					accum += p.stringByEncodingURL
					lastSlashExplicit = false
				}
			}
			return accum
		}
		set {
			let components = newValue.filePathComponents.map { $0 == "/" ? "/" : $0.stringByDecodingURL ?? "" }
			pathComponents = components
		}
	}
	var pathComponents = [String]()
	var queryString = ""
	
	lazy var queryParams: [(String, String)] = {
		return self.deFormURLEncoded(string: self.queryString)
	}()
	
	var protocolVersion = (1, 0)
	var remoteAddress: (host: String, port: UInt16) {
		guard let remote = connection.remoteAddress else {
			return ("", 0)
		}
		return (remote.host, remote.port)
	}
	var serverAddress: (host: String, port: UInt16) {
		guard let local = connection.localAddress else {
			return ("", 0)
		}
		return (local.host, local.port)
	}
	var serverName = ""
	var documentRoot = "./webroot"
	var urlVariables = [String:String]()
	var scratchPad = [String:Any]()
	
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
	
	lazy var postParams: [(String, String)] = {
		
		if let mime = self.mimes {
			return mime.bodySpecs.filter { $0.file == nil }.map { ($0.fieldName, $0.fieldValue) }
		} else if let bodyString = self.postBodyString {
			return self.deFormURLEncoded(string: bodyString)
		}
		return [(String, String)]()
	}()
	
	var postBodyBytes: [UInt8]? {
		get {
			if let _ = mimes {
				return nil
			}
			return workingBuffer
		}
		set {
			if let nv = newValue {
				workingBuffer = nv
			} else {
				workingBuffer.removeAll()
			}
		}
	}
	var postBodyString: String? {
		guard let bytes = postBodyBytes else {
			return nil
		}
		if bytes.isEmpty {
			return ""
		}
		return UTF8Encoding.encode(bytes: bytes)
	}
	var postFileUploads: [MimeReader.BodySpec]? {
		guard let mimes = self.mimes else {
			return nil
		}
		return mimes.bodySpecs
	}
	
	var connection: NetTCP
	var workingBuffer = [UInt8]()
	var workingBufferOffset = 0
	
	var mimes: MimeReader?
	
	var contentType: String? {
		guard let v = self.headerStore[.contentType] else {
			return nil
		}
		return UTF8Encoding.encode(bytes: v)
	}
	
	lazy var contentLength: Int = {
		guard let cl = self.headerStore[.contentLength] else {
			return 0
		}
		let conv = UTF8Encoding.encode(bytes: cl)
		return Int(conv) ?? 0
	}()
	
	typealias StatusCallback = (HTTPResponseStatus) -> ()
	
	var parser = http_parser()
	var parserSettings = http_parser_settings()
	
	enum State {
		case none, messageBegin, messageComplete, headersComplete, headerField, headerValue, body, url
	}
	
	var state = State.none
	var lastHeaderName: String?
	
	static func getSelf(parser: UnsafeMutablePointer<http_parser>) -> HTTP11Request? {
		guard let d = parser.pointee.data else { return nil }
		return Unmanaged<HTTP11Request>.fromOpaque(d).takeUnretainedValue()
	}
	
	init(connection: NetTCP) {
		self.connection = connection
		
		parserSettings.on_message_begin = {
			parser -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserMessageBegin(parser) ?? 0)
		}
		
		parserSettings.on_message_complete = {
			parser -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserMessageComplete(parser) ?? 0)
		}
		
		parserSettings.on_headers_complete = {
			parser -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserHeadersComplete(parser) ?? 0)
		}
		
		parserSettings.on_header_field = {
			(parser, chunk, length) -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserHeaderField(parser, data: chunk, length: length) ?? 0)
		}
		
		parserSettings.on_header_value = {
			(parser, chunk, length) -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserHeaderValue(parser, data: chunk, length: length) ?? 0)
		}
		
		parserSettings.on_body = {
			(parser, chunk, length) -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserBody(parser, data: chunk, length: length) ?? 0)
		}
		
		parserSettings.on_url = {
			(parser, chunk, length) -> Int32 in
			guard let parser = parser else { return 0 }
			return Int32(HTTP11Request.getSelf(parser: parser)?.parserURL(parser, data: chunk, length: length) ?? 0)
		}
		http_parser_init(&parser, HTTP_REQUEST)
		
		self.parser.data = Unmanaged.passUnretained(self).toOpaque()
	}
	
	func parserMessageBegin(_ parser: UnsafePointer<http_parser>) -> Int {
		self.enteringState(parser, .messageBegin, data: nil, length: 0)
		return 0
	}
	
	func parserMessageComplete(_ parser: UnsafePointer<http_parser>) -> Int {
		self.enteringState(parser, .messageComplete, data: nil, length: 0)
		return 0
	}
	
	func parserHeadersComplete(_ parser: UnsafePointer<http_parser>) -> Int {
		self.enteringState(parser, .headersComplete, data: nil, length: 0)
		return 0
	}
	
	func parserURL(_ parser: UnsafePointer<http_parser>, data: UnsafePointer<Int8>?, length: Int) -> Int {
		self.enteringState(parser, .url, data: data, length: length)
		return 0
	}
	
	func parserHeaderField(_ parser: UnsafePointer<http_parser>, data: UnsafePointer<Int8>?, length: Int) -> Int {
		self.enteringState(parser, .headerField, data: data, length: length)
		return 0
	}
	
	func parserHeaderValue(_ parser: UnsafePointer<http_parser>, data: UnsafePointer<Int8>?, length: Int) -> Int {
		self.enteringState(parser, .headerValue, data: data, length: length)
		return 0
	}
	
	func parserBody(_ parser: UnsafePointer<http_parser>, data: UnsafePointer<Int8>?, length: Int) -> Int {
		if self.state != .body {
			self.leavingState(parser)
			self.state = .body
		}
		if self.workingBuffer.count == 0 && self.mimes == nil {
			if let contentType = self.contentType,
				contentType.characters.starts(with: "multipart/form-data".characters) {
				self.mimes = MimeReader(contentType)
			}
		}
		data?.withMemoryRebound(to: UInt8.self, capacity: length) {
			data in
			for i in 0..<length {
				self.workingBuffer.append(data[i])
			}
		}
		if let mimes = self.mimes {
			defer {
				self.workingBuffer.removeAll()
			}
			mimes.addToBuffer(bytes: self.workingBuffer)
		}
		return 0
	}
	
	func enteringState(_ parser: UnsafePointer<http_parser>, _ state: State, data: UnsafePointer<Int8>?, length: Int) {
		if self.state != state {
			self.leavingState(parser)
			self.state = state
		}
		data?.withMemoryRebound(to: UInt8.self, capacity: length) {
			data in
			for i in 0..<length {
				self.workingBuffer.append(data[i])
			}
		}
	}
	
	// parse from workingBuffer contents
	func parseURI() -> ([String], String) {
		enum ParseURLState {
			case slash, component, query
		}
		var state = ParseURLState.slash
		var gen = workingBuffer.makeIterator()
		var decoder = UTF8()
		var pathComponents = ["/"]
		var component = ""
		var queryString = ""
		
		let question = UnicodeScalar(63)
		let slash = UnicodeScalar(47)
		
		loopy:
			repeat {
				let res = decoder.decode(&gen)
				switch res {
				case .scalarValue(let uchar):
					switch state {
					case .slash:
						if uchar == question {
							state = .query
							if pathComponents.count > 1 {
								pathComponents.append("/")
							}
						} else if uchar != slash {
							state = .component
							component = String(Character(uchar))
						}
					case .component:
						if uchar == question {
							state = .query
							pathComponents.append(component.stringByDecodingURL ?? "")
						} else if uchar == slash {
							state = .slash
							pathComponents.append(component.stringByDecodingURL ?? "")
						} else {
							component.append(Character(uchar))
						}
					case .query:
						queryString.append(Character(uchar))
					}
				case .emptyInput, .error:
					switch state {
					case .slash:
						if pathComponents.count > 1 {
							pathComponents.append("/")
						}
					case .component:
						pathComponents.append(component.stringByDecodingURL ?? "")
					case .query:
						()
					}
					break loopy
				}
		} while true
		return (pathComponents, queryString)
	}
	
	func leavingState(_ parser: UnsafePointer<http_parser>) {
		switch state {
		case .url:
			(self.pathComponents, self.queryString) = parseURI()
			workingBuffer.removeAll()
		case .headersComplete:
			let methodId = parser.pointee.method
			if let methodName = http_method_str(http_method(rawValue: methodId)) {
				self.method = HTTPMethod.from(string: String(validatingUTF8: methodName) ?? "GET")
			}
			protocolVersion = (Int(parser.pointee.http_major), Int(parser.pointee.http_minor))
			workingBuffer.removeAll()
			if let expect = header(.expect), expect.lowercased() == "100-continue" {
				// TODO: Should let headers be passed to filters and let them 
				// determine if request should continue or not
				_ = connection.writeFully(bytes: Array("HTTP/1.1 100 Continue\r\n\r\n".utf8))
			}
		case .headerField:
			workingBuffer.append(0)
			lastHeaderName = String(validatingUTF8: UnsafeMutableRawPointer(mutating: workingBuffer).assumingMemoryBound(to: Int8.self))
			workingBuffer.removeAll()
		case .headerValue:
			if let name = self.lastHeaderName {
				setHeader(named: name, value: self.workingBuffer)
			}
			lastHeaderName = nil
			workingBuffer.removeAll()
		case .body:
			()
		case .messageComplete:
			()
		case .messageBegin, .none:
			()
		}
	}
	
	func header(_ named: HTTPRequestHeader.Name) -> String? {
		guard let v = headerStore[named] else {
			return nil
		}
		return UTF8Encoding.encode(bytes: v)
	}
	
	func addHeader(_ named: HTTPRequestHeader.Name, value: String) {
		guard let existing = headerStore[named] else {
			self.headerStore[named] = [UInt8](value.utf8)
			return
		}
		let valueBytes = [UInt8](value.utf8)
		let newValue: [UInt8]
		if named == .cookie {
			newValue = existing + "; ".utf8 + valueBytes
		} else {
			newValue = existing + ", ".utf8 + valueBytes
		}
		self.headerStore[named] = newValue
	}
	
	func setHeader(_ named: HTTPRequestHeader.Name, value: String) {
		headerStore[named] = [UInt8](value.utf8)
	}
	
	func setHeader(named: String, value: [UInt8]) {
		headerStore[HTTPRequestHeader.Name.fromStandard(name: named)] = value
	}
	
	func readRequest(callback: @escaping StatusCallback) {
		self.connection.readSomeBytes(count: httpReadSize) {
			b in
			if let b = b, b.count > 0 {
				if self.didReadSomeBytes(b, callback: callback) {
					if b.count == httpReadSize {
						Threading.dispatch {
							self.readRequest(callback: callback)
						}
					} else {
						self.readRequest(callback: callback)
					}
				}
			} else {
				self.connection.readBytesFully(count: 1, timeoutSeconds: httpReadTimeout) {
					b in
					guard let b = b else {
						return callback(.requestTimeout)
					}
					if self.didReadSomeBytes(b, callback: callback) {
						self.readRequest(callback: callback)
					}
				}
			}
		}
	}
	
	// a true return value indicates that we should keep reading data
	// false indicates that the request either was fully read and is being processed or that the request failed
	//	either way no further action should be taken
	func didReadSomeBytes(_ b: [UInt8], callback: @escaping StatusCallback) -> Bool {
		_ = UnsafePointer(b).withMemoryRebound(to: Int8.self, capacity: b.count) {
			http_parser_execute(&parser, &parserSettings, $0, b.count)
		}
		let http_errno = parser.http_errno
		guard HPE_HEADER_OVERFLOW.rawValue != http_errno else {
			callback(.requestEntityTooLarge)
			return false
		}
		guard http_errno == 0 else {
			callback(.badRequest)
			return false
		}
		if self.state == .messageComplete {
			callback(.ok)
			return false
		}
		return true
	}
	
	func putPostData(_ b: [UInt8]) {
		if self.workingBuffer.count == 0 && self.mimes == nil {
			if let contentType = self.contentType,
				contentType.characters.starts(with: "multipart/form-data".characters) {
				self.mimes = MimeReader(contentType)
			}
		}
		if let mimes = self.mimes {
			return mimes.addToBuffer(bytes: b)
		} else {
			self.workingBuffer.append(contentsOf: b)
		}
	}
	
	func deFormURLEncoded(string: String) -> [(String, String)] {
		return string.characters.split(separator: "&").map(String.init).flatMap {
			let d = $0.characters.split(separator: "=", maxSplits: 1).flatMap { String($0).stringByDecodingURL }
			if d.count == 2 { return (d[0], d[1]) }
			if d.count == 1 { return (d[0], "") }
			return nil
		}
	}
}
