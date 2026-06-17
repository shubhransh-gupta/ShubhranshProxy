//
//  BodyFormattingTests.swift
//  ShubhranshProxyTests
//

import Foundation
import Testing
@testable import ShubhranshProxy

struct BodyFormattingTests {
    @Test func displayTextPrettyPrintsJSON() {
        let raw = #"{"name":"test","items":[1,2]}"#.data(using: .utf8)!
        let text = BodyFormatting.displayText(raw)
        #expect(text.contains("\n"))
        #expect(text.contains("\"name\""))
        #expect(text.contains("\"items\""))
    }

    @Test func prettyJSONIfNeededFormatsByContentType() {
        let raw = #"{"a":1}"#
        let pretty = BodyFormatting.prettyJSONIfNeeded(raw, contentType: "application/json")
        #expect(pretty.contains("\n"))
    }

    @Test func prettyJSONIfNeededLeavesPlainTextUntouched() {
        #expect(BodyFormatting.prettyJSONIfNeeded("hello", contentType: "text/plain") == "hello")
    }
}
