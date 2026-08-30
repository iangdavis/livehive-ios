# ``LiveHive``

Register ActivityKit push tokens with Live Hive from your iOS app.

Use this package when you want to start a Live Activity and have the SDK
forward push tokens to the Live Hive API. The SDK does not update or end
activities for you.

## Overview

Typical setup:

1. Call ``LiveHive/configure(publicKey:baseURL:)`` at app launch.
2. Start a Live Activity with ``LiveHive/start(status:eta:type:activityId:)``
   or register an existing activity with ``LiveHive/register(_:activityId:type:)``.
3. Send updates from the Live Hive dashboard or your backend using a secret
   `lh_live_` key.

## Topics

### Getting Started

- ``LiveHive``
- ``LiveHiveConfiguration``
- ``LiveHiveError``
- ``PushToken``

### Live Activity Support

- ``DeliveryAttributes``
- ``DeliveryLiveActivity``
