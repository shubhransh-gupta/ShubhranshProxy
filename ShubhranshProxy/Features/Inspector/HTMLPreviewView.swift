//
//  HTMLPreviewView.swift
//  ShubhranshProxy — Features/Inspector
//  Created by Shubhransh Gupta
//

import SwiftUI
import WebKit

/// Renders HTML response bodies in an embedded WebKit view (AppKit bridge).
struct HTMLPreviewView: NSViewRepresentable {
    let html: String
    var baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(html: html, baseURL: baseURL, into: view)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html: html, baseURL: baseURL, into: webView)
    }

    final class Coordinator {
        private var loadedHTML: String?
        private var loadedBaseURL: URL?

        func load(html: String, baseURL: URL?, into webView: WKWebView) {
            guard loadedHTML != html || loadedBaseURL != baseURL else { return }
            loadedHTML = html
            loadedBaseURL = baseURL
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }
}
