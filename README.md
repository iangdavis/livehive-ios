# Live Hive iOS SDK

Minimal Swift package that registers ActivityKit push tokens with Live Hive.

The SDK does **not** create Live Activities, define `ActivityAttributes`, or send updates. ActivityKit and WidgetKit remain your responsibility. Your backend updates and ends activities over HTTP. There is no server SDK.

Canonical API: `https://www.livehive.dev/v1`

## Install

In Xcode: File → Add Package Dependencies, paste:

```text
https://github.com/iangdavis/livehive-ios
```

Choose version **0.1.1** or later. Add the `LiveHive` library to your app target.

```swift
dependencies: [
    .package(url: "https://github.com/iangdavis/livehive-ios.git", from: "0.1.1")
]
```

This folder is also the source copy inside the Live Hive app repo (`sdks/ios`). Add Local still works for development.

## Golden path

```swift
import ActivityKit
import LiveHive

// Requires a public key (lh_pub_...). Never pass lh_live_.
LiveHive.configure(publicKey: "lh_pub_...")

let activity = try Activity.request(
    attributes: DeliveryAttributes(),
    content: .init(state: .init(status: "preparing", eta: 12), staleDate: nil),
    pushType: .token
)

LiveHive.register(activity)
```

`register` observes `activity.pushTokenUpdates`, converts each token to lowercase hex, and POSTs it to:

```text
POST https://www.livehive.dev/v1/activities/register
Authorization: Bearer lh_pub_...
```

Token rotation is handled automatically. Transient HTTP failures (429, 5xx) are retried.

Override `baseURL` only for local development.

## Do not

- Do not pass a server key (`lh_live_...`) to `configure`.
- Do not use this SDK to update or end activities. POST HTTP from your backend with `lh_live_`.
- Do not skip `pushType: .token`, WidgetKit, or `NSSupportsLiveActivities`.

See https://livehive.dev/llms.txt and https://livehive.dev/openapi.json.
