//
//  ShubhranshProxyApp.swift
//  ShubhranshProxy
//
//  Created by Shubhransh Gupta on 29/04/26.
//

import SwiftUI
import CoreData

@main
struct ShubhranshProxyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
