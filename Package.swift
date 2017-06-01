//
//  Package.swift
//  PerfectHTTPServer
//
//  Created by Kyle Jessup on 2016-05-02.
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

import PackageDescription

let package = Package(
	name: "PerfectHTTPServer",
	targets: [
		Target(name: "CHTTPParser", dependencies: []),
		Target(name: "CZlib", dependencies: []),
		Target(name: "PerfectHTTPServer", dependencies: ["CHTTPParser", "CZlib"])
	],
	dependencies: [.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTP.git", majorVersion: 2)],
	exclude: ["Sources/CZlib/examples", "Sources/CZlib/test", "Sources/CZlib/contrib"]
)
