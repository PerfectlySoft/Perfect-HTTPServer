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

// NOTE: This HTTP/2 client is competent enough to operate with Apple's push notification service, but
// still lacks some functionality to make it general purpose. Consider it a work in-progress.

import PerfectNet
import PerfectThread
import PerfectLib
import PerfectHTTP

#if os(Linux)
import SwiftGlibc
#endif

let HTTP2_DATA: UInt8 = 0x0
let HTTP2_HEADERS: UInt8 = 0x1
let HTTP2_PRIORITY: UInt8 = 0x2
let HTTP2_RST_STREAM: UInt8 = 0x3
let HTTP2_SETTINGS: UInt8 = 0x4
let HTTP2_PUSH_PROMISE: UInt8 = 0x5
let HTTP2_PING: UInt8 = 0x6
let HTTP2_GOAWAY: UInt8 = 0x7
let HTTP2_WINDOW_UPDATE: UInt8 = 0x8
let HTTP2_CONTINUATION: UInt8 = 0x9

let HTTP2_END_STREAM: UInt8 = 0x1
let HTTP2_END_HEADERS: UInt8 = 0x4
let HTTP2_PADDED: UInt8 = 0x8
let HTTP2_FLAG_PRIORITY: UInt8 = 0x20
let HTTP2_SETTINGS_ACK = HTTP2_END_STREAM
let HTTP2_PING_ACK = HTTP2_END_STREAM

let SETTINGS_HEADER_TABLE_SIZE: UInt16 = 0x1
let SETTINGS_ENABLE_PUSH: UInt16 = 0x2
let SETTINGS_MAX_CONCURRENT_STREAMS: UInt16 = 0x3
let SETTINGS_INITIAL_WINDOW_SIZE: UInt16 = 0x4
let SETTINGS_MAX_FRAME_SIZE: UInt16 = 0x5
let SETTINGS_MAX_HEADER_LIST_SIZE: UInt16 = 0x6

let http2ConnectionPreface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

struct HTTP2Frame {
	let length: UInt32 // 24-bit
	let type: UInt8
	let flags: UInt8
	let streamId: UInt32 // 31-bit
	var payload: [UInt8]?

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


