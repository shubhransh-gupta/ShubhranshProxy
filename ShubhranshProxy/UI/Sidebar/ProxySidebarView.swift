//
//  ProxySidebarView.swift
//  ShubhranshProxy — Proxyman-style icon rail + section content
//

import SwiftUI

struct ProxySidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 0) {
            iconRail(selected: state.sidebarSection) { section in
                state.sidebarSection = section
                section.persist()
            }
            Divider()
            DomainsSidebarView(section: state.sidebarSection)
                .id(state.sidebarSection)
        }
        .background(.background)
    }

    private func iconRail(
        selected: SidebarSection,
        onSelect: @escaping (SidebarSection) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(SidebarSection.allCases) { section in
                let isSelected = selected == section
                Button {
                    onSelect(section)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .frame(width: 28, height: 28)
                        Text(section.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 52)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(section.helpText)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(width: 60)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}
