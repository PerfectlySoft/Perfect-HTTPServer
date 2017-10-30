// swift-tools-version:4.0
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
	products: [
		.library(name: "PerfectHTTPServer", targets: ["PerfectHTTPServer"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-Net.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-HTTP.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-CZlib-src.git", from: "0.0.0")
	],
	targets: [
		.target(name: "PerfectCHTTPParser", dependencies: []),
		.target(name: "PerfectHTTPServer", dependencies: ["PerfectCHTTPParser", "PerfectNet", "PerfectHTTP", "PerfectCZlib"]),
		.testTarget(name: "PerfectHTTPServerTests", dependencies: ["PerfectHTTPServer"])
	]
)
