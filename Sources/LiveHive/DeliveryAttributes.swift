#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Shared by the app and the widget. `content_state` over HTTP must use these keys.
@available(iOS 16.1, *)
public struct DeliveryAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var eta: Int

        public init(status: String, eta: Int) {
            self.status = status
            self.eta = eta
        }
    }

    public init() {}
}
#endif
