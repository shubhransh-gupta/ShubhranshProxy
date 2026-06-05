//
//  MITMHTTPChannelHandler.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  After TLS termination on the client side, forwards decrypted HTTP/1.1 to the origin over TLS.
//  Serializes requests per client connection so keep-alive responses never interleave.
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSL

/// Handles decrypted HTTP on a MITM connection (post-CONNECT + NIOSSLServerHandler).
final class MITMHTTPChannelHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var accumulator = Data()
    private var pendingRequests: [ParsedInboundRequest] = []
    private var isForwarding = false
    private let host: String
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private let callbacks: ProxyRuntimeCallbacks
    private let clientSSLContext: NIOSSLContext
    private let clientAppName: String?
    private let clientIPAddress: String?
    private let clientBootstrap: ClientBootstrap

    init(
        host: String,
        port: Int,
        group: MultiThreadedEventLoopGroup,
        callbacks: ProxyRuntimeCallbacks,
        clientSSLContext: NIOSSLContext,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil
    ) {
        self.host = host
        self.port = port
        self.group = group
        self.callbacks = callbacks
        self.clientSSLContext = clientSSLContext
        self.clientAppName = clientAppName
        self.clientIPAddress = clientIPAddress
        self.clientBootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: clientSSLContext, serverHostname: host)
                    )
                }
            }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        if let bytes = buf.readBytes(length: buf.readableBytes) {
            accumulator.append(contentsOf: bytes)
        }
        do {
            while true {
                var working = accumulator
                guard let parsed = try RawHTTPRequestParse.parseIfComplete(buffer: &working) else {
                    accumulator = working
                    break
                }
                accumulator = working
                pendingRequests.append(parsed)
            }
            drainQueue(clientContext: context)
        } catch {
            sendSimpleError(context: context, text: "ShubhranshProxy MITM: \(error)")
            context.close(promise: nil)
        }
    }

    private func drainQueue(clientContext: ChannelHandlerContext) {
        guard !isForwarding, !pendingRequests.isEmpty else { return }
        isForwarding = true
        let request = pendingRequests.removeFirst()
        forwardHTTPS(request: request, clientContext: clientContext)
    }

    private func forwardHTTPS(
        request: ParsedInboundRequest,
        clientContext: ChannelHandlerContext
    ) {
        let fullURL = HTTPProxyURLBuilder.fullURL(
            request: request,
            host: host,
            port: port,
            scheme: "https",
            defaultPort: 443
        )
        let loop = clientContext.eventLoop
        ProxyFeaturePipeline.forward(
            .init(
                request: request,
                host: host,
                port: port,
                fullURL: fullURL,
                exchangeID: UUID(),
                startedAt: Date().timeIntervalSince1970,
                wasDecryptedHTTPS: true,
                clientAppName: clientAppName,
                clientIPAddress: clientIPAddress,
                clientChannel: clientContext.channel,
                clientContext: clientContext,
                group: group,
                clientBootstrap: clientBootstrap,
                callbacks: callbacks,
                onFinished: { [weak self] in
                    loop.execute {
                        guard let self else { return }
                        self.isForwarding = false
                        self.drainQueue(clientContext: clientContext)
                    }
                }
            )
        )
    }

    private func sendSimpleError(context: ChannelHandlerContext, text: String) {
        let body = "<html><body><pre>\(text)</pre></body></html>"
        let payload =
            "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        var buf = context.channel.allocator.buffer(string: payload)
        context.writeAndFlush(wrapOutboundOut(buf), promise: nil)
    }
}
