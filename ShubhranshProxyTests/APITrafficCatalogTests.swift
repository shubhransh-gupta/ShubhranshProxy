//
//  APITrafficCatalogTests.swift
//  ShubhranshProxyTests
//

import Foundation
import Testing
@testable import ShubhranshProxy

struct APITrafficCatalogTests {
    @Test func groupsAllDistinctPathsUnderSameHost() {
        let sessions = [
            makeSession(method: "GET", url: "https://api.example.com/v1/users", host: "api.example.com"),
            makeSession(method: "GET", url: "https://api.example.com/v1/profile", host: "api.example.com"),
            makeSession(method: "POST", url: "https://api.example.com/v1/orders", host: "api.example.com"),
        ]

        let groups = APITrafficCatalog.buildBaseGroups(from: sessions)

        #expect(groups.count == 1)
        #expect(groups[0].host == "api.example.com")
        #expect(groups[0].endpoints.count == 3)
    }

    @Test func doesNotCollapseDifferentPathsOnSameHost() {
        let keyA = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com/a",
            host: "api.example.com"
        )
        let keyB = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com/b",
            host: "api.example.com"
        )
        #expect(keyA != keyB)
    }

    @Test func keepsDifferentQueryStringsSeparate() {
        let sessions = [
            makeSession(method: "GET", url: "https://api.example.com/v1/users?page=1", host: "api.example.com"),
            makeSession(method: "GET", url: "https://api.example.com/v1/users?page=2", host: "api.example.com"),
        ]

        let groups = APITrafficCatalog.buildBaseGroups(from: sessions)

        #expect(groups.count == 1)
        #expect(groups[0].endpoints.count == 2)
    }

    @Test func resolvesOriginFormPathsUnderSameHost() {
        let sessions = [
            makeSession(method: "GET", url: "/v1/users", host: "api.example.com"),
            makeSession(method: "GET", url: "/v1/profile", host: "api.example.com"),
        ]

        let groups = APITrafficCatalog.buildBaseGroups(from: sessions)

        #expect(groups.count == 1)
        #expect(groups[0].endpoints.count == 2)
    }

    @Test func mergesHttpAndHttpsForSamePath() {
        let keyHTTP = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "http://api.example.com/v1/users",
            host: "api.example.com"
        )
        let keyHTTPS = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com/v1/users",
            host: "api.example.com"
        )
        #expect(keyHTTP == keyHTTPS)
    }

    @Test func keepsDifferentPortsSeparate() {
        let keyA = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com:8443/users",
            host: "api.example.com"
        )
        let keyB = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com/users",
            host: "api.example.com"
        )
        #expect(keyA != keyB)
    }

    @Test func keepsSamePathOnDifferentHostsSeparate() {
        let keyA = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://api.example.com/users",
            host: "api.example.com"
        )
        let keyB = APITrafficCatalog.endpointKey(
            method: "GET",
            url: "https://cdn.example.com/users",
            host: "cdn.example.com"
        )
        #expect(keyA != keyB)
    }

    private func makeSession(method: String, url: String, host: String) -> ProxySession {
        ProxySession(
            snapshot: HTTPExchangeSnapshot(
                id: UUID(),
                startedAt: Date().timeIntervalSince1970,
                completedAt: Date().timeIntervalSince1970,
                method: method,
                url: url,
                host: host,
                responseStatus: 200,
                durationMs: 10,
                requestSize: 0,
                responseSize: 0,
                mimeType: nil,
                requestHeaders: "",
                requestBody: Data(),
                responseHeaders: nil,
                responseBody: nil,
                errorMessage: nil,
                wasMappedLocal: false,
                wasMappedRemote: false,
                isCONNECT: false,
                wasDecryptedHTTPS: true,
                clientAppName: "Safari",
                clientIPAddress: "127.0.0.1"
            )
        )
    }
}
