//
//  ThrottleByteHandler.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation
import NIOCore

/// Limits outbound throughput on a channel (simulated slow network).
final class ThrottleByteHandler: ChannelOutboundHandler, RemovableChannelHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let bytesPerSecond: Int
    private let latencyMs: Int
    private var scheduledDelayMs: Int64 = 0
    private struct PendingWrite {
        let id: UUID
        let promise: EventLoopPromise<Void>?
    }
    private var pendingWrites: [PendingWrite] = []

    init(settings: ThrottleSnapshot) {
        self.bytesPerSecond = max(settings.bytesPerSecond, 1024)
        self.latencyMs = settings.latencyMs
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = unwrapOutboundIn(data)
        let byteCount = buffer.readableBytes
        guard byteCount > 0 else {
            context.write(data, promise: promise)
            return
        }

        guard context.channel.isActive else {
            promise?.fail(ChannelError.ioOnClosedChannel)
            return
        }

        let writeID = UUID()
        if let promise {
            pendingWrites.append(PendingWrite(id: writeID, promise: promise))
        }

        let transferMs = Int64((Double(byteCount) / Double(bytesPerSecond)) * 1000)
        let delayMs = Int64(latencyMs) + scheduledDelayMs + transferMs
        scheduledDelayMs = delayMs

        context.eventLoop.scheduleTask(in: .milliseconds(delayMs)) {
            self.completePendingWrite(id: writeID, context: context, data: data, promise: promise)
        }
    }

    private func completePendingWrite(
        id: UUID,
        context: ChannelHandlerContext,
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        pendingWrites.removeAll { $0.id == id }
        guard context.channel.isActive else {
            promise?.fail(ChannelError.ioOnClosedChannel)
            return
        }
        context.write(data, promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        failPendingPromises()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failPendingPromises()
        context.fireErrorCaught(error)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        failPendingPromises()
    }

    private func failPendingPromises() {
        scheduledDelayMs = 0
        for pending in pendingWrites {
            pending.promise?.fail(ChannelError.ioOnClosedChannel)
        }
        pendingWrites.removeAll()
    }
}
