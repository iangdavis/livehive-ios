#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Canned lock screen + Dynamic Island for `DeliveryAttributes`.
/// Put this in your Widget Extension `WidgetBundle`. You still create the target.
@available(iOS 16.1, *)
public struct DeliveryLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            HStack {
                Text(context.state.status)
                Spacer()
                Text("\(context.state.eta) min")
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                }
            } compactLeading: {
                Text("LH")
            } compactTrailing: {
                Text("\(context.state.eta)m")
            } minimal: {
                Text("\(context.state.eta)")
            }
        }
    }
}
#endif
