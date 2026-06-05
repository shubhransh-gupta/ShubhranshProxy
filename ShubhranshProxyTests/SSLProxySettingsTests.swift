//
//  SSLProxySettingsTests.swift
//  ShubhranshProxyTests
//  Created by Shubhransh Gupta
//

import Testing
@testable import ShubhranshProxy

struct SSLProxySettingsTests {
    @Test func decryptsRemoteDeviceTrafficWithoutIncludedHosts() {
        var settings = SSLProxySettings()
        settings.isEnabled = true
        settings.interceptAllHosts = false
        settings.interceptRemoteDevices = true
        settings.includedHosts = []

        #expect(settings.shouldIntercept(host: "api.example.com", clientIPAddress: "192.168.1.42"))
        #expect(!settings.shouldIntercept(host: "api.example.com", clientIPAddress: "127.0.0.1"))
        #expect(!settings.shouldIntercept(host: "api.example.com", clientIPAddress: nil))
    }

    @Test func macTrafficStillUsesIncludedHostsWhenSelective() {
        var settings = SSLProxySettings()
        settings.isEnabled = true
        settings.interceptAllHosts = false
        settings.interceptRemoteDevices = true
        settings.includedHosts = ["allowed.com"]

        #expect(settings.shouldIntercept(host: "allowed.com", clientIPAddress: "127.0.0.1"))
        #expect(!settings.shouldIntercept(host: "blocked.com", clientIPAddress: "127.0.0.1"))
    }
}
