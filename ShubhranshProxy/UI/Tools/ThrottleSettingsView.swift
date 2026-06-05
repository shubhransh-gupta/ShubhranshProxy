//
//  ThrottleSettingsView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct ThrottleSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var throttle = features.throttling
        Form {
            Section {
                Toggle("Enable throttling", isOn: $features.throttlingEnabled)
                    .onChange(of: features.throttlingEnabled) { _, _ in appState.syncFeatureMailboxes() }
            }
            Section("Profile") {
                Picker("Network profile", selection: $throttle.selected) {
                    ForEach(ThrottleProfileStore.Profile.allCases) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .onChange(of: throttle.selected) { _, _ in appState.syncFeatureMailboxes() }
                if throttle.selected == .custom {
                    Stepper("Bytes/sec: \(throttle.customBytesPerSecond)", value: $throttle.customBytesPerSecond, in: 1024...5_000_000, step: 1024)
                        .onChange(of: throttle.customBytesPerSecond) { _, _ in appState.syncFeatureMailboxes() }
                }
            }
            Section {
                Text("Throttling applies to data sent back to the client after the origin responds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Throttling")
    }
}
