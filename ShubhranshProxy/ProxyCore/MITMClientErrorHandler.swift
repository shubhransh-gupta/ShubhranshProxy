//
//  MITMClientErrorHandler.swift
//  ShubhranshProxy — ProxyCore
//
//  Created by Shubhransh Gupta
//
//  Records TLS handshake failures (e.g. iPhone CA not trusted) as sessions.
//

import Foundation
import NIOCore

final class MITMClientErrorHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let host: String
    private let clientIPAddress: String?
    private let callbacks: ProxyRuntimeCallbacks

    init(host: String, clientIPAddress: String?, callbacks: ProxyRuntimeCallbacks) {
        self.host = host
        self.clientIPAddress = clientIPAddress
        self.callbacks = callbacks
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let detail = Self.friendlyMessage(error, clientIPAddress: clientIPAddress)
        callbacks.onHTTPExchange(
            ExchangeSnapshotFactory.tlsFailure(
                host: host,
                clientIPAddress: clientIPAddress,
                error: detail
            )
        )
        context.close(promise: nil)
    }

    private static func friendlyMessage(_ error: Error, clientIPAddress: String?) -> String {
        let base = error.localizedDescription
        guard let ip = ClientAddressResolver.normalize(clientIPAddress),
              !ClientAddressResolver.isLoopback(ip) else {
            return base
        }
        return """
        \(base)

        iPhone/Android HTTPS failed MITM from \(ip). Install the ShubhranshProxy root CA on the device, then enable full trust under Certificate Trust Settings. Native apps with certificate pinning (e.g. some banking/Lenskart builds) cannot be decrypted — test with Safari first.
        """
    }
}
