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

import PerfectLib
import PerfectHTTP

final class HTTP2Response: HTTP11Response, HeaderListener {
	
	func addHeader(name nam: [UInt8], value: [UInt8], sensitive: Bool) {
		let n = UTF8Encoding.encode(bytes: nam)
		let v = UTF8Encoding.encode(bytes: value)
		switch n {
		case ":status":
			self.status = HTTPResponseStatus.statusFrom(code: Int(v) ?? 200)
		default:
			headerStore.append((HTTPResponseHeader.Name.fromStandard(name: n), v))
		}
	}
}
