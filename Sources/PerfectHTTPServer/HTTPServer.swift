//
//	HTTPServer.swift
//	PerfectLib
//
//	Created by Kyle Jessup on 2015-10-23.
//	Copyright (C) 2015 PerfectlySoft, Inc.
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

#if os(Linux)
	import SwiftGlibc
	import LinuxBridge
#else
	import Darwin
#endif

/// Stand-alone HTTP server.
open class HTTPServer {
	
	public var net: NetTCP?
	
	/// The directory in which web documents are sought.
	/// Setting the document root will add a default URL route which permits
	/// static files to be served from within.
	public var documentRoot = "./webroot" { // Given a "safe" default
		didSet {
			// !FIX! add default route
			do {
				let dir = Dir(documentRoot)
				if !dir.exists {
					try Dir(documentRoot).create()
				}
				self.routes.add(method: .get, uri: "/**", handler: {
					request, response in
					StaticFileHandler(documentRoot: request.documentRoot).handleRequest(request: request, response: response)
				})
			} catch {
				Log.terminal(message: "The document root \(documentRoot) could not be created.")
			}
		}
	}
	/// The port on which the server is listening.
	public var serverPort: UInt16 = 0
	/// The local address on which the server is listening. The default of 0.0.0.0 indicates any address.
	public var serverAddress = "0.0.0.0"
	/// Switch to user after binding port
	public var runAsUser: String?
	
	/// The canonical server name.
	/// This is important if utilizing the `HTTPRequest.serverName` property.
	public var serverName = ""
	public var ssl: (sslCert: String, sslKey: String)?
	public var caCert: String?
	public var certVerifyMode: OpenSSLVerifyMode?
	public var tlsMethod: TLSMethod = .tlsV1_2
  
	public var cipherList = [
		"ECDHE-ECDSA-AES256-GCM-SHA384",
		"ECDHE-ECDSA-AES128-GCM-SHA256",
		"ECDHE-ECDSA-AES256-CBC-SHA384",
		"ECDHE-ECDSA-AES256-CBC-SHA",
		"ECDHE-ECDSA-AES128-CBC-SHA256",
		"ECDHE-ECDSA-AES128-CBC-SHA",
		"ECDHE-RSA-AES256-GCM-SHA384",
		"ECDHE-RSA-AES128-GCM-SHA256",
		"ECDHE-RSA-AES256-CBC-SHA384",
		"ECDHE-RSA-AES128-CBC-SHA256",
		"ECDHE-RSA-AES128-CBC-SHA",
		"ECDHE-RSA-AES256-SHA384",
		"ECDHE-ECDSA-AES256-SHA384",
		"ECDHE-RSA-AES256-SHA",
		"ECDHE-ECDSA-AES256-SHA"]
	
	private var requestFilters = [[HTTPRequestFilter]]()
	private var responseFilters = [[HTTPResponseFilter]]()
	
	/// Routing support
	private var routes = Routes()
	private var routeNavigator: RouteNavigator?
	
	/// Initialize the server object.
	public init() {}
	
	@available(*, deprecated, message: "Set documentRoot directly")
	public init(documentRoot: String) {
		self.documentRoot = documentRoot
	}
	
	/// Add the Routes to this server.
	public func addRoutes(_ routes: Routes) {
		self.routes.add(routes)
	}
	
	/// Set the request filters. Each is provided along with its priority.
	/// The filters can be provided in any order. High priority filters will be sorted above lower priorities.
	/// Filters of equal priority will maintain the order given here.
	@discardableResult
	public func setRequestFilters(_ request: [(HTTPRequestFilter, HTTPFilterPriority)]) -> HTTPServer {
		let high = request.filter { $0.1 == HTTPFilterPriority.high }.map { $0.0 },
		                                                                  med = request.filter { $0.1 == HTTPFilterPriority.medium }.map { $0.0 },
		                                                                                                                                 low = request.filter { $0.1 == HTTPFilterPriority.low }.map { $0.0 }
		requestFilters.append(high)
		requestFilters.append(med)
		requestFilters.append(low)
		return self
	}
	
	/// Set the response filters. Each is provided along with its priority.
	/// The filters can be provided in any order. High priority filters will be sorted above lower priorities.
	/// Filters of equal priority will maintain the order given here.
	@discardableResult
	public func setResponseFilters(_ response: [(HTTPResponseFilter, HTTPFilterPriority)]) -> HTTPServer {
		let high = response.filter { $0.1 == HTTPFilterPriority.high }.map { $0.0 },
		                                                                   med = response.filter { $0.1 == HTTPFilterPriority.medium }.map { $0.0 },
		                                                                                                                                   low = response.filter { $0.1 == HTTPFilterPriority.low }.map { $0.0 }
		responseFilters.append(high)
		responseFilters.append(med)
		responseFilters.append(low)
		return self
	}
	
	@available(*, deprecated, message: "Set serverPort and call start()")
	public func start(port: UInt16, bindAddress: String = "0.0.0.0") throws {
		self.serverPort = port
		self.serverAddress = bindAddress
		try self.start()
	}
	
	@available(*, deprecated, message: "Set serverPort and ssl directly then call start()")
	public func start(port: UInt16, sslCert: String, sslKey: String, bindAddress: String = "0.0.0.0") throws {
		self.serverPort = port
		self.serverAddress = bindAddress
		self.ssl = (sslCert: sslCert, sslKey: sslKey)
		try self.start()
	}
	
	/// Bind the server to the designated address/port
  open func bind() throws {
		if let (cert, key) = ssl {
      let socket = NetTCPSSL()
      socket.tlsMethod = self.tlsMethod
			try socket.bind(port: serverPort, address: serverAddress)
			socket.cipherList = self.cipherList
			
			if let verifyMode = certVerifyMode,
				let cert = caCert,
				verifyMode != .sslVerifyNone {
				
				guard socket.setClientCA(path: cert, verifyMode: verifyMode) else {
					let code = Int32(socket.errorCode())
					throw PerfectError.networkError(code, "Error setting clientCA : \(socket.errorStr(forCode: code))")
				}
			}
			
			guard socket.useCertificateChainFile(cert: cert) else {
				let code = Int32(socket.errorCode())
				throw PerfectError.networkError(code, "Error setting certificate chain file: \(socket.errorStr(forCode: code))")
			}
			guard socket.usePrivateKeyFile(cert: key) else {
				let code = Int32(socket.errorCode())
				throw PerfectError.networkError(code, "Error setting private key file: \(socket.errorStr(forCode: code))")
			}
			guard socket.checkPrivateKey() else {
				let code = Int32(socket.errorCode())
				throw PerfectError.networkError(code, "Error validating private key file: \(socket.errorStr(forCode: code))")
			}
			self.net = socket
		} else {
			let net = NetTCP()
			try net.bind(port: serverPort, address: serverAddress)
			self.net = net
		}
	}
	
	/// Start the server. Does not return until the server terminates.
	public func start() throws {
		if nil == self.net {
			try bind()
		}
		guard let net = self.net else {
			throw PerfectError.networkError(-1, "The socket was not bound.")
		}
		let witess = (net is NetTCPSSL) ? "HTTPS" : "HTTP"
		Log.info(message: "Starting \(witess) server \(self.serverName) on \(self.serverAddress):\(self.serverPort)")
		try self.startInner()
	}
	
	private func startInner() throws {
		// 1.0 compatability ONLY
		if let compatRoutes = compatRoutes {
			self.addRoutes(compatRoutes)
		}
		self.routeNavigator = self.routes.navigator
		
		guard let sock = self.net else {
			Log.terminal(message: "Server could not be started. Socket was not initialized.")
		}
		if let runAs = self.runAsUser {
			try PerfectServer.switchTo(userName: runAs)
		}
		sock.listen()
		
		var flag = 1
		_ = setsockopt(sock.fd.fd, Int32(IPPROTO_TCP), TCP_NODELAY, &flag, UInt32(MemoryLayout<Int32>.size))
		
		defer { sock.close() }
		self.serverAddress = sock.localAddress?.host ?? ""
		sock.forEachAccept {
			[weak self] net in
			guard let net = net else {
				return
			}
			Threading.dispatch {
				self?.handleConnection(net)
			}
		}
	}
	
	/// Stop the server by closing the accepting TCP socket. Calling this will cause the server to break out of the otherwise blocking `start` function.
	public func stop() {
		if let n = self.net {
			self.net = nil
			n.close()
		}
	}
	
	open func handleConnection(_ net: NetTCP) {
		#if os(Linux)
			var flag = 1
			_ = setsockopt(net.fd.fd, Int32(IPPROTO_TCP), TCP_NODELAY, &flag, UInt32(MemoryLayout<Int32>.size))
		#endif
		let req = HTTP11Request(connection: net)
		req.serverName = self.serverName
		req.readRequest { [weak self]
			status in
			if case .ok = status {
				self?.runRequest(req)
			} else {
				net.close()
			}
		}
	}
	
	func runRequest(_ request: HTTP11Request) {
		request.documentRoot = self.documentRoot
		let net = request.connection
		// !FIX! check for upgrade to http/2
		// switch to HTTP2Request/HTTP2Response
		
		let response = HTTP11Response(request: request, filters: responseFilters.isEmpty ? nil : responseFilters.makeIterator())
		if response.isKeepAlive {
			response.completedCallback = { [weak self] in
				if let `self` = self {
					Threading.dispatch {
						self.handleConnection(net)
					}
				}
			}
		}
		let oldCompletion = response.completedCallback
		response.completedCallback = {
			response.completedCallback = nil
			response.flush {
				ok in
				guard ok else {
					net.close()
					return
				}
				if let cb = oldCompletion {
					cb()
				}
			}
		}
		if requestFilters.isEmpty {
			routeRequest(request, response: response)
		} else {
			filterRequest(request, response: response, allFilters: requestFilters.makeIterator())
		}
	}
	
	private func filterRequest(_ request: HTTPRequest, response: HTTPResponse, allFilters: IndexingIterator<[[HTTPRequestFilter]]>) {
		var filters = allFilters
		if let prioFilters = filters.next() {
			filterRequest(request, response: response, allFilters: filters, prioFilters: prioFilters.makeIterator())
		} else {
			routeRequest(request, response: response)
		}
	}
	
	private func filterRequest(_ request: HTTPRequest, response: HTTPResponse,
	                           allFilters: IndexingIterator<[[HTTPRequestFilter]]>,
	                           prioFilters: IndexingIterator<[HTTPRequestFilter]>) {
		var prioFilters = prioFilters
		guard let filter = prioFilters.next() else {
			return filterRequest(request, response: response, allFilters: allFilters)
		}
		filter.filter(request: request, response: response) {
			result in
			switch result {
			case .continue(let req, let res):
				self.filterRequest(req, response: res, allFilters: allFilters, prioFilters: prioFilters)
			case .execute(let req, let res):
				self.filterRequest(req, response: res, allFilters: allFilters)
			case .halt(_, let res):
				res.completed()
			}
		}
	}
	
	private func routeRequest(_ request: HTTPRequest, response: HTTPResponse) {
		let pathInfo = request.path
		if let nav = self.routeNavigator, let handler = nav.findHandler(uri: pathInfo, webRequest: request) {
			handler(request, response)
		} else {
			response.status = .notFound
			response.appendBody(string: "The file \(pathInfo) was not found.")
			response.completed()
		}
	}
}
