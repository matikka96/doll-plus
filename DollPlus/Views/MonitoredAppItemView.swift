//
//  MonitoredAppItemView.swift
//  Doll
//
//  Created by xiaogd on 2023/1/11.
//

import SwiftUI
import Monitor

private let statusRefreshInterval: TimeInterval = 1

struct MonitoredAppItemView: View {
    var appItem: MonitoredApp
    var iconRevision: Int
    var openOptions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Storage.appIcon(for: appItem.bundleId))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .id(iconRevision)

            Text(appItem.appName)
                .accessibilityIdentifier("monitoredAppName")

            Spacer()

            TimelineView(.periodic(from: .now, by: statusRefreshInterval)) { _ in
                Text(MonitoredAppStatus(of: appItem).rowText)
                    .foregroundStyle(.secondary)
            }

            Button(action: openOptions) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Icon and alert options")
            .accessibilityLabel("Icon and alert options")
            .accessibilityIdentifier("monitoredAppOptions")
        }
    }
}
