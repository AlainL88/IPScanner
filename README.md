# IPScanner

A fast local network scanner for iPhone, iPad and Mac. Discover devices on your Wi-Fi/LAN — IP, MAC address, hostname and vendor — with built-in tools for ping, port scanning, and Wake-on-LAN. Written in Swift 6 with SwiftUI, SwiftData and only Apple frameworks.

**Read this in Italian?** Una versione sintetica in italiano è in fondo al file.

---

## Features

- **LAN scan** — ICMP ping sweep over the primary subnet (or a custom CIDR range), with live progress.
- **Device details** — IP, MAC, hostname and vendor (resolved from a bundled IEEE OUI database), first/last seen, online status.
- **Customization** — rename devices, assign a custom icon, mark trusted devices on a **whitelist**.
- **Cumulative mode** — keep every device ever seen, with offline devices retained.
- **Tools** — Ping, TCP **Port Scan** (common ports or custom list), **Wake-on-LAN**.
- **Quick actions** — open a device in the browser (`http://ip`) or VNC (`vnc://ip`).
- **Sorting & layout** — sort by name/IP/MAC/last seen; toggle visible columns; choose row density.
- **History** — every scan is saved; export/delete sessions.
- **Export & share** — CSV/JSON export, email, and **peer-to-peer transfer** of results between two instances via Bonjour.
- **Notifications** — local notifications for newly discovered devices (best-effort in background on iOS).
- **Localization** — English (base) + Italian.
- **Privacy** — scans happen on-device; the only network access is the local network itself. Optional Crashlytics (see below).

## Requirements

- Xcode 26 or later (project format: Xcode 26, synchronized folders)
- iOS 26 / iPadOS 26 / macOS 26 or later
- Swift 6

> The iOS simulator has limited access to the real local network — test scanning on a physical device.

## Quick start (no Firebase required)

1. Clone the repository.
2. Open `IPScanner.xcodeproj` in Xcode.
3. Select the `IPScanner` scheme and the iOS Simulator (or a Mac).
4. Build & run.

That's it. **The project builds and runs with no configuration and no Firebase credentials.** Crashlytics is simply disabled when `GoogleService-Info.plist` is absent (more below).

To run the unit tests:

```sh
xcodebuild test -project IPScanner.xcodeproj -scheme IPScanner \
  -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
```

> On macOS, the app is **not sandboxed** by default (it targets direct/notarized distribution, which the app's features need — broad local-network access and peer-to-peer listening). If you distribute through the Mac App Store, re-enable the sandbox + `com.apple.security.network.client/server` entitlements.

## Crash reporting (optional)

Crashlytics (Firebase) is an **optional, build-time-only** extra:

- The app checks at runtime whether `GoogleService-Info.plist` is present in the bundle.
  - **Present** → `CrashReportingService` initializes Firebase and Crashlytics is active.
  - **Absent** → Firebase is never initialized; the app logs `Crashlytics disabled: GoogleService-Info.plist not found` and runs normally. No crash, no alert.
- The Crashlytics **run-script build phase** also guards on the plist and exits `0` when it's missing, so builds never fail without credentials.
- Real plists are **never committed** (see `.gitignore`). `GoogleService-Info.plist.example` shows the expected shape.

### Enable it for your own project

1. Create a Firebase project, register an app for your bundle ID (`com.alain.IPScanner`).
2. Download its `GoogleService-Info.plist` and drop it at `IPScanner/GoogleService-Info.plist`.
3. Rebuild — Crashlytics is now active. (The SPM dependency `firebase-ios-sdk` is always resolved; only initialization is conditional.)
4. To verify end-to-end: on a Debug build with the plist present, go to **Settings → About → Test Crash**.

### Xcode Cloud

1. In your Xcode Cloud workflow, add a secret **Environment Variable**:
   - **Name:** `GOOGLE_SERVICE_INFO_B64`
   - **Value:** the base64 of your `GoogleService-Info.plist`
   - Produce the value locally with:
     ```sh
     base64 -i IPScanner/GoogleService-Info.plist | tr -d '\n'
     ```
2. `CI/ci_scripts/ci_post_clone.sh` decodes it into the correct path **before** the build.
3. `CI/ci_scripts/ci_post_xcodebuild.sh` uploads the archived build's **dSYMs** to Crashlytics (only when the plist and an archive are present; otherwise it no-ops safely).
4. Without the secret, builds still succeed — Crashlytics is just disabled.

## Known limitations

- **iOS background scanning** uses `BGAppRefreshTask`; iOS throttles background refreshes, so they are *best-effort* and may be delayed — this is an OS policy, not a bug.
- **ARP cache** only contains hosts that have already been contacted; the scanner pings first to populate it, which is why MACs appear a moment after the sweep.
- **mDNS/Bonjour** enrichment is best-effort and depends on devices advertising services.

## Architecture

```
App/            app entry, root navigation, shared state, persistence controller
Models/         SwiftData models + IPv4/CIDR value types
ViewModels/     scan, detail, tools
Views/          scan list, device detail, tools, history, settings
Services/       network services (all native, no third-party network deps)
  Ping/SimplePing.swift   vendorized Apple SimplePing (Swift 6, async)
Resources/      oui-database.json (IEEE OUI registry), Localizable.xcstrings
CI/ci_scripts/  Xcode Cloud hooks
```

Everything network-related uses **Apple frameworks only**: `Network.framework` (NWBrowser/NWConnection/NWListener), BSD sockets for ICMP and the ARP table (`sysctl PF_ROUTE`), `getifaddrs` for the local subnet. The only SPM dependency is `firebase-ios-sdk` (Crashlytics, optional).

## Testing

- Unit tests: IPv4/CIDR parsing, ICMP checksum, ARP table shape, OUI lookup, Wake-on-LAN magic packet, port-scan (against a real local listener), CSV/JSON export, Crashlytics disabled-without-plist, SwiftData round-trips.
- The suite runs on macOS (fast) with `xcodebuild test` as above; also runnable on an iOS simulator.

## License

MIT — see [LICENSE](LICENSE).

---

## Italiano (sintesi)

**IPScanner** è uno scanner di rete locale per iPhone, iPad e Mac: rileva i dispositivi della tua LAN (IP, MAC, hostname, produttore) con strumenti integrati per Ping, scansione porte e Wake-on-LAN.

- Richiede **Xcode 26+**, **iOS/iPadOS/macOS 26+**, Swift 6.
- **Funziona senza alcuna configurazione**: Crashlytics è un extra opzionale e si disattiva da solo se manca `GoogleService-Info.plist`.
- La lingua principale è l'inglese; la seconda è l'italiano.
- Le limitazioni note (scansione in background iOS "best effort", cache ARP, simulatore) sono descritte sopra.
