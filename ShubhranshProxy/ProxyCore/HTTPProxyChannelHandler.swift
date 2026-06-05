//
//  HTTPProxyChannelHandler.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Per-client TCP connection: HTTP forward, Map Local (HTTP), CONNECT tunnel, traffic recording.
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSL

/// Handles one browser → proxy connection.
final class HTTPProxyChannelHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var accumulator = Data()
    private var clientAppName: String?
    private var clientIPAddress: String?
    private let group: MultiThreadedEventLoopGroup
    private let clientBootstrap: ClientBootstrap
    private let callbacks: ProxyRuntimeCallbacks

    init(group: MultiThreadedEventLoopGroup, callbacks: ProxyRuntimeCallbacks) {
        self.group = group
        self.callbacks = callbacks
        self.clientBootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeSucceededFuture(())
            }
    }

    func channelActive(context: ChannelHandlerContext) {
        if let ip = ClientAddressResolver.ipAddress(for: context.channel),
           !ClientAddressResolver.isLoopback(ip) {
            callbacks.onRemoteClientConnected(ip)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let ip = ClientAddressResolver.ipAddress(for: context.channel),
           !ClientAddressResolver.isLoopback(ip) {
            callbacks.onRemoteClientDisconnected(ip)
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
                    return
                }
                accumulator = working
                try handleParsed(parsed, clientContext: context)
            }
        } catch {
            sendSimpleError(context: context, text: "ShubhranshProxy: \(error)")
            context.close(promise: nil)
        }
    }

    private func handleParsed(_ request: ParsedInboundRequest, clientContext: ChannelHandlerContext) throws {
        let (host, port) = try HTTPProxyTargetResolver.hostPort(for: request)
        if request.isConnect {
            handleConnect(request: request, host: host, port: port, clientContext: clientContext)
        } else {
            try forwardHTTP(request: request, host: host, port: port, clientContext: clientContext)
        }
    }

    private func resolvedClientAppName(for channel: Channel) -> String? {
        if let clientAppName { return clientAppName }
        let name = ClientProcessResolver.appName(for: channel)
        clientAppName = name
        return name
    }

    private func resolvedClientIPAddress(for channel: Channel) -> String? {
        if let clientIPAddress { return clientIPAddress }
        let ip = ClientAddressResolver.ipAddress(for: channel)
        clientIPAddress = ip
        return ip
    }

    private func handleConnect(
        request: ParsedInboundRequest,
        host: String,
        port: Int,
        clientContext: ChannelHandlerContext
    ) {
        let clientChannel = clientContext.channel
        let clientApp = resolvedClientAppName(for: clientChannel)
        let clientIP = resolvedClientIPAddress(for: clientChannel)
        let connectHeaders = HTTPMessageHeaders.headerBlock(from: request.raw)
        let settings = callbacks.sslSettings()
        if settings.shouldIntercept(host: host, clientIPAddress: clientIP) {
            handleConnectMITM(
                request: request,
                host: host,
                port: port,
                clientContext: clientContext,
                clientAppName: clientApp,
                clientIPAddress: clientIP
            )
            return
        }

        var respBuf = clientChannel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")

        clientContext.writeAndFlush(wrapOutboundOut(respBuf), promise: nil)

        clientBootstrap.connect(host: host, port: port).flatMap { upstream in
            self.callbacks.onCONNECT(request.target, true, nil, clientApp, clientIP, connectHeaders)
            return clientContext.pipeline.removeHandler(self).flatMap { _ in
                clientChannel.pipeline.addHandler(PeerRelayHandler(peer: upstream)).flatMap { _ in
                    upstream.pipeline.addHandler(PeerRelayHandler(peer: clientChannel))
                }
            }
        }.whenFailure { err in
            self.callbacks.onCONNECT(request.target, false, err.localizedDescription, clientApp, clientIP, connectHeaders)
            clientChannel.close(promise: nil)
        }
    }

    private func handleConnectMITM(
        request: ParsedInboundRequest,
        host: String,
        port: Int,
        clientContext: ChannelHandlerContext,
        clientAppName: String?,
        clientIPAddress: String?
    ) {
        let clientChannel = clientContext.channel
        var respBuf = clientChannel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")
        clientContext.writeAndFlush(wrapOutboundOut(respBuf), promise: nil)

        let connectHeaders = HTTPMessageHeaders.headerBlock(from: request.raw)
        let cb = callbacks
        do {
            let material = try cb.leafCertificate(host)
            let serverContext = try HTTPSMITMConnector.makeServerSSLContext(material: material)
            let clientSSLContext = try HTTPSMITMConnector.makeClientSSLContext()

            clientContext.pipeline.removeHandler(self).flatMap { _ in
                clientContext.pipeline.addHandler(NIOSSLServerHandler(context: serverContext))
            }.flatMap { _ in
                clientContext.pipeline.addHandler(
                    MITMClientErrorHandler(
                        host: host,
                        clientIPAddress: clientIPAddress,
                        callbacks: cb
                    )
                )
            }.flatMap { _ in
                clientContext.pipeline.addHandler(
                    MITMHTTPChannelHandler(
                        host: host,
                        port: port,
                        group: self.group,
                        callbacks: cb,
                        clientSSLContext: clientSSLContext,
                        clientAppName: clientAppName,
                        clientIPAddress: clientIPAddress
                    )
                )
            }.whenFailure { err in
                cb.onCONNECT(request.target, false, err.localizedDescription, clientAppName, clientIPAddress, connectHeaders)
                clientChannel.close(promise: nil)
            }
        } catch {
            cb.onCONNECT(request.target, false, error.localizedDescription, clientAppName, clientIPAddress, connectHeaders)
            clientChannel.close(promise: nil)
        }
    }

    private func forwardHTTP(
        request: ParsedInboundRequest,
        host: String,
        port: Int,
        clientContext: ChannelHandlerContext
    ) throws {
        let fullURL = HTTPProxyURLBuilder.fullURL(request: request, host: host, port: port)
        let clientApp = resolvedClientAppName(for: clientContext.channel)
        let clientIP = resolvedClientIPAddress(for: clientContext.channel)
        ProxyFeaturePipeline.forward(
            .init(
                request: request,
                host: host,
                port: port,
                fullURL: fullURL,
                exchangeID: UUID(),
                startedAt: Date().timeIntervalSince1970,
                wasDecryptedHTTPS: false,
                clientAppName: clientApp,
                clientIPAddress: clientIP,
                clientChannel: clientContext.channel,
                clientContext: clientContext,
                group: group,
                clientBootstrap: clientBootstrap,
                callbacks: callbacks
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
