# Curfew

Ian's iPhone app that locks distracting apps at bedtime while he's in the bedroom. The Mac mini in the bedroom is the anchor: no extra hardware.

- **Apps:** choose apps, categories and websites with Apple's Screen Time picker. Lock just those, or everything except those.
- **Times:** one or more windows (for example 22:30–07:00 on school nights, 23:30–08:30 at weekends), or "any time I'm in the bedroom".
- **Bedroom:** apps lock only while the iPhone is close to the Mac. A range screen measures by the bed and just outside the door to set where the bedroom ends.
- **Breaks:** press and hold for a 15-minute break; apps lock again on their own.
- **Widget:** Home Screen and Lock Screen.

## How it works

- **Mac helper** (`Mac/`, menu bar only, TestFlight for Mac): advertises a Bluetooth LE service (`Shared/Common/Signal.swift`) and sends a heartbeat every 15 seconds to subscribed iPhones. It registers itself to open at login and, by default, stops the Mac idling to sleep (the screen can still sleep).
- **iPhone presence** (`App/Model/BedroomSensor.swift`): a background Bluetooth central with state restoration. It keeps a standing connection request to the Mac and scans for its service, so iOS wakes Curfew when the Mac comes into range or drops out. Each heartbeat wakes it briefly to read the signal strength (smoothed over four readings, with 5 dB of give so the edge doesn't flicker).
- **Locking** (`Shared/Blocking/Blocker.swift`): Screen Time (FamilyControls with individual authorisation, ManagedSettings shields). Locked = Curfew on, in the bedroom, inside a window, not on a break. The app re-evaluates when presence changes; the DeviceActivity monitor extension (`Monitor/`) re-evaluates at each window's start and end and when a break ends. A reading older than 10 minutes counts as "not in the bedroom".
- Shared state lives in the keychain group (as in Ian's other apps), so no App Group is needed.
- Native SwiftUI, iOS 26+ (iPhone), macOS 14+. The Xcode project is generated from `project.yml` with XcodeGen. Icons are drawn by `scripts/make_icon.py`.

## Apple's Screen Time permission

Locking apps outside development needs Apple's **Family Controls (Distribution)** entitlement, approved per identifier (`com.<team>.curfew` and `com.<team>.curfew.Monitor`) via https://developer.apple.com/contact/request/family-controls-distribution. Until it's approved, builds leave the entitlement out (the build lane checks each signing profile) and the app shows "Waiting for Apple" while still showing bedroom presence. Once approved: run **Set up with Apple → refresh-profiles**, then **Build Curfew**.

## Workflows

1. **Set up with Apple**: `check`, `identifiers`, `certificates`, `refresh-profiles` (after Apple's approval), `testers`.
2. **Check build and screenshots**: every push; builds for the simulator and the Mac, runs the self-checks (`-CurfewSelfTest`) and saves screenshots to the `screenshots` branch.
3. **Build Curfew**: iPhone app and Mac helper to TestFlight. Every push to `main`, monthly (so they never expire) and on demand.
