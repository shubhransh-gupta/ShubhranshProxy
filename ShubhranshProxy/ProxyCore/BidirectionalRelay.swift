//
//  BidirectionalRelay.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  After CONNECT returns 200, forwards raw TLS bytes between client and origin.
//

import NIOCore
import NIOPosix

/// Forwards `ByteBuffer` reads on this channel to `peer`.
final class PeerRelayHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let peer: Channel
    private var didHalfClosePeer = false

    init(peer: Channel) {
        self.peer = peer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard buffer.readableBytes > 0 else {
            return
        }
        peer.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if peer.isActive, !didHalfClosePeer {
            didHalfClosePeer = true
            _ = peer.close()
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if peer.isActive {
            _ = peer.close()
        }
        context.fireErrorCaught(error)
    }
}
