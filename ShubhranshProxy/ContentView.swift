//
//  ContentView.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Legacy entry — main UI is `MainWindowView`.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        MainWindowView()
            .environment(appState)
    }
}

#Preview {
    ContentView()
}
