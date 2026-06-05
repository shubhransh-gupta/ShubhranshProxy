//
//  HTTPProxyService.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Binds a TCP listener and dispatches each accepted connection to `HTTPProxyChannelHandler`.
//

import Foundation
import NIOCore
import NIOPosix

actor HTTPProxyService {
    enum State: Sendable, Equatable {
        case stopped
        case running(host: String, port: Int)
    }

    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private(set) var state: State = .stopped

    init() {}

    func start(configuration: HTTPProxyConfiguration = .default, callbacks: ProxyRuntimeCallbacks) async throws {
        guard case .stopped = state else { return }

        let threads = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { child in
                child.pipeline.addHandler(HTTPProxyChannelHandler(group: group, callbacks: callbacks))
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        let bound = try await bootstrap.bind(
            host: configuration.listenHost,
            port: configuration.listenPort
        ).get()

        self.group = group
        self.channel = bound
        self.state = .running(host: configuration.listenHost, port: configuration.listenPort)
    }

    func stop() async {
        if let channel {
            _ = try? await channel.close().get()
        }
        channel = nil
        if let group {
            try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                group.shutdownGracefully { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
        group = nil
        state = .stopped
    }
}
