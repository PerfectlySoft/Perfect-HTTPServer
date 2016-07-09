//
//  HTTP11Response.swift
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

#if os(OSX)
	import Darwin
#else
	import SwiftGlibc
#endif

import PerfectNet
import PerfectThread
import PerfectHTTP

class HTTP11Response: HTTPResponse {
    var status = HTTPResponseStatus.ok
    var headerStore = Array<(HTTPResponseHeader.Name, String)>()
    var bodyBytes = [UInt8]()
    
    var headers: AnyIterator<(HTTPResponseHeader.Name, String)> {
        var g = self.headerStore.makeIterator()
        return AnyIterator<(HTTPResponseHeader.Name, String)> {
            g.next()
        }
    }
    
    var connection: NetTCP {
        return request.connection
    }
    
    var isStreaming = false
    var wroteHeaders = false
    var completedCallback: (() -> ())?
    let request: HTTPRequest
    
    lazy var isKeepAlive: Bool = {
        // http 1.1 is keep-alive unless otherwise noted
        // http 1.0 is keep-alive if specifically noted
        // check header first
        if let connection = self.request.header(.connection) {
            if connection.lowercased() == "keep-alive" {
                return true
            }
            return false
        }
        return self.isHTTP11
    }()
    
    var isHTTP11: Bool {
        let version = self.request.protocolVersion
        return version.0 == 1 && version.1 == 1
    }
	
	let filters: IndexingIterator<[[HTTPResponseFilter]]>?
	
	init(request: HTTPRequest, filters: IndexingIterator<[[HTTPResponseFilter]]>? = nil) {
        self.request = request
		self.filters = filters
        let net = request.connection
        self.completedCallback = {
            net.close()
        }
    }
    
    func completed() {
        if let cb = self.completedCallback {
            cb()
        }
    }
	
	func abort() {
		self.completedCallback = nil
		self.connection.close()
	}
    
    func header(_ named: HTTPResponseHeader.Name) -> String? {
        for (n, v) in headerStore where n == named {
            return v
        }
        return nil
    }
    
    func addHeader(_ name: HTTPResponseHeader.Name, value: String) {
        headerStore.append((name, value))
    }
    
    func setHeader(_ name: HTTPResponseHeader.Name, value: String) {
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
        addHeader(name, value: value)
    }
	
    func flush(callback: (Bool) -> ()) {
        self.push {
            ok in
            guard ok else {
                return callback(false)
            }
            if self.isStreaming {
				self.pushNonStreamed(bytes: Array("0\r\n\r\n".utf8), callback: callback)
            } else {
                callback(true)
            }
        }
    }
    
    func pushHeaders(callback: (Bool) -> ()) {
        wroteHeaders = true
        if isKeepAlive {
            addHeader(.connection, value: "Keep-Alive")
        }
        if isStreaming {
            addHeader(.transferEncoding, value: "chunked")
        } else if nil == header(.contentLength) {
            setHeader(.contentLength, value: "\(bodyBytes.count)")
        }
		if let filters = self.filters {
			return filterHeaders(allFilters: filters, callback: callback)
		}
		finishPushHeaders(callback: callback)
    }
	
	func filterHeaders(allFilters: IndexingIterator<[[HTTPResponseFilter]]>, callback: (Bool) -> ()) {
		var allFilters = allFilters
		if let prioFilters = allFilters.next() {
			return filterHeaders(allFilters: allFilters, prioFilters: prioFilters.makeIterator(), callback: callback)
		}
		finishPushHeaders(callback: callback)
	}
	
	func filterHeaders(allFilters: IndexingIterator<[[HTTPResponseFilter]]>,
	                   prioFilters: IndexingIterator<[HTTPResponseFilter]>,
	                   callback: (Bool) -> ()) {
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

	func finishPushHeaders(callback: (Bool) -> ()) {
		var responseString = "HTTP/\(request.protocolVersion.0).\(request.protocolVersion.1) \(status)\r\n"
		for (n, v) in headers {
			responseString.append("\(n.standardName): \(v)\r\n")
		}
		responseString.append("\r\n")
		connection.write(string: responseString) {
			sent in
			guard sent > 0 else {
				return self.abort()
			}
			self.push(callback: callback)
		}
	}
	
	func filterBodyBytes(allFilters: IndexingIterator<[[HTTPResponseFilter]]>, callback: (bodyBytes: [UInt8]) -> ()) {
		var allFilters = allFilters
		if let prioFilters = allFilters.next() {
			return filterBodyBytes(allFilters: allFilters, prioFilters: prioFilters.makeIterator(), callback: callback)
		}
		finishFilterBodyBytes(callback: callback)
	}
	
	func filterBodyBytes(allFilters: IndexingIterator<[[HTTPResponseFilter]]>,
	                     prioFilters: IndexingIterator<[HTTPResponseFilter]>,
	                     callback: (bodyBytes: [UInt8]) -> ()) {
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
	
	func finishFilterBodyBytes(callback: (bodyBytes: [UInt8]) -> ()) {
		let bytes = self.bodyBytes
		self.bodyBytes = [UInt8]()
		callback(bodyBytes: bytes)
	}
	
	func filteredBodyBytes(callback: (bodyBytes: [UInt8]) -> ()) {
		if let filters = self.filters {
			return filterBodyBytes(allFilters: filters, callback: callback)
		}
		finishFilterBodyBytes(callback: callback)
	}
	
    func push(callback: (Bool) -> ()) {
        if !wroteHeaders {
            return pushHeaders(callback: callback)
		}
		filteredBodyBytes {
			bytes in
			if self.isStreaming {
				return self.pushStreamed(bytes: bytes, callback: callback)
			}
			self.pushNonStreamed(bytes: bytes, callback: callback)
		}
    }
    
    func pushStreamed(bytes: [UInt8], callback: (Bool) -> ()) {
		let bodyCount = bytes.count
		guard bodyCount > 0 else {
			return callback(true)
		}
		let hexString = "\(String(bodyCount, radix: 16, uppercase: true))\r\n"
		let sendA = Array(hexString.utf8)
		self.pushNonStreamed(bytes: sendA) {
			ok in
			guard ok else {
				return self.abort()
			}
			self.pushNonStreamed(bytes: bytes) {
				ok in
				guard ok else {
					return self.abort()
				}
				self.pushNonStreamed(bytes: Array("\r\n".utf8), callback: callback)
			}
		}
    }
    
    func pushNonStreamed(bytes: [UInt8], callback: (Bool) -> ()) {
        let bodyCount = bytes.count
        guard bodyCount > 0 else {
            return callback(true)
        }
        connection.write(bytes: bytes) {
            sent in
            guard bodyCount == sent else {
                return self.abort()
            }
            Threading.dispatch {
                callback(true)
            }
        }
    }
}
