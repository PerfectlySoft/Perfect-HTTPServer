//
//  HTTP2FrameReader.swift
//  PerfectHTTPServer
//
//  Created by Kyle Jessup on 2017-06-20.
//
//

import PerfectNet
import PerfectThread
import Dispatch

enum HTTP2FrameSubscriptionType: UInt8 {
	case headers = 0x1
	case settings = 0x4
	case pushPromise = 0x5
	case ping = 0x6
	case goAway = 0x7
	case windowUpdate = 0x8
	case sessionTimeout = 0xFF
}

typealias HTTP2FrameReceiver = (HTTP2Frame) -> ()

class HTTP2FrameReader {
	private let net: NetTCP
	
	private var frameSubscriptions = [HTTP2FrameSubscriptionType:HTTP2FrameReceiver]()
	private var streamSubscriptions = [Int:HTTP2FrameReceiver]()
	private let subscriptionsLock = Threading.Lock()
	
	private var readFrames = [HTTP2Frame]()
	private let readFramesEvent = Threading.Event()
	
	// no frames in queue and no frames read
	var noFrameReadTimeout = 60.0*5.0
	private let readFramesThread = DispatchQueue(label: "HTTP2FrameReader")
	
	private let processFramesThread = DispatchQueue(label: "HTTP2FrameProcessor")
	
	private var shouldTimeout: Bool {
		readFramesEvent.lock()
		defer {
			readFramesEvent.unlock()
		}
		return readFrames.isEmpty
	}
	
	init(_ net: NetTCP) {
		self.net = net
		startReadFrames()
		startProcessReadFrames()
	}
	
	func subscribe(_ type: HTTP2FrameSubscriptionType, _ callback: @escaping HTTP2FrameReceiver) {
		subscriptionsLock.lock()
		frameSubscriptions[type] = callback
		subscriptionsLock.unlock()
	}
	
	func subscribe(stream: Int, _ callback: @escaping HTTP2FrameReceiver) {
		subscriptionsLock.lock()
		streamSubscriptions[stream] = callback
		subscriptionsLock.unlock()
		readFramesEvent.signal()
	}
	
	func unsubscribe(stream: Int) {
		subscriptionsLock.lock()
		streamSubscriptions.removeValue(forKey: stream)
		subscriptionsLock.unlock()
		readFramesEvent.signal()
	}
	
	private func startProcessReadFrames() {
		processFramesThread.async {
			repeat {
				self.readFramesEvent.lock()
				if self.readFrames.count > 0 {
					self.subscriptionsLock.lock()
					self.readFrames = self.readFrames.filter {
						frame in
						if frame.streamId != 0, let callback = self.streamSubscriptions[Int(frame.streamId)] {
							callback(frame)
							return false
						} else if let subscribableType = HTTP2FrameSubscriptionType(rawValue: frame.type),
							let callback = self.frameSubscriptions[subscribableType] {
							callback(frame)
							return false
						}
						return true
					}
					self.subscriptionsLock.unlock()
				} else {
					_ = self.readFramesEvent.wait(seconds: 0.5)
				}
				self.readFramesEvent.unlock()
			} while self.net.isValid
		}
	}
	
	private func pushReadFrame(_ frame: HTTP2Frame) {
		readFramesEvent.lock()
		readFrames.append(frame)
		readFramesEvent.signal()
		readFramesEvent.unlock()
	}
	
	private func startReadFrames() {
		readFramesThread.async {
			self.readHTTP2Frame {
				frame in
				if frame == nil {
					self.net.close()
					let timeoutFrame = HTTP2Frame(length: 0, type: HTTP2FrameSubscriptionType.sessionTimeout.rawValue, flags: 0, streamId: 0, payload: nil)
					self.pushReadFrame(timeoutFrame)
				} else if let frame = frame {
					self.pushReadFrame(frame)
				}
				self.startReadFrames()
			}
		}
	}
	
	private func bytesToHeader(_ b: [UInt8]) -> HTTP2Frame {
		let payloadLength = (UInt32(b[0]) << 16) + (UInt32(b[1]) << 8) + UInt32(b[2])
		let type = b[3]
		let flags = b[4]
		var sid = UInt32(b[5])
		sid <<= 8
		sid += UInt32(b[6])
		sid <<= 8
		sid += UInt32(b[7])
		sid <<= 8
		sid += UInt32(b[8])
		sid &= ~0x80000000
		return HTTP2Frame(length: payloadLength, type: type, flags: flags, streamId: sid, payload: nil)
	}
	
	private func readHTTP2Frame(callback: @escaping (HTTP2Frame?) -> ()) {
		let net = self.net
		net.readBytesFully(count: 9, timeoutSeconds: noFrameReadTimeout) {
			bytes in
			if let b = bytes {
				var header = self.bytesToHeader(b)
				if header.length > 0 {
					net.readBytesFully(count: Int(header.length), timeoutSeconds: self.noFrameReadTimeout) {
						bytes in
						header.payload = bytes
						callback(header)
					}
				} else {
					callback(header)
				}
			} else {
				callback(nil)
			}
		}
	}
}






