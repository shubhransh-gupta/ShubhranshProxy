//
//  HTTPExchangeRecorder.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Parses a captured raw HTTP response and builds an exchange snapshot for the UI.
//

import Foundation

enum HTTPExchangeRecorder {
    static func snapshot(
        id: UUID,
        startedAt: TimeInterval,
        request: ParsedInboundRequest,
        fullURL: String,
        host: String,
        rawResponse: Data,
        errorMessage: String?,
        wasMappedLocal: Bool,
        wasMappedRemote: Bool = false,
        wasDecryptedHTTPS: Bool = false,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil
    ) -> HTTPExchangeSnapshot {
        let parsed = try? HTTPResponseParser.parse(raw: rawResponse)
        let headerBlock = parsed?.headerBlock
        let decodedBody = HTTPResponseBodyDecoder.decodedBody(headerBlock: headerBlock, body: parsed?.body ?? Data())

        return ExchangeSnapshotFactory.httpExchange(
            id: id,
            startedAt: startedAt,
            request: request,
            fullURL: fullURL,
            host: host,
            responseStatus: parsed?.statusCode,
            responseHeaders: headerBlock,
            responseBody: decodedBody.isEmpty ? parsed?.body : decodedBody,
            errorMessage: errorMessage,
            wasMappedLocal: wasMappedLocal,
            wasMappedRemote: wasMappedRemote,
            responseByteCount: rawResponse.count,
            wasDecryptedHTTPS: wasDecryptedHTTPS,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress
        )
    }
}
