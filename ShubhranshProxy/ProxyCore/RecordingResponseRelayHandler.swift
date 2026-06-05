//
//  RecordingResponseRelayHandler.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Tee upstream bytes to the browser while buffering a capped copy for the inspector.
//

import Foundation
import NIOCore
import NIOPosix

final class RecordingResponseRelayHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let downstream: Channel
    private let maxCaptureBytes: Int
    private var captured = Data()
    private var didFinish = false
    private let onComplete: @Sendable (Data) -> Void

    init(
        downstream: Channel,
        maxCaptureBytes: Int = 8 * 1024 * 1024,
        onComplete: @escaping @Sendable (Data) -> Void
    ) {
        self.downstream = downstream
        self.maxCaptureBytes = maxCaptureBytes
        self.onComplete = onComplete
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let len = buffer.readableBytes
        if len > 0 {
            if captured.count < maxCaptureBytes {
                let take = min(len, maxCaptureBytes - captured.count)
                var slice = buffer
                if take > 0, let bytes = slice.readBytes(length: take) {
                    captured.append(contentsOf: bytes)
                }
            }
            downstream.writeAndFlush(buffer, promise: nil)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        downstream.flush()
        context.fireChannelReadComplete()
    }

    func channelInactive(context: ChannelHandlerContext) {
        finishRelay()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finishRelay()
        context.fireErrorCaught(error)
    }

    private func finishRelay() {
        guard !didFinish else { return }
        didFinish = true
        onComplete(captured)
        if downstream.isActive {
            downstream.close(promise: nil)
        }
    }
}
