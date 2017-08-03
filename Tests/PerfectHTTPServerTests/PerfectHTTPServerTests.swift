import XCTest
import PerfectLib
import PerfectNet
import PerfectThread
import PerfectHTTP
@testable import PerfectHTTPServer

func ShimHTTPRequest() -> HTTP11Request {
	return HTTP11Request(connection: NetTCP())
}

class PerfectHTTPServerTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		compatRoutes = nil
	}
	
	func testHPACKEncode() {
		
		let encoder = HPACKEncoder()
		let b = Bytes()
		
		let headers = [
//			(":method", "POST"),
//			(":scheme", "https"),
//			(":path", "/3/device/00fc13adff785122b4ad28809a3420982341241421348097878e577c991de8f0"),
//			("host", "api.development.push.apple.com"),
//			("apns-id", "eabeae54-14a8-11e5-b60b-1697f925ec7b"),
//			("apns-expiration", "0"),
//			("apns-priority", "10"),
//			("content-length", "33"),
			("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/603.2.4 (KHTML, like Gecko) Version/10.1.1 Safari/603.2.4")]
		do {
			for (n, v) in headers {
				try encoder.encodeHeader(out: b, name: UTF8Encoding.decode(string: n), value: UTF8Encoding.decode(string: v), sensitive: false)
			}
			
			class Listener: HeaderListener {
				var headers = [(String, String)]()
				func addHeader(name nam: [UInt8], value: [UInt8], sensitive: Bool) {
					self.headers.append((UTF8Encoding.encode(bytes: nam), UTF8Encoding.encode(bytes: value)))
				}
			}
			
			let decoder = HPACKDecoder()
			let l = Listener()
			try decoder.decode(input: b, headerListener: l)
			
			XCTAssert(l.headers.count == headers.count)
			
			for i in 0..<headers.count {
				let h1 = headers[i]
				let h2 = l.headers[i]
				
				XCTAssertEqual(h1.0, h2.0)
				XCTAssertEqual(h1.1, h2.1)
			}
			
		}
		catch {
			XCTAssert(false, "Exception \(error)")
		}
	}
	
	func testWebConnectionHeadersWellFormed() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\r\nX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertTrue(connection.header(.custom(name: "X-Foo")) == "bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "X-Bar")) == "", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersLF() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\nX-Foo: bar\nX-Bar: \nContent-Type: application/x-www-form-urlencoded\n\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertTrue(connection.header(.custom(name: "x-foo")) == "bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "x-bar")) == "", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersMalormed() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\rX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .badRequest = ok else {
				return XCTAssert(false, "\(ok)")
			}
		})
	}
	
	func testWebConnectionHeadersFolded() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\r\n bar\r\nX-Bar: foo\r\n  foo\r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			let wasFoldedValue = connection.header(.custom(name: "x-foo"))
			XCTAssertTrue(wasFoldedValue == "bar bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "x-bar")) == "foo  foo", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersTooLarge() {
		let connection = ShimHTTPRequest()
		
		var fullHeaders = "GET / HTTP/1.1\r\nX-Foo:"
		for _ in 0..<(1024*81) {
			fullHeaders.append(" bar")
		}
		fullHeaders.append("\r\n\r\n")
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .requestEntityTooLarge = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssert(true)
		})
	}
	
	func testWebRequestQueryParam() {
		let req = ShimHTTPRequest()
		req.queryString = "yabba=dabba&y=asd==&doo=fi+☃&fi=&fo=fum"
		XCTAssert(req.param(name: "doo") == "fi ☃")
		XCTAssert(req.param(name: "fi") == "")
		XCTAssert(req.param(name: "y") == "asd==")
	}
	
	func testWebRequestPostParam() {
		let req = ShimHTTPRequest()
		req.postBodyBytes = Array("yabba=dabba&y=asd==&doo=fi+☃&fi=&fo=fum".utf8)
		XCTAssert(req.param(name: "doo") == "fi ☃")
		XCTAssert(req.param(name: "fi") == "")
		XCTAssert(req.param(name: "y") == "asd==")
	}
	
	func testWebRequestCookie() {
		let req = ShimHTTPRequest()
		req.setHeader(.cookie, value: "yabba=dabba; doo=fi☃; fi=; fo=fum")
		for cookie in req.cookies {
			if cookie.0 == "doo" {
				XCTAssert(cookie.1 == "fi☃")
			}
			if cookie.0 == "fi" {
				XCTAssert(cookie.1 == "")
			}
		}
	}
	
	func testWebRequestPath1() {
		let connection = ShimHTTPRequest()
		let fullHeaders = "GET /pathA/pathB/path%20c HTTP/1.1\r\nX-Foo: bar\r\nX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(Array(fullHeaders.utf8)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertEqual(connection.path, "/pathA/pathB/path%20c")
			XCTAssertEqual(connection.pathComponents, ["/", "pathA", "pathB", "path c"])
		})
	}
	
	func testWebRequestPath2() {
		let connection = ShimHTTPRequest()
		let fullHeaders = "GET /pathA/pathB//path%20c/?a=b&c=d%20e HTTP/1.1\r\nX-Foo: bar\r\nX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(Array(fullHeaders.utf8)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertEqual(connection.path, "/pathA/pathB/path%20c/")
			XCTAssertEqual(connection.pathComponents, ["/", "pathA", "pathB", "path c", "/"])
			XCTAssert(connection.param(name: "a") == "b")
			XCTAssert(connection.param(name: "c") == "d e")
			})
	}
	
	func testWebRequestPath3() {
		let connection = ShimHTTPRequest()
		let path = "/pathA/pathB//path%20c/"
		connection.path = path
		XCTAssertEqual(connection.path, "/pathA/pathB/path%20c/")
		XCTAssertEqual(connection.pathComponents, ["/", "pathA", "pathB", "path c", "/"])
	}
	
	func testWebRequestPath4() {
		let connection = ShimHTTPRequest()
		let fullHeaders = "GET /?a=b&c=d%20e HTTP/1.1\r\nX-Foo: bar\r\nX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(Array(fullHeaders.utf8)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertEqual(connection.path, "/")
			XCTAssertEqual(connection.pathComponents, ["/"])
			XCTAssert(connection.param(name: "a") == "b")
			XCTAssert(connection.param(name: "c") == "d e")
			})
	}
	
	func testSimpleHandler() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.addRoutes(routes)
		server.serverPort = port
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clienttcp = NetTCP()
		Threading.dispatch {
			do {
				try clienttcp.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 2.0)
						net.readSomeBytes(count: 1024) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n").map(String.init)
							
							XCTAssertEqual(splitted.last, msg)
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			
		})
	}
	
	func testSimpleStreamingHandler() {
		let port = 8282 as UInt16
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.isStreaming = true
				response.appendBody(string: "A")
				response.push {
					ok in
					XCTAssert(ok, "Failed in .push")
					response.appendBody(string: "BC")
					response.completed()
				}
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 2.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Transfer-Encoding: chunked",
							               "",
							               "1",
							               "A",
							               "2",
							               "BC",
							               "0",
							               "",
							               ""]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			
		})
	}
	
	func testSlowClient() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					var reqIt = Array("GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n".utf8).makeIterator()
					func pushChar() {
						if let b = reqIt.next() {
							let a = [b]
							net.write(bytes: a) {
								wrote in
								guard 1 == wrote else {
									XCTAssert(false, "Could not write request \(wrote) != \(1)")
									return endClient()
								}
								Threading.sleep(seconds: 0.5)
								Threading.dispatch {
									pushChar()
								}
							}
						} else {
							Threading.sleep(seconds: 2.0)
							net.readSomeBytes(count: 1024) {
								bytes in
								guard let bytes = bytes, bytes.count > 0 else {
									XCTAssert(false, "Could not read bytes from server")
									return endClient()
								}
								let str = UTF8Encoding.encode(bytes: bytes)
								let splitted = str.characters.split(separator: "\r\n").map(String.init)
								XCTAssert(splitted.last == msg)
								endClient()
							}
						}
					}
					pushChar()
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 20000, handler: {
			_ in
			
		})
	}
	
	static var oneSet = false, twoSet = false, threeSet = false
	
	func testRequestFilters() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		
		PerfectHTTPServerTests.oneSet = false
		PerfectHTTPServerTests.twoSet = false
		PerfectHTTPServerTests.threeSet = false
		
		struct Filter1: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				PerfectHTTPServerTests.oneSet = true
				callback(.continue(request, response))
			}
		}
		struct Filter2: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(PerfectHTTPServerTests.oneSet)
				XCTAssert(!PerfectHTTPServerTests.twoSet && !PerfectHTTPServerTests.threeSet)
				PerfectHTTPServerTests.twoSet = true
				callback(.execute(request, response))
			}
		}
		struct Filter3: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(false, "This filter should be skipped")
				callback(.continue(request, response))
			}
		}
		struct Filter4: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(PerfectHTTPServerTests.oneSet && PerfectHTTPServerTests.twoSet)
				XCTAssert(!PerfectHTTPServerTests.threeSet)
				PerfectHTTPServerTests.threeSet = true
				callback(.halt(request, response))
			}
		}
		
		let requestFilters: [(HTTPRequestFilter, HTTPFilterPriority)] = [(Filter1(), HTTPFilterPriority.high), (Filter2(), HTTPFilterPriority.medium), (Filter3(), HTTPFilterPriority.medium), (Filter4(), HTTPFilterPriority.low)]
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				XCTAssert(false, "This handler should not execute")
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setRequestFilters(requestFilters)
		server.serverPort = port
		server.addRoutes(routes)
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 1024) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			XCTAssert(PerfectHTTPServerTests.oneSet && PerfectHTTPServerTests.twoSet && PerfectHTTPServerTests.threeSet)
		})
	}
	
	func testResponseFilters() {
		let port = 8282 as UInt16
		
		struct Filter1: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				response.setHeader(.custom(name: "X-Custom"), value: "Value")
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
		}
		
		struct Filter2: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 65 ? 97 : $0 }
				response.bodyBytes = b
				callback(.continue)
			}
		}
		
		struct Filter3: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 66 ? 98 : $0 }
				response.bodyBytes = b
				callback(.done)
			}
		}
		
		struct Filter4: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				XCTAssert(false, "This should not execute")
				callback(.done)
			}
		}
		
		let responseFilters: [(HTTPResponseFilter, HTTPFilterPriority)] = [
			(Filter1(), HTTPFilterPriority.high),
			(Filter2(), HTTPFilterPriority.medium),
			(Filter3(), HTTPFilterPriority.low),
			(Filter4(), HTTPFilterPriority.low)
		]
		
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: "ABZABZ")
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setResponseFilters(responseFilters)
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Content-Length: 6",
							               "X-Custom: Value",
							               "",
							               "abZabZ"]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
		})
	}
	
	func testStreamingResponseFilters() {
		let port = 8282 as UInt16
		
		struct Filter1: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				response.setHeader(.custom(name: "X-Custom"), value: "Value")
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
		}
		
		struct Filter2: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 65 ? 97 : $0 }
				response.bodyBytes = b
				callback(.continue)
			}
		}
		
		struct Filter3: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 66 ? 98 : $0 }
				response.bodyBytes = b
				callback(.done)
			}
		}
		
		struct Filter4: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				XCTAssert(false, "This should not execute")
				callback(.done)
			}
		}
		
		let responseFilters: [(HTTPResponseFilter, HTTPFilterPriority)] = [
			(Filter1(), HTTPFilterPriority.high),
			(Filter2(), HTTPFilterPriority.medium),
			(Filter3(), HTTPFilterPriority.low),
			(Filter4(), HTTPFilterPriority.low)
		]
		
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.isStreaming = true
				response.appendBody(string: "ABZ")
				response.push {
					_ in
					response.appendBody(string: "ABZ")
					response.completed()
				}
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setResponseFilters(responseFilters)
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Transfer-Encoding: chunked",
							               "X-Custom: Value",
							               "",
							               "3",
							               "abZ",
							               "3",
							               "abZ",
							               "0",
							               "",
							               ""]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
		})
	}
	
	func testServerConf1() {
		
		let port = 8282
		
		func handler(data: [String:Any]) throws -> RequestHandler {
			return handler2
		}
		
		func handler2(request: HTTPRequest, response: HTTPResponse) {
			// Respond with a simple message.
			response.setHeader(.contentType, value: "text/html")
			response.appendBody(string: "<html><title>Hello, world!</title><body>Hello, world!</body></html>")
			// Ensure that response.completed() is called when your processing is done.
			response.completed()
		}
		
		let confData = [
			"servers": [
				[
					"name":"localhost",
					"address":"0.0.0.0",
					"port":port,
					"routes":[
						["method":"get", "uri":"/test.html", "handler":handler],
						["method":"get", "uri":"/test.png", "handler":handler2]
					],
					"filters":[
						[
							"type":"response",
							"priority":"high",
							"name":PerfectHTTPServer.HTTPFilter.contentCompression,
						]
					]
				]
			]
		]
		let configs: [HTTPServer.LaunchContext]
		do {
			configs = try HTTPServer.launch(wait: false, configurationData: confData)
		} catch {
			return XCTAssert(false, "Error: \(error)")
		}
		
		let clientExpectation = self.expectation(description: "client")
		Threading.sleep(seconds: 1.0)
		do {
			let client = NetTCP()
			try client.connect(address: "127.0.0.1", port: UInt16(port), timeoutSeconds: 5.0) {
				net in
				
				guard let net = net else {
					XCTAssert(false, "Could not connect to server")
					return clientExpectation.fulfill()
				}
				let reqStr = "GET /test.html HTTP/1.1\r\nHost: localhost:\(port)\r\nAccept-Encoding: gzip, deflate\r\n\r\n"
				net.write(string: reqStr) {
					count in
					
					guard count == reqStr.utf8.count else {
						XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count) \(String(validatingUTF8: strerror(errno)) ?? "no error msg")")
						return clientExpectation.fulfill()
					}
					
					Threading.sleep(seconds: 2.0)
					net.readSomeBytes(count: 1024) {
						bytes in
						
						guard let bytes = bytes, bytes.count > 0 else {
							XCTAssert(false, "Could not read bytes from server")
							return clientExpectation.fulfill()
						}
						
//						let str = UTF8Encoding.encode(bytes: bytes)
//						let splitted = str.characters.split(separator: "\r\n").map(String.init)
						
//						XCTAssert(splitted.last == msg)
						
						clientExpectation.fulfill()
					}
				}
			}
		} catch {
			XCTAssert(false, "Error thrown: \(error)")
			clientExpectation.fulfill()
		}
		
		waitForExpectations(timeout: 10000) {
			_ in
			configs.forEach { _ = try? $0.terminate().wait() }
		}
	}
	
	func testRoutingTrailingSlash() {
		let port = 8282 as UInt16
		var routes = Routes()
		let badHandler = {
			(_:HTTPRequest, resp:HTTPResponse) in
			resp.completed(status: .internalServerError)
		}
		let goodHandler = {
			(_:HTTPRequest, resp:HTTPResponse) in
			resp.completed(status: .notFound)
		}
		routes.add(method: .get, uri: "/", handler: { _, _ in })
		routes.add(method: .get, uri: "/test/", handler: goodHandler)
		routes.add(method: .get, uri: "/**", handler: badHandler)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		let clientNet = NetTCP()
		Threading.dispatch {
			do {
				try clientNet.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET /test/ HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						Threading.sleep(seconds: 2.0)
						net.readSomeBytes(count: 1024) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = "HTTP/1.0 404 Not Found"
							XCTAssert(splitted.first == compare)
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
		})
	}
	
    static var allTests : [(String, (PerfectHTTPServerTests) -> () throws -> Void)] {
        return [
			("testHPACKEncode", testHPACKEncode),
			("testWebConnectionHeadersWellFormed", testWebConnectionHeadersWellFormed),
			("testWebConnectionHeadersLF", testWebConnectionHeadersLF),
			("testWebConnectionHeadersMalormed", testWebConnectionHeadersMalormed),
			("testWebConnectionHeadersFolded", testWebConnectionHeadersFolded),
			("testWebConnectionHeadersTooLarge", testWebConnectionHeadersTooLarge),
			("testWebRequestQueryParam", testWebRequestQueryParam),
			("testWebRequestPostParam", testWebRequestPostParam),
			("testWebRequestCookie", testWebRequestCookie),
			("testWebRequestPath1", testWebRequestPath1),
			("testWebRequestPath2", testWebRequestPath2),
			("testWebRequestPath3", testWebRequestPath3),
			("testWebRequestPath4", testWebRequestPath4),
			("testSimpleHandler", testSimpleHandler),
			("testSimpleStreamingHandler", testSimpleStreamingHandler),
			("testSlowClient", testSlowClient),
			("testRequestFilters", testRequestFilters),
			("testResponseFilters", testResponseFilters),
			("testStreamingResponseFilters", testStreamingResponseFilters),
			("testServerConf1", testServerConf1),
			("testRoutingTrailingSlash", testRoutingTrailingSlash)
        ]
    }
}
