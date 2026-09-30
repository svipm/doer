import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island / lock-screen presentation for background Cloudflare
/// verification (visible when the challenge sheet is minimized and the user
/// is elsewhere). Only live on iOS 16.2+ (ActivityKit); the bundle gates it.
@available(iOS 16.2, *)
struct CloudflareVerificationActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CloudflareVerificationActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(context.state.statusText)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                        .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                ProgressView()
                    .controlSize(.small)
            } minimal: {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.orange)
                    .font(.caption2)
            }
        }
    }
}
