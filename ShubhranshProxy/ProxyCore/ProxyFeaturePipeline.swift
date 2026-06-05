//
//  ProxyFeaturePipeline.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation
import NIOCore
import NIOPosix

enum ProxyFeaturePipeline {
    struct Context {
        var request: ParsedInboundRequest
        var host: String
        var port: Int
        var fullURL: String
        var exchangeID: UUID
        var startedAt: TimeInterval
        var wasDecryptedHTTPS: Bool
        var clientAppName: String?
        var clientIPAddress: String?
        var clientChannel: Channel
        var clientContext: ChannelHandlerContext
        var group: MultiThreadedEventLoopGroup
        var clientBootstrap: ClientBootstrap
        var callbacks: ProxyRuntimeCallbacks
        /// Called on the NIO event loop when this exchange finishes (used to serialize MITM keep-alive).
        var onFinished: (@Sendable () -> Void)?
    }

    static func forward(_ ctx: Context) {
        let cb = ctx.callbacks
        var request = ctx.request
        var fullURL = ctx.fullURL
        var host = ctx.host
        var port = ctx.port
        var wasMappedRemote = false

        if BlockListEngine.shouldBlock(url: fullURL, host: host, settings: cb.blockListSettings()) {
            let blocked = BlockListEngine.blockedResponseHTML(for: ctx.fullURL)
            ctx.clientChannel.writeAndFlush(ctx.clientChannel.allocator.buffer(bytes: blocked)).whenComplete { _ in
                if !ctx.wasDecryptedHTTPS {
                    ctx.clientChannel.close(promise: nil)
                }
            }
            let parsed = try? HTTPResponseParser.parse(raw: blocked)
            cb.onHTTPExchange(
                ExchangeSnapshotFactory.httpExchange(
                    id: ctx.exchangeID,
                    startedAt: ctx.startedAt,
                    request: ctx.request,
                    fullURL: ctx.fullURL,
                    host: ctx.host,
                    responseStatus: 403,
                    responseHeaders: parsed?.headerBlock,
                    responseBody: parsed?.body,
                    errorMessage: "Blocked by block list",
                    wasMappedLocal: false,
                    responseByteCount: blocked.count,
                    wasDecryptedHTTPS: ctx.wasDecryptedHTTPS,
                    clientAppName: ctx.clientAppName,
                    clientIPAddress: ctx.clientIPAddress
                )
            )
            finish(ctx)
            return
        }

        let rules = cb.mapLocalRules()
        if let hit = MapLocalEngine.matchingRule(for: fullURL, rules: rules) {
            serveMapLocal(ctx: ctx, hit: hit)
            return
        }

        if let remoteHit = MapRemoteEngine.matchingRule(for: fullURL, rules: cb.mapRemoteRules()),
           let mapped = MapRemoteEngine.apply(request: request, fullURL: fullURL, rule: remoteHit) {
            request = mapped.request
            fullURL = mapped.fullURL
            host = mapped.host
            port = mapped.port
            wasMappedRemote = true
        }

        var requestRaw = request.raw
        if cb.rewriteEnabled() {
            requestRaw = RewriteRuleEngine.applyRequestRules(requestRaw, url: fullURL, rules: cb.rewriteRules())
        }

        if cb.shouldBreakRequest(fullURL) {
            let headers = HTTPMessageHeaders.headerBlock(from: requestRaw)
            let body = HTTPMessageHeaders.requestBody(from: requestRaw)
            let pending = PendingBreakpoint(
                id: UUID(),
                phase: .request,
                method: request.method,
                url: fullURL,
                host: host,
                headers: headers,
                body: body,
                rawData: requestRaw
            )
            let decision = cb.awaitBreakpoint(pending)
            switch decision.action {
            case .drop:
                if !ctx.wasDecryptedHTTPS {
                    ctx.clientChannel.close(promise: nil)
                }
                finish(ctx)
                return
            case .forward:
                if let modified = decision.modifiedData { requestRaw = modified }
            }
        }

        let toSend = HTTPOutboundRequestNormalizer.apply(to: requestRaw)
        installThrottle(on: ctx.clientChannel, settings: cb.throttleSettings())

        ctx.clientBootstrap.connect(host: host, port: port).flatMap { upstream in
            var buf = upstream.allocator.buffer(bytes: toSend)
            return upstream.writeAndFlush(buf).flatMap {
                upstream.pipeline.addHandler(
                    FeatureAwareRecordingHandler(
                        downstream: ctx.clientChannel,
                        url: fullURL,
                        callbacks: cb,
                        closeDownstreamWhenDone: !ctx.wasDecryptedHTTPS
                    ) { rawResponse in
                        cb.onHTTPExchange(
                            HTTPExchangeRecorder.snapshot(
                                id: ctx.exchangeID,
                                startedAt: ctx.startedAt,
                                request: request,
                                fullURL: fullURL,
                                host: host,
                                rawResponse: rawResponse,
                                errorMessage: nil,
                                wasMappedLocal: false,
                                wasMappedRemote: wasMappedRemote,
                                wasDecryptedHTTPS: ctx.wasDecryptedHTTPS,
                                clientAppName: ctx.clientAppName,
                                clientIPAddress: ctx.clientIPAddress
                            )
                        )
                        finish(ctx)
                    }
                )
            }
        }.whenFailure { err in
            cb.onHTTPExchange(
                HTTPExchangeRecorder.snapshot(
                    id: ctx.exchangeID,
                    startedAt: ctx.startedAt,
                    request: request,
                    fullURL: fullURL,
                    host: host,
                    rawResponse: Data(),
                    errorMessage: err.localizedDescription,
                    wasMappedLocal: false,
                    wasMappedRemote: wasMappedRemote,
                    wasDecryptedHTTPS: ctx.wasDecryptedHTTPS,
                    clientAppName: ctx.clientAppName,
                    clientIPAddress: ctx.clientIPAddress
                )
            )
            if !ctx.wasDecryptedHTTPS {
                ctx.clientChannel.close(promise: nil)
            }
            finish(ctx)
        }
    }

    private static func finish(_ ctx: Context) {
        ctx.onFinished?()
    }

    private static func serveMapLocal(ctx: Context, hit: MapLocalRuleSnapshot) {
        do {
            let (body, contentType) = try MapLocalEngine.loadMappedBody(from: hit)
            let raw = buildMapLocalHTTPResponse(contentType: contentType, body: body)
            ctx.clientChannel.writeAndFlush(ctx.clientChannel.allocator.buffer(bytes: raw)).whenComplete { _ in
                if !ctx.wasDecryptedHTTPS {
                    ctx.clientChannel.close(promise: nil)
                }
            }
            let parsed = try? HTTPResponseParser.parse(raw: raw)
            ctx.callbacks.onHTTPExchange(
                ExchangeSnapshotFactory.httpExchange(
                    id: ctx.exchangeID,
                    startedAt: ctx.startedAt,
                    request: ctx.request,
                    fullURL: ctx.fullURL,
                    host: ctx.host,
                    responseStatus: parsed?.statusCode ?? 200,
                    responseHeaders: parsed?.headerBlock,
                    responseBody: parsed?.body,
                    errorMessage: nil,
                    wasMappedLocal: true,
                    responseByteCount: raw.count,
                    wasDecryptedHTTPS: ctx.wasDecryptedHTTPS,
                    clientAppName: ctx.clientAppName,
                    clientIPAddress: ctx.clientIPAddress
                )
            )
            finish(ctx)
        } catch {
            sendSimpleError(on: ctx.clientContext, text: "Map Local: \((error as NSError).localizedDescription)")
            finish(ctx)
        }
    }

    private static func buildMapLocalHTTPResponse(contentType: String, body: Data) -> Data {
        let head =
            """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.count)\r
            Access-Control-Allow-Origin: *\r
            Connection: close\r
            \r

            """
        return Data(head.utf8) + body
    }

    private static func sendSimpleError(on context: ChannelHandlerContext, text: String) {
        let body = "<html><body><pre>\(text)</pre></body></html>"
        let payload =
            "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let buf = context.channel.allocator.buffer(string: payload)
        _ = context.channel.writeAndFlush(buf)
    }

    private static func installThrottle(on channel: Channel, settings: ThrottleSnapshot) {
        guard settings.isEnabled else { return }
        _ = channel.pipeline.addHandler(ThrottleByteHandler(settings: settings))
    }
}
