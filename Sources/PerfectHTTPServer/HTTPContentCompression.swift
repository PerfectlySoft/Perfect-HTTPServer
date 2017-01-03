//
//  HTTPContentCompression.swift
//  PerfectHTTPServer
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

import PerfectHTTP
import CZlib

class ZlibStream {
	var stream = z_stream()
	
	init?() {
		stream.zalloc = nil
		stream.zfree = nil
		stream.opaque = nil
		
		let err = deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
		guard Z_OK == err else {
			return nil
		}
	}
	
	func compress(_ bytes: [UInt8]) -> [UInt8] {
		let needed = Int(compressBound(UInt(bytes.count)))
		let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: needed)
		defer {
			dest.deallocate(capacity: needed)
		}
		
		var left = uInt(needed)
		var sourceLen = uInt(bytes.count)
		stream.next_out = dest
		stream.avail_out = 0
		stream.next_in = UnsafeMutablePointer(mutating: bytes)
		stream.avail_in = 0
		
		while true {
			if stream.avail_out == 0 {
				stream.avail_out = left
				left -= stream.avail_out
			}
			if stream.avail_in == 0 {
				stream.avail_in = sourceLen
				sourceLen -= stream.avail_in
			}
			let err = deflate(&stream, sourceLen > 0 ? Z_NO_FLUSH : Z_FINISH)
			guard err == Z_OK else {
				break
			}
		}
		
		let b2 = UnsafeRawBufferPointer(start: dest, count: Int(stream.total_out))
		return [UInt8](b2)
	}
	
	func close() {
		deflateEnd(&stream)
	}
}

public extension HTTPFilter {
	/// Response filter which provides content compression.
	/// Mime types which will be encoded or ignored can be specified with the "compressTypes" and
	/// "ignoreTypes" keys, respectively. The values for these keys should be an array of String
	/// containing either the full mime type or the the main type with a * wildcard. e.g. text/*
	/// The default values for the compressTypes key are: "*/*"
	/// The default values for the ignoreTypes key are: "image/*", "video/*", "audio/*"
	public static func contentCompression(data: [String:Any]) throws -> HTTPResponseFilter {
		let inCompressTypes = data["compressTypes"] as? [String] ?? ["*/*"]
		let inIgnoreTypes = data["ignoreTypes"] as? [String] ?? ["image/*", "video/*", "audio/*"]
		
		struct CompressResponse: HTTPResponseFilter {
			let compressTypes: [MimeType]
			let ignoreTypes: [MimeType]
			
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				let req = response.request
				if !response.isStreaming,
					let acceptEncoding = req.header(.acceptEncoding),
					let contentType = contentType(response: response),
					clientWantsCompression(acceptEncoding: acceptEncoding),
					shouldCompress(mimeType: contentType) {
					let skipCheck = response.request.scratchPad["no-compression"] as? Bool ?? false
					if !skipCheck, let stream = ZlibStream() {
						response.setHeader(.contentEncoding, value: "deflate")
						let old = response.bodyBytes
						let new = stream.compress(old)
						response.bodyBytes = new
						stream.close()
						response.setHeader(.contentLength, value: "\(new.count)")
					}
				}
				return callback(.continue)
			}
			
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				return callback(.continue)
			}
			
			private func contentType(response: HTTPResponse) -> String? {
				if let contentType = response.header(.contentType) {
					return contentType
				}
				let path = response.request.path
				return MimeType.forExtension(path.lastFilePathComponent.filePathExtension)
			}
			
			private func clientWantsCompression(acceptEncoding: String) -> Bool {
				return acceptEncoding.contains("deflate")
			}
			
			private func shouldCompress(mimeType: String) -> Bool {
				let mime = MimeType(mimeType)
				return compressTypes.contains(mime) && !ignoreTypes.contains(mime)
			}
		}
		return CompressResponse(compressTypes: inCompressTypes.map { MimeType($0) },
		                        ignoreTypes: inIgnoreTypes.map { MimeType($0) })
	}
}
