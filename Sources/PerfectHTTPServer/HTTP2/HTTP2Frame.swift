//
//  HTTP2Frame.swift
//  PerfectHTTPServer
//
//  Created by Kyle Jessup on 2017-06-20.

enum HTTP2FrameType: UInt8 {
	case data = 0x0
	case headers = 0x1
	case priority = 0x2
	case cancelStream = 0x3
	case settings = 0x4
	case pushPromise = 0x5
	case ping = 0x6
	case goAway = 0x7
	case windowUpdate = 0x8
	case continuation = 0x9
}

typealias HTTP2FrameFlag = UInt8

let flagEndStream: HTTP2FrameFlag = 0x1
let flagEndHeaders: HTTP2FrameFlag = 0x4
let flagPadded: HTTP2FrameFlag = 0x8
let flagPriority: HTTP2FrameFlag = 0x20
let flagSettingsAck: HTTP2FrameFlag = 0x1
let flagPingAck: HTTP2FrameFlag = 0x1

struct HTTP2Frame {
	let length: UInt32 // 24-bit
	let type: UInt8
	let flags: UInt8
	let streamId: UInt32 // 31-bit
	var payload: [UInt8]?
	
	init(length: UInt32,
			type: UInt8,
			flags: UInt8 = 0,
			streamId: UInt32 = 0,
			payload: [UInt8]? = nil) {
		self.length = length
		self.type = type
		self.flags = flags
		self.streamId = streamId
		self.payload = payload
	}
	
	init(type: HTTP2FrameType,
		 flags: UInt8 = 0,
		 streamId: UInt32 = 0,
		 payload: [UInt8]? = nil) {
		self.init(length: UInt32(payload?.count ?? 0), type: type.rawValue, flags: flags, streamId: streamId, payload: payload)
	}
	
	var typeStr: String {
		switch self.type {
		case HTTP2_DATA:
			return "HTTP2_DATA"
		case HTTP2_HEADERS:
			return "HTTP2_HEADERS"
		case HTTP2_PRIORITY:
			return "HTTP2_PRIORITY"
		case HTTP2_RST_STREAM:
			return "HTTP2_RST_STREAM"
		case HTTP2_SETTINGS:
			return "HTTP2_SETTINGS"
		case HTTP2_PUSH_PROMISE:
			return "HTTP2_PUSH_PROMISE"
		case HTTP2_PING:
			return "HTTP2_PING"
		case HTTP2_GOAWAY:
			return "HTTP2_GOAWAY"
		case HTTP2_WINDOW_UPDATE:
			return "HTTP2_WINDOW_UPDATE"
		case HTTP2_CONTINUATION:
			return "HTTP2_CONTINUATION"
		default:
			return "UNKNOWN_TYPE"
		}
	}
	
	var flagsStr: String {
		var s = ""
		if flags == 0 {
			s.append("NO FLAGS")
		}
		if (flags & HTTP2_END_STREAM) != 0 {
			s.append(" +HTTP2_END_STREAM")
		}
		if (flags & HTTP2_END_HEADERS) != 0 {
			s.append(" +HTTP2_END_HEADERS")
		}
		return s
	}
	
	func headerBytes() -> [UInt8] {
		var data = [UInt8]()
		
		let l = length.hostToNet >> 8
		data.append(UInt8(l & 0xFF))
		data.append(UInt8((l >> 8) & 0xFF))
		data.append(UInt8((l >> 16) & 0xFF))
		
		data.append(type)
		data.append(flags)
		
		let s = streamId.hostToNet
		data.append(UInt8(s & 0xFF))
		data.append(UInt8((s >> 8) & 0xFF))
		data.append(UInt8((s >> 16) & 0xFF))
		data.append(UInt8((s >> 24) & 0xFF))
		return data
	}
}
