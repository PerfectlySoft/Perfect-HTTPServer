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




