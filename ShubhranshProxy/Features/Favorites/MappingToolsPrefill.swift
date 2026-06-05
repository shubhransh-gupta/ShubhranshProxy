//
//  MappingToolsPrefill.swift
//  ShubhranshProxy — Features
//
//  Created by Shubhransh Gupta
//

import Foundation

struct MappingToolsPrefill: Equatable {
    enum Mode {
        case mapLocal
        case mapRemote
        case allMapped
    }

    var mode: Mode
    var matchURL: String
    var remoteToURL: String = ""
    var responseBody: String = ""
    var contentType: String = "application/json; charset=utf-8"
}
