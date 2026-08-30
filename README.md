# LiveHive iOS SDK

LiveHive starts a Live Activity, registers its push token, and keeps token
rotation synced with your backend. It does not update or end activities.

## Install

In Xcode, add this package:

```text
https://github.com/iangdavis/livehive-ios.git
```

Use the `LiveHive` product in your app target. Version `0.2.0` or later is
recommended.

For richer package discovery in Xcode, add the Live Hive package collection:

```text
https://raw.githubusercontent.com/iangdavis/livehive-ios/main/livehive.package-collection.json
```

Then use Xcode or SwiftPM to add that collection before adding the package.

## Use

```swift
import LiveHive

LiveHive.configure(publicKey: "lh_pub_...")

let activity = try LiveHive.start(
    attributes: DeliveryAttributes(),
    contentState: .init(status: "preparing", eta: 12)
)
```

Send updates from the Live Hive dashboard or your backend with a secret
`lh_live_...` key:

```text
POST https://www.livehive.dev/v1/activities/{activity.id}/update
Authorization: Bearer lh_live_...
```

## Documentation

- Canonical API: `https://www.livehive.dev/v1`
- Getting started: [livehive.dev/docs/getting-started](https://livehive.dev/docs/getting-started)
- OpenAPI: [livehive.dev/openapi.json](https://livehive.dev/openapi.json)
- LLMs guide: [livehive.dev/llms.txt](https://livehive.dev/llms.txt)
