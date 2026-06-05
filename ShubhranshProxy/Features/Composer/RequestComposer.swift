//
//  RequestComposer.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

@MainActor
@Observable
final class RequestComposer {
    var method = "GET"
    var url = "http://127.0.0.1/"
    var headers = "Accept: */*"
    var body = ""
}
