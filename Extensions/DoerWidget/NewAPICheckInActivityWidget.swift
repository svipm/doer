import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island / lock-screen presentation for the NewAPI batch check-in.
/// Only live on iOS 16.2+ (ActivityKit); the bundle gates its registration.
@available(iOS 16.2, *)
struct NewAPICheckInActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NewAPICheckInActivityAttributes.self) { context in
            LockScreenCheckInCard(
                total: context.attributes.total,
                state: context.state
            )
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(String(localized: "widget.checkin.title", defaultValue: "NewAPI 批量签到"))
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completed)/\(context.attributes.total)")
                        .font(.headline)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CheckInCountRow(state: context.state)
                    ProgressView(
                        value: Double(context.state.completed),
                        total: Double(max(context.attributes.total, 1))
                    )
                    .tint(.green)
                }
            } compactLeading: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text("\(context.state.completed)/\(context.attributes.total)")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
            }
        }
    }
}

@available(iOS 16.2, *)
private struct LockScreenCheckInCard: View {
    let total: Int
    let state: NewAPICheckInActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "widget.checkin.title", defaultValue: "NewAPI 批量签到"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(state.completed)/\(total)")
                    .font(.headline)
                    .monospacedDigit()
            }
            ProgressView(
                value: Double(state.completed),
                total: Double(max(total, 1))
            )
            .tint(.green)
            CheckInCountRow(state: state)
        }
    }
}

@available(iOS 16.2, *)
private struct CheckInCountRow: View {
    let state: NewAPICheckInActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Label("\(state.succeeded)", systemImage: "checkmark")
                .foregroundStyle(.green)
            Label("\(state.alreadySigned)", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            Label("\(state.failed)", systemImage: "xmark")
                .foregroundStyle(.red)
            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
    }
}
