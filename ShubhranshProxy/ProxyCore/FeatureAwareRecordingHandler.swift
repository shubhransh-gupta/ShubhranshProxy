//
//  FeatureAwareRecordingHandler.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation
import NIOCore
import NIOPosix

/// Buffers upstream responses, streams them to the client, and records complete messages for the inspector.
final class FeatureAwareRecordingHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let downstream: Channel
    private let url: String
    private let maxCaptureBytes: Int
    private let closeDownstreamWhenDone: Bool
    private var streamBuffer = HTTPResponseStreamBuffer()
    private var didFinish = false
    private var deliveredAnyResponse = false
    private let callbacks: ProxyRuntimeCallbacks
    private let onComplete: @Sendable (Data) -> Void

    init(
        downstream: Channel,
        url: String,
        callbacks: ProxyRuntimeCallbacks,
        maxCaptureBytes: Int = 8 * 1024 * 1024,
        closeDownstreamWhenDone: Bool = true,
        onComplete: @escaping @Sendable (Data) -> Void
    ) {
        self.downstream = downstream
        self.url = url
        self.callbacks = callbacks
        self.maxCaptureBytes = maxCaptureBytes
        self.closeDownstreamWhenDone = closeDownstreamWhenDone
        self.onComplete = onComplete
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let len = buffer.readableBytes
        guard len > 0, let bytes = buffer.readBytes(length: len) else { return }

        if !requiresResponseTransform, downstream.isActive {
            var out = downstream.allocator.buffer(bytes: bytes)
            downstream.writeAndFlush(out, promise: nil)
        }

        streamBuffer.append(Data(bytes))
        flushCompleteResponses(connectionClosed: false)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(connectionClosed: true)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(connectionClosed: true)
        context.fireErrorCaught(error)
    }

    private var requiresResponseTransform: Bool {
        callbacks.rewriteEnabled() || callbacks.shouldBreakResponse(url)
    }

    private func finish(connectionClosed: Bool) {
        guard !didFinish else { return }
        didFinish = true
        flushCompleteResponses(connectionClosed: connectionClosed)
        if !deliveredAnyResponse, connectionClosed, !streamBuffer.isEmpty {
            deliver(streamBuffer.drainRemaining())
        }
        if closeDownstreamWhenDone, downstream.isActive {
            downstream.close(promise: nil)
        }
    }

    private func flushCompleteResponses(connectionClosed: Bool) {
        for rawResponse in streamBuffer.popAllCompleteResponses(connectionClosed: connectionClosed) {
            deliver(rawResponse)
        }
    }

    private func deliver(_ rawResponse: Data) {
        guard !rawResponse.isEmpty else { return }
        deliveredAnyResponse = true

        var response = rawResponse
        if callbacks.rewriteEnabled() {
            response = RewriteRuleEngine.applyResponseRules(
                response,
                url: url,
                rules: callbacks.rewriteRules()
            )
        }

        if callbacks.shouldBreakResponse(url) {
            let headers = HTTPMessageHeaders.headerBlock(from: response)
            let body = HTTPMessageHeaders.requestBody(from: response)
            let pending = PendingBreakpoint(
                id: UUID(),
                phase: .response,
                method: "RESPONSE",
                url: url,
                host: ProxySession.host(from: url),
                headers: headers,
                body: body,
                rawData: response
            )
            let decision = callbacks.awaitBreakpoint(pending)
            switch decision.action {
            case .drop:
                if downstream.isActive {
                    downstream.close(promise: nil)
                }
                onComplete(response)
                return
            case .forward:
                if let modified = decision.modifiedData { response = modified }
            }
        }

        if requiresResponseTransform, downstream.isActive, !response.isEmpty {
            var buf = downstream.allocator.buffer(bytes: response)
            downstream.writeAndFlush(buf, promise: nil)
        }

        if response.count <= maxCaptureBytes {
            onComplete(response)
        } else {
            onComplete(Data(response.prefix(maxCaptureBytes)))
        }
    }
}
