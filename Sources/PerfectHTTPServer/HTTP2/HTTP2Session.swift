//
//  HTTP2Session.swift
//  PerfectHTTPServer
//
//  Created by Kyle Jessup on 2017-06-20.
//
//

import PerfectNet
import PerfectLib

// A single HTTP/2 connection handling multiple requests and responses
class HTTP2Session {
	let net: NetTCP
	let frameReader: HTTP2FrameReader
	let frameWriter: HTTP2FrameWriter
	let encoder = HPACKEncoder()
	let decoder = HPACKDecoder()
	var settings = HTTP2SessionSettings()
	
	public init(_ net: NetTCP) {
		self.net = net
		frameReader = HTTP2FrameReader(net)
		frameWriter = HTTP2FrameWriter(net)
		subscribe()
	}
	
	deinit {
		print("~HTTP2Session")
	}
	
	func fatalError(_ msg: String) {
		let msgBytes = Array(msg.utf8)
		let frame = HTTP2Frame(type: HTTP2FrameType.goAway, payload: msgBytes)
		frameWriter.enqueueFrame(frame)
		frameWriter.waitUntilEmpty {
			self.net.close()
		}
	}
	
/*
	headers
	settings
	pushPromise
	ping
	goAway
	sessionTimeout
*/
	func subscribe() {
		frameReader.subscribe(.settings, self.settingsFrame)
		frameReader.subscribe(.windowUpdate, self.windowUpdateFrame)
		frameReader.subscribe(.headers, self.headersFrame)
		frameReader.subscribe(.pushPromise, self.pushPromiseFrame)
		frameReader.subscribe(.ping, self.pingFrame)
		frameReader.subscribe(.goAway, self.goAwayFrame)
		frameReader.subscribe(.sessionTimeout, self.sessionTimeoutFrame)
	}
	
	func settingsFrame(_ frame: HTTP2Frame) {
		let endStream = (frame.flags & flagSettingsAck) != 0
		if !endStream { // ACK settings receipt
			if let payload = frame.payload {
				processSettingsPayload(Bytes(existingBytes: payload))
			}
			let response = HTTP2Frame(type: HTTP2FrameType.settings,
			                          flags: flagSettingsAck)
			frameWriter.enqueueFrame(response)
		}
	}
	
	func windowUpdateFrame(_ frame: HTTP2Frame) {
		guard let b = frame.payload, b.count == 4 else {
			return fatalError("Invalid frame")
		}
		var sid: UInt32 = UInt32(b[0])
		sid <<= 8
		sid += UInt32(b[1])
		sid <<= 8
		sid += UInt32(b[2])
		sid <<= 8
		sid += UInt32(b[3])
		sid &= ~0x80000000
		frameWriter.windowSize = Int(sid)
	}

	func headersFrame(_ frame: HTTP2Frame) {
		print("headersFrame")
	}
	
	func pushPromiseFrame(_ frame: HTTP2Frame) {
		print("pushPromiseFrame")
	}
	
	func pingFrame(_ frame: HTTP2Frame) {
		print("pingFrame")
	}
	
	func goAwayFrame(_ frame: HTTP2Frame) {
		print("goAwayFrame")
		net.close()
	}
	
	func sessionTimeoutFrame(_ frame: HTTP2Frame) {
		print("sessionTimeoutFrame")
	}
	
	func processSettingsPayload(_ b: Bytes) {
		while b.availableExportBytes >= 6 {
			let identifier = b.export16Bits().netToHost
			let value = Int(b.export32Bits().netToHost)
			switch identifier {
			case SETTINGS_HEADER_TABLE_SIZE:
				settings.headerTableSize = Int(value)
				//self.encoder = HPACKEncoder(maxCapacity: Int(value))
			case SETTINGS_ENABLE_PUSH:
				settings.enablePush = value == 1
			case SETTINGS_MAX_CONCURRENT_STREAMS:
				settings.maxConcurrentStreams = value
			case SETTINGS_INITIAL_WINDOW_SIZE:
				settings.initialWindowSize = value
			case SETTINGS_MAX_FRAME_SIZE:
				settings.maxFrameSize = value
			case SETTINGS_MAX_HEADER_LIST_SIZE:
				settings.maxHeaderListSize = value
			default:
				()
			}
		}
	}
}
