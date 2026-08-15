# IPScanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build from scratch the multiplatform SwiftUI app "IPScanner" (iOS/iPadOS/macOS 26+) — a LAN network scanner equivalent to "IP Scanner - Scanner di Rete" — compilable by anyone without Firebase credentials.

**Architecture:** MVVM + Swift Concurrency. A single multiplatform SwiftUI target (`IPScanner`) using the modern Xcode 26 synchronized-folder project format (new files auto-included). Networking lives in `Services/` as actors/structs over native frameworks only (Network.framework, BSD syscalls, vendorized SimplePing). Optional Firebase Crashlytics initialized defensively. SwiftData persistence with optional CloudKit sync (graceful fallback to local store). UI on `NavigationSplitView` (3 columns), localized EN + IT via String Catalog.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Network.framework (NWBrowser/NWConnection/NWListener), BSD sockets (ICMP, ARP sysctl, getifaddrs), BackgroundTasks, UNUserNotificationCenter, String Catalog (.xcstrings), firebase-ios-sdk (SPM, optional), XCTest.

## Global Constraints

- Deployment target **26.0** for iOS/iPadOS/macOS. **No** visionOS, **no** older OS. Xcode 26.6, Swift 6 (`SWIFT_VERSION = 6.0`).
- Single multiplatform target `IPScanner`, bundle ID `com.alain.IPScanner`, `PRODUCT_NAME = IPScanner`. `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; views/viewmodels `@MainActor`; network services are `actor`s.
- **Only SPM dependency allowed:** `firebase-ios-sdk` (product `FirebaseCrashlytics`), version `from: 12.0.0`. ICMP ping is **vendorized** (`Services/Ping/SimplePing.swift`) — no SPM ping library.
- Crashlytics must be **optional at build time**: build/runtime must never fail when `GoogleService-Info.plist` is absent. Real plists are never committed (`.gitignore` + `GoogleService-Info.plist.example` committed).
- Base language English, second **Italian**, via String Catalog `Localizable.xcstrings`. Dates/numbers use `Locale.current`.
- UI: semantic adaptive colors, SF Symbols, Dynamic Type, VoiceOver labels, ≥44pt touch targets, NavigationSplitView 3-column collapsing on iPhone, curated empty states.
- App icon direction approved: **Radar di scansione** (cyan rings on navy, green blip). **No** StoreKit/Pro.
- Commit style: conventional (`feat:`, `fix:`, `chore:`, `docs:`), concise, English, **no AI/co-author trailers**.

---

### Task 1: Project configuration (pbxproj) + clean app shell

**Files:**
- Modify: `IPScanner.xcodeproj/project.pbxproj`
- Rewrite: `IPScanner/IPScannerApp.swift`
- Delete: `IPScanner/ContentView.swift`, `IPScanner/Item.swift` (replaced by real views/models later)
- Create: `IPScanner/IPScanner-macOS.entitlements`

**Interfaces:**
- Produces: a single target `IPScanner` building for `iphoneos iphonesimulator macosx`, deployment 26.0, Swift 6. Buildable shell: `xcodebuild -project IPScanner.xcodeproj -scheme IPScanner -sdk iphonesimulator build` and `... -sdk macosx build` both succeed.

- [ ] **Step 1: Edit target Debug build settings** (`B52156DF3030AE8F000013D0`) — change:
  - `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `MACOSX_DEPLOYMENT_TARGET = 26.0`, remove `XROS_DEPLOYMENT_TARGET`.
  - `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (drop `xros xrsimulator`).
  - `TARGETED_DEVICE_FAMILY = "1,2"` (drop 7).
  - `SWIFT_VERSION = 6.0` (was 5.0).
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (was MainActor).
  - `PRODUCT_NAME = IPScanner`.
  - Add `CODE_SIGN_ENTITLEMENTS = "IPScanner/IPScanner.entitlements";` and `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = "IPScanner/IPScanner-macOS.entitlements";`.
  - Add `INFOPLIST_KEY_CFBundleDisplayName = IPScanner;`.
- [ ] **Step 2: Repeat the same edits for target Release** (`B52156E0303030AE8F000013D0`).
- [ ] **Step 3: Project-level knownRegions** — add `it` to `knownRegions = (en, Base, it)`.
- [ ] **Step 4: Create `IPScanner/IPScanner-macOS.entitlements`**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array><string>iCloud.com.alain.IPScanner</string></array>
	<key>com.apple.developer.icloud-services</key>
	<array><string>CloudKit</string></array>
</dict>
</plist>
```
- [ ] **Step 5: Update `IPScanner/IPScanner.entitlements`** — set the container ID to `iCloud.com.alain.IPScanner`; remove the bogus `com.apple.developer.aps-environment` key (keep aps for future push only if needed — for local notifications + CloudKit it is not required, so drop both aps keys).
- [ ] **Step 6: Rewrite `IPScannerApp.swift`** to a minimal, clean shell (no Item): `@main struct IPScannerApp: App` with `WindowGroup { Text("IPScanner") }`. Delete `ContentView.swift` and `Item.swift`.
- [ ] **Step 7: Validate** — run:
  - `xcodebuild -list -project IPScanner.xcodeproj` (parses pbxproj)
  - `xcodebuild -project IPScanner.xcodeproj -scheme IPScanner -sdk iphonesimulator build` (Debug)
  - `xcodebuild -project IPScanner.xcodeproj -scheme IPScanner -sdk macosx build`
  Expected: both build successfully with no warnings.
- [ ] **Step 8: Commit** — `chore: configure project for swift 6 multiplatform builds`

---

### Task 2: Unit test target + shared scheme

**Files:**
- Modify: `IPScanner.xcodeproj/project.pbxproj`
- Create: `IPScanner.xcodeproj/xcshareddata/xcschemes/IPScanner.xcscheme`
- Create: `IPScannerTests/SmokeTests.swift`

**Interfaces:**
- Produces: `IPScannerTests` XCTest target (bundle `IPScannerTests.xctest`), runnable via `xcodebuild test -scheme IPScanner -destination 'platform=macOS'`.

- [ ] **Step 1: pbxproj** — add `PBXFileSystemSynchronizedRootGroup` `IPScannerTests` (path `IPScannerTests`, target = test target), a `PBXNativeTarget` `IPScannerTests` (productType `com.apple.product-type.bundle.unit-test`, product `IPScannerTests.xctest`, buildPhases Sources/Frameworks/Resources, `fileSystemSynchronizedGroups`), `PBXContainerItemProxy` + `PBXTargetDependency` from `IPScanner` to `IPScannerTests`, `PBXBuildFile` for `IPScannerTests.xctest` in the app's Frameworks phase, build configurations (Debug/Release) for the test target, and the test target in the `TargetAttributes` (with `TestTargetID` back to the app). Reuse the app's project-level settings via `PBXFileSystemSynchronizedRootGroup`. Use fresh 24-hex UUIDs for new objects.
- [ ] **Step 2: Add a passing smoke test** `IPScannerTests/SmokeTests.swift`:
```swift
import XCTest
@testable import IPScanner

final class SmokeTests: XCTestCase {
    func testProjectLoads() { XCTAssertTrue(true) }
}
```
- [ ] **Step 3: Create shared scheme** `IPScanner.xcscheme` with BuildAction (build `IPScanner`, buildForTesting), TestAction (Testables → `IPScannerTests`), LaunchAction (runnable `IPScanner`), with `LastUpgradeVersion = 2660` and `version = "1.7"`.
- [ ] **Step 4: Validate** — `xcodebuild test -project IPScanner.xcodeproj -scheme IPScanner -destination 'platform=macOS'` → build + test pass (1 passing).
- [ ] **Step 5: Commit** — `chore: add unit test target and shared scheme`

---

### Task 3: Optional Firebase Crashlytics (SPM + run script + service + CI scripts)

**Files:**
- Modify: `IPScanner.xcodeproj/project.pbxproj`
- Create: `IPScanner/Services/CrashReportingService.swift`
- Create: `IPScannerTests/CrashReportingServiceTests.swift`
- Create: `GoogleService-Info.plist.example`
- Create: `CI/ci_scripts/ci_post_clone.sh`, `CI/ci_scripts/ci_post_xcodebuild.sh`

**Interfaces:**
- Produces: `CrashReportingService` (singleton) with:
```swift
public final class CrashReportingService: @unchecked Sendable {
    public static let shared: CrashReportingService
    public private(set) var isEnabled: Bool
    public func configure(bundle: Bundle = .main, firebaseConfigure: (() -> Void)? = nil)
    public func triggerTestCrash()  // DEBUG only, fatalError()
}
```
  `configure()` sets `isEnabled = bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil`; if enabled calls `firebaseConfigure ?? { FirebaseApp.configure() }`; else logs `"Crashlytics disabled: GoogleService-Info.plist not found"`.
- Consumes: called once from `IPScannerApp.init()` before body.

- [ ] **Step 1: pbxproj — add SPM package.** Add section:
```
/* Begin XCRemoteSwiftPackageReference section */
    <ID1> /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {
        isa = XCRemoteSwiftPackageReference;
        repositoryURL = "https://github.com/firebase/firebase-ios-sdk";
        requirement = { kind = upToNextMajorVersion; minimumVersion = 12.0.0; };
    };
/* End XCRemoteSwiftPackageReference section */
```
  Add `XCSwiftPackageProductDependency` `<ID2>` for product `FirebaseCrashlytics` with `package = <ID1>`. Add `packageProductDependencies = ( <ID2> /* FirebaseCrashlytics */ );` to the `IPScanner` target. Also add `packageReferences` — for objectVersion 77, the package is referenced only via the target's `packageProductDependencies`.
- [ ] **Step 2: pbxproj — Crashlytics run script phase (LAST build phase)**:
```
/* Begin PBXShellScriptBuildPhase section */
    <ID3> /* Run Crashlytics */ = {
        isa = PBXShellScriptBuildPhase;
        buildActionMask = 2147483647;
        files = ( );
        inputFileListPaths = ( );
        inputPaths = (
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}",
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}",
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist",
            "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
            "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",
        );
        name = "Run Crashlytics";
        outputFileListPaths = ( );
        outputPaths = ( );
        runOnlyForDeploymentPostprocessing = 0;
        shellPath = /bin/sh;
        shellScript = "SCRIPT=\"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run\"\nPLIST=\"${PROJECT_DIR}/IPScanner/GoogleService-Info.plist\"\nif [ ! -f \"$PLIST\" ]; then\n  echo \"Crashlytics disabled: GoogleService-Info.plist not found\"\n  exit 0\nfi\nif [ ! -f \"$SCRIPT\" ]; then\n  echo \"Crashlytics: run script not found, skipping\"\n  exit 0\nfi\n\"$SCRIPT\"\n";
        alwaysOutOfDate = 1;
    };
/* End PBXShellScriptBuildPhase section */
```
  Add `<ID3>` to the target's `buildPhases` **after** Resources. (The official template sets `alwaysOutOfDate = 1` so dSYM upload runs on every build.)
- [ ] **Step 3: Write `CrashReportingService.swift`** (defensive init, `import FirebaseCore` only inside `#if canImport(FirebaseCore)` / `#if DEBUG` for test crash; guard so the file compiles even if Firebase product is missing — it won't be, but keep `import FirebaseCore` guarded with `canImport`).
- [ ] **Step 4: Wire in `IPScannerApp.init()`**: `CrashReportingService.shared.configure()`.
- [ ] **Step 5: Test** `CrashReportingServiceTests.swift`:
```swift
import XCTest
@testable import IPScanner

final class CrashReportingServiceTests: XCTestCase {
    func testDisabledWhenPlistMissing() {
        let service = CrashReportingService()
        service.configure(bundle: Bundle(for: Self.self), firebaseConfigure: { XCTFail("should not configure") })
        XCTAssertFalse(service.isEnabled)
    }
}
```
  Note: tests link the app (and thus Firebase); `configure` with a bundle lacking the plist must not crash.
- [ ] **Step 6: Create `GoogleService-Info.plist.example`** with placeholder values (empty strings / `YOUR_...`).
- [ ] **Step 7: Write `CI/ci_scripts/ci_post_clone.sh`** (executable `chmod +x`):
```bash
#!/bin/sh
# Xcode Cloud: writes GoogleService-Info.plist from a base64 secret, if provided.
set -e
PLIST="$CI_PRIMARY_REPOSITORY_PATH/IPScanner/GoogleService-Info.plist"
if [ -n "$GOOGLE_SERVICE_INFO_B64" ]; then
  echo "$GOOGLE_SERVICE_INFO_B64" | base64 --decode > "$PLIST"
  echo "Crashlytics: GoogleService-Info.plist written from secret."
else
  echo "Crashlytics: GOOGLE_SERVICE_INFO_B64 not set; Crashlytics will be disabled for this build."
fi
```
- [ ] **Step 8: Write `CI/ci_scripts/ci_post_xcodebuild.sh`** (executable; runs only on Archive workflows):
```bash
#!/bin/sh
# Xcode Cloud: uploads dSYMs to Crashlytics after an archive build, if the plist exists.
set -e
PLIST="$CI_PRIMARY_REPOSITORY_PATH/IPScanner/GoogleService-Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "Crashlytics: plist not found, skipping dSYM upload."; exit 0
fi
[ -z "$CI_ARCHIVE_PATH" ] && { echo "Crashlytics: no archive, skipping dSYM upload."; exit 0; }
DSYMS="$CI_ARCHIVE_PATH/dSYMs"
[ -d "$DSYMS" ] || { echo "Crashlytics: no dSYMs folder, skipping."; exit 0; }
UPLOAD_SYMBOLS="$CI_DERIVED_DATA_PATH/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
if [ ! -f "$UPLOAD_SYMBOLS" ]; then
  # fallback: locate in checkouts
  UPLOAD_SYMBOLS=$(find "$CI_DERIVED_DATA_PATH/SourcePackages/checkouts" -path '*Crashlytics/upload-symbols' 2>/dev/null | head -1)
fi
[ -f "$UPLOAD_SYMBOLS" ] || { echo "Crashlytics: upload-symbols not found, skipping."; exit 0; }
# detect platform from the first dSYM's Info.plist
PLATFORM=ios
FIRST_DSYM=$(find "$DSYMS" -name '*.dSYM' | head -1)
if [ -n "$FIRST_DSYM" ]; then
  SUPPORTED=$(/usr/libexec/PlistBuddy -c "Print :CFBundleSupportedPlatforms" "$FIRST_DSYM/Contents/Info.plist" 2>/dev/null || true)
  case "$SUPPORTED" in *MacOSX*) PLATFORM=macos ;; esac
fi
"$UPLOAD_SYMBOLS" -gsp "$PLIST" -p "$PLATFORM" "$DSYMS"
echo "Crashlytics: dSYMs uploaded for platform $PLATFORM."
```
- [ ] **Step 9: Validate build WITH and WITHOUT plist.**
  - Move the real plist aside temporarily (`mv IPScanner/GoogleService-Info.plist /tmp/`), build both platforms + run tests → must pass with "Crashlytics disabled" logged. Restore the plist, build again → must pass.
  - `xcodebuild -project IPScanner.xcodeproj -scheme IPScanner -sdk iphonesimulator build` and `-sdk macosx build`.
- [ ] **Step 10: Commit** — `feat: add optional crashlytics integration`

---

### Task 4: Core value types — IPv4 address + CIDR (TDD)

**Files:**
- Create: `IPScanner/Models/IPAddress.swift`
- Create: `IPScannerTests/IPv4Tests.swift`

**Interfaces (canonical — used by later tasks):**
```swift
public struct IPv4Address: Hashable, Sendable, Codable, CustomStringConvertible {
    public let a, b, c, d: UInt8
    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8)
    public init?(_ string: String)          // "192.168.1.5"; nil on malformed
    public var description: String
    public var uint32: UInt32               // network byte order value
    public init(uint32: UInt32)
    public func next() -> IPv4Address?      // nil on 255.255.255.255
    public var isHostAddress: Bool          // !(.0 or .255)
}

public enum IPv4CIDR {
    public static func parse(_ cidr: String) -> (network: IPv4Address, prefix: UInt8)?  // nil on invalid
    public static func hostAddresses(_ cidr: String, maxHosts: Int = 4096) -> [IPv4Address]
    public static func hostAddresses(network: IPv4Address, prefix: UInt8, maxHosts: Int = 4096) -> [IPv4Address]
    public static func broadcast(of network: IPv4Address, prefix: UInt8) -> IPv4Address
}
```

- [ ] **Step 1: Write failing tests** `IPv4Tests.swift`: parse valid "192.168.1.5"; reject "256.1.1.1", "abc", "1.2.3"; `description` round-trip; `next()` from 192.168.1.1 → 192.168.1.2; `isHostAddress` false for x.x.x.0 and x.x.x.255. CIDR: `parse("192.168.1.0/24")` → network 192.168.1.0, prefix 24; `hostAddresses("10.0.0.0/30")` → exactly [10.0.0.1, 10.0.0.2]; `hostAddresses("192.168.1.0/24", maxHosts: 10)` → 10 addresses; `broadcast(192.168.1.0, 24)` → 192.168.1.255; `parse("192.168.1.0")` → nil; `parse("1.2.3.0/33")` → nil.
- [ ] **Step 2: Run tests** → fail (types undefined).
- [ ] **Step 3: Implement `IPAddress.swift`** (IPv4Address from String via split on "." with exactly 4 parts, each 0...255; uint32 big-endian `(a<<24)|(b<<16)|(c<<8)|d`; CIDR parse via splitting on "/", prefix 0...32; hostAddresses excludes network and broadcast, caps at maxHosts, iterates uint32+1).
- [ ] **Step 4: Run tests** → pass.
- [ ] **Step 5: Commit** — `feat: add ipv4 address and cidr parsing`

---

### Task 5: OUI vendor lookup (TDD)

**Files:**
- Create: `IPScanner/Services/OUILookupService.swift`
- Create: `IPScannerTests/OUILookupTests.swift`
- Create: `IPScanner/Resources/oui-database.json` (generated — see step 2)

**Interfaces:**
```swift
public actor OUILookupService {
    public struct Entry: Sendable { public let prefix: String; public let vendor: String }
    public init(bundle: Bundle = .main, fileName: String = "oui-database")
    public func vendorName(forMAC mac: String) async -> String?  // "AA:BB:CC" prefix match, case-insensitive
    public var count: Int
}
```

- [ ] **Step 1: Write failing tests** `OUILookupTests.swift`: service loads bundled dataset (`count > 1000`); known prefix like "F4:5C:89" (Apple) → non-nil vendor; lookup with lowercase/dash form "f4-5c-89:..." matches; unknown prefix "ZZ:99:99" → nil; malformed MAC "" → nil.
- [ ] **Step 2: Generate `oui-database.json`** — download public IEEE registry and compress to `{ "PREFIX": "Vendor" }`:
  `curl -s https://standards-oui.ieee.org/oui/oui.txt -o /tmp/oui.txt` then process with `awk`/`swift` into JSON. Format per line: `F45C89	(hex)		Apple, Inc.`. Script (bash+awk) produces compact JSON sorted by key. Commit the generated JSON (~30k entries, a few hundred KB).
- [ ] **Step 3: Implement `OUILookupService.swift`** — `actor`, decodes JSON `[String:String]`, normalizes MAC (strip `-`/`:`/`.`, uppercase, take first 6 hex chars), lookup; builds a `[String:String]` in init; `count` from dictionary.
- [ ] **Step 4: Run tests** → pass.
- [ ] **Step 5: Commit** — `feat: add oui vendor lookup`

---

### Task 6: Wake-on-LAN magic packet (TDD)

**Files:**
- Create: `IPScanner/Services/WakeOnLANService.swift`
- Create: `IPScannerTests/MagicPacketTests.swift`

**Interfaces:**
```swift
public enum MagicPacket {
    public static func build(forMAC mac: String) -> Data?   // 6×0xFF + 16×MAC, 102 bytes
}
public struct WakeOnLANService: Sendable {
    public init()
    public func sendWake(mac: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) async throws
}
```

- [ ] **Step 1: Write failing tests** `MagicPacketTests.swift`: valid "AA:BB:CC:DD:EE:FF" → Data count 102, first 6 bytes all 0xFF, bytes 6..102 are the MAC repeated 16×; invalid "" → nil; invalid "ZZ:..." → nil.
- [ ] **Step 2: Run** → fail. 
- [ ] **Step 3: Implement** `MagicPacket.build` (parse 6 hex octets → 6 bytes, repeat 16× after 6×0xFF) and `WakeOnLANService.sendWake` via `NWConnection` to UDP `send` `host:` `port:` on broadcast address (Network.framework `NWConnection(to: UDP.broadcast...)` or `NWConnection(host:port:using: .udp)` + `send(content:)`); throws on error.
- [ ] **Step 4: Run tests** → pass.
- [ ] **Step 5: Commit** — `feat: add wake on lan`

---

### Task 7: Subnet detection (getifaddrs)

**Files:**
- Create: `IPScanner/Services/SubnetService.swift`

**Interfaces:**
```swift
public struct NetworkInterface: Sendable, Equatable {
    public let name: String            // "en0"
    public let ipAddress: String
    public let netmask: String
    public let prefixLength: UInt8
    public let broadcastAddress: String?
    public var cidr: String            // "192.168.1.0/24"
}
public enum SubnetService {
    public static func primaryIPv4Interface() -> NetworkInterface?  // first non-loopback, IPv4
    public static func isPrivateIP(_ ip: String) -> Bool
}
```

- [ ] **Step 1: Implement** `SubnetService` — `getifaddrs`, iterate `ifaddrs`, `ifa_addr->sa_family == AF_INET`, skip loopback (`IFF_LOOPBACK`) and link-local (`169.254`), prefer names starting `en`/`eth`; compute prefixLength from netmask via bit count; broadcast from address|~mask; `cidr` from ip+prefix. `isPrivateIP` checks 10/8, 172.16/12, 192.168/16.
- [ ] **Step 2: Validate** — small `#Preview`/temporary test or build + a one-off `swift` check is not possible (app target). Instead assert via unit test on the pure helpers if extracted, else build-only. Add `SubnetServiceTests` for `isPrivateIP` + prefix-from-mask helper if factored out. Keep minimal: build + `xcodebuild test` passes.
- [ ] **Step 3: Commit** — `feat: add subnet detection`

---

### Task 8: Vendorized SimplePing + PingService (TDD)

**Files:**
- Create: `IPScanner/Services/Ping/SimplePing.swift`
- Create: `IPScanner/Services/Ping/PingService.swift`
- Create: `IPScannerTests/PingTests.swift`

**Interfaces:**
```swift
public struct PingResult: Sendable, Hashable {
    public let address: String
    public let succeeded: Bool
    public let roundTripTime: TimeInterval?   // seconds
    public let errorDescription: String?
}
public actor PingService {
    public init(timeout: TimeInterval = 1.5)
    public func ping(host: String) async -> PingResult
    public func pingSweep(addresses: [String], onResult: @escaping @Sendable (PingResult) -> Void) async -> [PingResult]
    public func pingSweep(addresses: [String], concurrency: Int = 32) -> AsyncStream<PingResult>
}
```

- [ ] **Step 1: Write failing test** `PingTests.swift`: `MagicPacket`-independent — test the checksum helper + sequence via a small pure static function on SimplePing if exposed (`SimplePing.inetChecksum(_ bytes:)`). Assert checksum of a known ICMP echo packet equals expected value computed independently (e.g. Apple sample's test vector).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement `SimplePing.swift`** — a faithful Swift 6 port of Apple's `SimplePing` (BSD sockets `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`, build ICMP echo request with identifier/sequence, compute checksum, `sendto`, `recv` in a loop with `setsockopt(SO_RCVTIMEO)` for timeout, parse echo reply, match id/seq). Wrap in a `final class SimplePing: @unchecked Sendable` exposing `sendEchoRequest(to host: String, identifier: UInt16, sequence: UInt16) async -> PingResult`. No delegate pattern; async via a single task doing send+recv with timeout.
- [ ] **Step 4: Implement `PingService`** actor: `ping(host:)` builds a `SimplePing`, sends one echo, returns `PingResult`. `pingSweep` uses `TaskGroup` (concurrency-limited) over addresses, calling `ping`, emitting via callback or `AsyncStream`; returns collected results.
- [ ] **Step 5: Run tests** → pass (checksum test; actual network ping not exercised in CI).
- [ ] **Step 6: Commit** — `feat: add icmp ping service`

---

### Task 9: ARP table reader (sysctl)

**Files:**
- Create: `IPScanner/Services/ARPTableService.swift`

**Interfaces:**
```swift
public struct ARPEntry: Sendable, Hashable {
    public let ipAddress: String
    public let macAddress: String?   // nil when incomplete
    public let interface: String?
}
public enum ARPTableService {
    public static func read() -> [ARPEntry]      // sysctl NET_RT_FLAGS/RTF_LLINFO
    public static func macAddress(for ip: String) -> String?   // dictionary lookup
}
```

- [ ] **Step 1: Implement** — `sysctl` `PF_ROUTE/AF_INET/NET_RT_FLAGS` with flag `RTF_LLINFO`; parse `rt_msghdr` structs; for `AF_INET` entries read `sockaddr_in` dst → IP, and the following `sockaddr_dl` → MAC (bytes 6..12) and interface name (`sdl_data`). Handle alignment via `AlignedStorage`/`MemoryLayout` offsets as Apple's Reachability does. Comment the BSD offsets thoroughly (non-obvious logic).
- [ ] **Step 2: Validate** — build for both platforms; add a unit test only for any extracted pure parsing helper if feasible; otherwise manual check on macOS (the macOS test host has an ARP table — test `read()` returns non-empty on macOS via an XCTest guarded with `#if os(macOS)` that doesn't fail the suite if empty).
- [ ] **Step 3: Commit** — `feat: add arp table reader`

---

### Task 10: Bonjour discovery + port scan (TDD for port scan helpers)

**Files:**
- Create: `IPScanner/Services/BonjourDiscoveryService.swift`
- Create: `IPScanner/Services/PortScanService.swift`
- Create: `IPScannerTests/PortScanTests.swift`

**Interfaces:**
```swift
public actor BonjourDiscoveryService {
    public init()
    public func resolveHostnames(for addresses: Set<String>, duration: TimeInterval = 3) async -> [String: String]  // ip -> hostname
}
public struct PortScanConfiguration: Sendable {
    public var ports: [UInt16]
    public var timeout: TimeInterval
    public var concurrency: Int
    public static let common: [UInt16]
}
public struct OpenPort: Sendable, Hashable {
    public let port: UInt16
    public let serviceName: String?
}
public actor PortScanService {
    public func scan(host: String, configuration: PortScanConfiguration, onResult: @escaping @Sendable (OpenPort) -> Void) async -> [OpenPort]
}
```

- [ ] **Step 1: Write failing tests** `PortScanTests.swift`: `PortScanConfiguration.common` contains 22, 80, 443; a pure helper `PortScanService.serviceName(for port:)` maps 80→"http", 443→"https", 22→"ssh", 12345→nil. (No live network in unit tests.)
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement `PortScanService`** — `NWConnection` to `host:port` TCP, `start()` then `send` empty / wait `stateUpdateHandler == .ready` within timeout via `Task` + continuation; build a `withCheckedThrowingContinuation`-based connect-check; `scan` uses `TaskGroup` with semaphore-limited concurrency (`withTaskGroup` + `next()`), calls `onResult` per open port, returns sorted array.
- [ ] **Step 4: Implement `BonjourDiscoveryService`** — `NWBrowser(for: .bonjour(type: "_services._dns-sd._udp", domain: nil))` + a browser per type list `["_http._tcp", "_ssh._tcp", "_airplay._tcp", "_smb._tcp", ...]`, collect `NWEndpoint.service` hostnames, then `NWConnection`-free: map hostname→IP via a small `resolver` (or accept hostname-only results); merge into `[ip: hostname]` where the resolved endpoint's hostname matches the scanned addresses. Keep best-effort and non-blocking within `duration`.
- [ ] **Step 5: Run tests** → pass. Build both platforms.
- [ ] **Step 6: Commit** — `feat: add bonjour discovery and port scan`

---

### Task 11: Scan coordinator (orchestrator)

**Files:**
- Create: `IPScanner/Services/NetworkScannerCoordinator.swift`

**Interfaces (canonical):**
```swift
public struct ScannedDevice: Sendable, Hashable, Identifiable {
    public let id: String              // ip
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let vendor: String?
    public let firstSeen: Date
    public let lastSeen: Date
    public let isOnline: Bool
    public var isNew: Bool             // filled by VM from metadata/whitelist
}
public enum ScanPhase: Sendable { case idle, subnetDetection, pinging(completed: Int, total: Int), arpReading, bonjourDiscovery, finishing }
public enum ScanEvent: Sendable {
    case phase(ScanPhase)
    case device(ScannedDevice)
    case completed(summary: ScanSummary)
}
public struct ScanSummary: Sendable { public let totalResponded: Int; public let duration: TimeInterval; public let started: Date }
public actor NetworkScannerCoordinator {
    public init()
    public func scan(cidr: String, includeBonjour: Bool = true) -> AsyncStream<ScanEvent>
    public func cancel()
}
```

- [ ] **Step 1: Implement** — `scan(cidr:)` builds `AsyncStream` (buffering `.bufferingNewest(16)`); emits `.phase(.subnetDetection)`; expands CIDR via `IPv4CIDR.hostAddresses`; emits `.phase(.pinging(...))`; runs `PingService.pingSweep` with `onResult` emitting `.device(...)` per response; then `.phase(.arpReading)`, reads `ARPTableService.read()`, attaches MACs (via `macAddress(for:)` lookup) to ping responders; optional `.phase(.bonjourDiscovery)` → hostname map; builds `ScannedDevice`s; `.completed(summary)`. Keep the whole thing cancellable via `withTaskCancellationHandler`/Task cancel.
- [ ] **Step 2: Validate** — build both platforms; no unit test (needs live network) beyond a compile-time smoke; manual run via a small debug print in a temporary preview not committed.
- [ ] **Step 3: Commit** — `feat: add network scan coordinator`

---

### Task 12: SwiftData persistence with CloudKit fallback

**Files:**
- Create: `IPScanner/Models/Device.swift`, `IPScanner/Models/ScanSession.swift`, `IPScanner/Models/CustomNetworkRange.swift`
- Create: `IPScanner/App/PersistenceController.swift`

**Interfaces:**
```swift
@Model final class Device {
    var ipAddress: String; var macAddress: String?; var hostname: String?
    var vendor: String?; var customName: String?; var customIcon: String?
    var isWhitelisted: Bool; var firstSeen: Date; var lastSeen: Date; var isOnline: Bool
    init(...)  // all defaults provided (CloudKit-safe)
}
@Model final class ScanSession {
    var startedAt: Date; var cidr: String; var duration: TimeInterval; var deviceSnapshots: [DeviceSnapshot]
    init(...)
}
struct DeviceSnapshot: Codable, Hashable, Sendable { ip, mac, hostname, vendor, isOnline, lastSeen }
@Model final class CustomNetworkRange {
    var name: String; var cidr: String; var icon: String; var sortOrder: Int
    init(...)
}
enum PersistenceController {
    static let container: ModelContainer      // cloud + local configurations, with do/catch fallback
    static var previewContainer: ModelContainer
}
```

- [ ] **Step 1: Implement models** — all `@Model` classes final, properties optional/defaulted for CloudKit compatibility. `DeviceSnapshot` as a Codable struct attribute (no relationships → CloudKit-safe). Store `Device` (cumulative) + `DeviceMetadataOverride`-equivalent fields **folded into `Device`** (`customName`, `customIcon`, `isWhitelisted`) for CloudKit compatibility — documented deviation from spec §7 (avoids to-one relationship restrictions).
- [ ] **Step 2: Implement `PersistenceController`** — `ModelConfiguration("Cloud", schema: [Device, CustomNetworkRange], cloudKitDatabase: .automatic)` at `appSupport` URL + `ModelConfiguration("Local", schema: [ScanSession], cloudKitDatabase: .none)`; `ModelContainer` built in do/catch; **on any error fall back to a local-only container** (no CloudKit) so contributors without iCloud still run; final fallback to in-memory. Expose `previewContainer` (in-memory) for `#Preview`.
- [ ] **Step 3: Wire `IPScannerApp.swift`** — `.modelContainer(PersistenceController.container)`.
- [ ] **Step 4: Validate** — build + `xcodebuild test` (a test creating the container in-memory succeeds).
- [ ] **Step 5: Commit** — `feat: add swiftdata persistence`

---

### Task 13: Notifications + background scanning

**Files:**
- Create: `IPScanner/Services/NotificationService.swift`
- Create: `IPScanner/Services/BackgroundScanService.swift`
- Modify: `IPScanner/Info.plist` (add `UIBackgroundModes` → `fetch`, `processing`)

**Interfaces:**
```swift
public actor NotificationService {
    public static let shared = NotificationService()
    public func requestAuthorization() async -> Bool
    public func notifyNewDevice(_ device: ScannedDevice) async
    public func notifyDeviceWentOffline(_ device: ScannedDevice) async
    public var authorizationStatus: UNAuthorizationStatus
}
public actor BackgroundScanService {
    public static let identifier = "com.alain.IPScanner.refresh"
    public func register()                                     // BGTaskScheduler.shared.register
    public func scheduleNext(earliestBegin: TimeInterval = 60)
    public func handle(task: BGAppRefreshTask)
    public func runScanInBackgroundIfNeeded()                  // macOS: plain timer path is caller-side
}
```

- [ ] **Step 1: Implement `NotificationService`** — `UNUserNotificationCenter.current()`; `requestAuthorization(options: [.alert,.sound,.badge])`; notifications with localized titles/bodies, unique identifiers per device; guard `isEnabled`/authorized.
- [ ] **Step 2: Implement `BackgroundScanService`** — on iOS register `BGAppRefreshTask` (identifier), `scheduleNext` via `BGAppRefreshTaskRequest(identifier:)`, `handle(task:)` runs a bounded scan (reuse `NetworkScannerCoordinator`), calls `task.setTaskCompleted(success:)`; re-schedules. Guard `#if os(iOS)`. macOS: expose a `scheduledTimer`-friendly API but the timer is driven from the VM (see Task 18); document iOS best-effort limits.
- [ ] **Step 3: Info.plist** — set `UIBackgroundModes = [fetch, processing]`.
- [ ] **Step 4: Validate** — build both platforms; no crash on simulator (authorization may be denied).
- [ ] **Step 5: Commit** — `feat: add notifications and background scanning`

---

### Task 14: Export, email, share, P2P Bonjour

**Files:**
- Create: `IPScanner/Services/ExportService.swift`
- Create: `IPScanner/Services/EmailService.swift`
- Create: `IPScanner/Services/P2PTransferService.swift`

**Interfaces:**
```swift
public enum ExportFormat: String, CaseIterable, Sendable { case csv, json }
public enum ExportService {
    public static func data(for devices: [ScannedDevice], format: ExportFormat) -> Data
    public static func csvString(for devices: [ScannedDevice]) -> String
    public static func jsonString(for devices: [ScannedDevice]) -> String
}
public enum EmailService {
    public static func compose(subject: String, body: String, attachmentName: String?, attachmentData: Data?, from viewController: Any? = nil)  // iOS: MFMailComposeViewController; macOS: NSSharingService.mail
}
public actor P2PTransferService {
    public static let serviceType = "_ipscanner._tcp"
    public static let bonjourServices: [String] = ["_ipscanner._tcp", "_services._dns-sd._udp"]
    public func startListening() throws -> NWListener
    public func sendJSON(_ payload: Data, to host: String, port: UInt16 = 49491) async throws
}
```

- [ ] **Step 1: Implement `ExportService`** — CSV with header `IP,MAC,Hostname,Vendor,Status,Last Seen` (RFC-4180 quoting), JSON array of device dictionaries; UTF-8 `Data`.
- [ ] **Step 2: Implement `EmailService`** — `#if os(iOS)` `MFMailComposeViewController` (canSendMail check), `#if os(macOS)` `NSSharingService(named: .composeEmail)`; attachment MIME `text/csv`/`application/json`.
- [ ] **Step 3: Implement `P2PTransferService`** — `NWListener` on `serviceType`, send JSON via `NWConnection` (TCP) to discovered peers; `NWBrowser` to discover other instances; payload framed with a length prefix or newline-delimited JSON.
- [ ] **Step 4: Validate** — build both platforms.
- [ ] **Step 5: Commit** — `feat: add export, email, and peer-to-peer transfer`

---

### Task 15: Design system + localization catalog

**Files:**
- Create: `IPScanner/App/Theme.swift`
- Create: `IPScanner/Resources/Localizable.xcstrings` (EN base + IT)
- Create: `IPScanner/Resources/InfoPlist.xcstrings` (NSLocalNetworkUsageDescription IT)
- Modify: `IPScanner/Info.plist` (NSLocalNetworkUsageDescription EN, NSBonjourServices)
- Create: `IPScanner/Assets.xcassets/` semantic color sets (e.g. `NetworkAccent`, `StatusOnline`, `StatusOffline`, `SurfaceRaised`) as adaptive color sets.

**Interfaces:**
```swift
enum RowDensity: String, CaseIterable, Identifiable { case compact, comfortable, spacious
    var id: String { rawValue }; var rowHeight: CGFloat; var label
}
enum Theme {
    static let cornerRadius: CGFloat = 12
    // semantic color helpers
}
extension Color { static var networkAccent: Color { ... } }
```

- [ ] **Step 1: Create adaptive color sets** in the asset catalog (JSON per set: `"appearances": [{"appearance":"luminosity","value":"light"/"dark"}]`).
- [ ] **Step 2: Write `Theme.swift`** — `RowDensity`, spacing/radius constants, `Color` extensions reading from assets (so Light/Dark are automatic).
- [ ] **Step 3: Add `NSLocalNetworkUsageDescription`** = "IPScanner needs access to the local network to detect connected devices." and `NSBonjourServices = ["_ipscanner._tcp", "_services._dns-sd._udp", "_http._tcp", "_ssh._tcp", "_smb._tcp", "_airplay._tcp", "_airtunes._tcp", "_rfb._tcp"]` to `Info.plist`.
- [ ] **Step 4: Create `Localizable.xcstrings`** — JSON schema `{"sourceLanguage":"en","strings":{...},"version":"1.0"}`. Keys (EN base / IT): app/scan states ("Scan", "Scanning…", "No devices found", "Stop", "New device", "Last seen", "IP Address", "MAC Address", "Hostname", "Vendor", "Status", "Online"/"Offline", tools ("Ping", "Port Scan", "Wake on LAN", "Send"), settings ("Settings", "Notifications", "Background scanning", "Custom networks", "Add range", "Row density", "Columns", "Sort by", "Name"/"IP"/"MAC"/"Last seen", "Cumulative mode", "Whitelist", "Export", "Share", "Send by email", "About", "Crash reporting", "Test Crash"), history ("History", "Scan history", "No previous scans"), P2P ("Send to another device"), errors ("Permission denied", "Network unavailable"), empty states, notification bodies ("New device found", "{device} went offline"). Use `"%lld"`-style and `%lld` placeholders where needed with correct `localizations` dictionaries for pluralization only if required (avoid over-pluralization).
- [ ] **Step 5: Create `InfoPlist.xcstrings`** with the Italian value for `NSLocalNetworkUsageDescription` (key form `com.apple.NSLocalNetworkUsageDescription` if needed — use the standard `NSLocalNetworkUsageDescription` key with localized value).
- [ ] **Step 6: Validate** — build both platforms; confirm no "untranslated" warnings are errors. 
- [ ] **Step 7: Commit** — `feat: add design system and localizations`

---

### Task 16: Root navigation + scan list UI + scan flow

**Files:**
- Create: `IPScanner/App/RootView.swift`, `IPScanner/App/AppState.swift`
- Create: `IPScanner/ViewModels/ScanViewModel.swift`
- Create: `IPScanner/Views/ScanList/ScanListView.swift`, `DeviceRowView.swift`, `EmptyStateView.swift`, `ScanProgressView.swift`
- Create: `IPScanner/Views/ScanList/SidebarView.swift`

**Interfaces:**
```swift
@MainActor @Observable final class ScanViewModel {
    var network: CustomNetworkRange?          // nil → default subnet
    var devices: [ScannedDevice]
    var phase: ScanPhase
    var isScanning: Bool
    var sortOrder: SortOrder; var sortAscending: Bool
    var visibleColumns: Set<Column>           // .ip .mac .hostname .vendor .lastSeen .status
    var rowDensity: RowDensity
    var isCumulativeMode: Bool
    var showOnlyNew: Bool
    func startScan(); func stopScan()
    func upsertDevice(_ d: ScannedDevice)     // persistence: Device + ScanSession
}
```

- [ ] **Step 1: Implement `AppState`** (`@Observable`): holds `selectedNetwork`, `selectedDevice`, global settings, notification auth status.
- [ ] **Step 2: Implement `RootView`** — `NavigationSplitView` (sidebar = `SidebarView`, content = `ScanListView`, detail = placeholder/`DeviceDetailView`). Sidebar: "Networks" section (default subnet entry + `CustomNetworkRange` list + "Add" → sheet), "History", "Settings" navigation destinations.
- [ ] **Step 3: Implement `ScanViewModel`** — startScan: get default cidr from `SubnetService.primaryIPv4Interface()` (or selected range), run `NetworkScannerCoordinator.scan` task, collect `.device` events → upsert + persist (Device upsert by ip, create ScanSession on `.completed`), drive `phase`; cumulative mode keeps offline devices with `isOnline=false`; whitelist filter `showOnlyNew`. Sorting/filtering computed.
- [ ] **Step 4: Implement list views** — `ScanListView`: toolbar (scan/stop toggle, sort menu, columns menu, row-density menu, export/share menu), `List`/`Table` of `DeviceRowView`, `ScanProgressView` header, `EmptyStateView` (icon + text + "Start scan" button). `DeviceRowView`: SF Symbol (customIcon or inferred e.g. `desktopcomputer`/`laptopcomputer`/`iphone`), display name (customName ?? hostname ?? ip), subtitle IP · MAC · vendor, status dot, swipe actions (rename, ping, open, wake). Respect `visibleColumns`/`rowDensity`. Localized strings everywhere.
- [ ] **Step 5: Validate** — build + run on simulator; unit-test pure sort/filter helpers where feasible (`ScanViewModelTests` for sort keys and filter logic).
- [ ] **Step 6: Commit** — `feat: add scan list ui and scan flow`

---

### Task 17: Device detail view

**Files:**
- Create: `IPScanner/Views/DeviceDetail/DeviceDetailView.swift`
- Create: `IPScanner/ViewModels/DeviceDetailViewModel.swift`

- [ ] **Step 1: Implement `DeviceDetailViewModel`** (`@Observable`, `@MainActor`): wraps a `ScannedDevice` + its persisted `Device` metadata; `rename()`, `setIcon()`, `toggleWhitelist()`, actions (open browser `http://ip`, open VNC `vnc://ip`, ping once, wake, share).
- [ ] **Step 2: Implement `DeviceDetailView`** — header (large icon, name, ip), info sections (MAC, hostname, vendor, first/last seen, status), editable name field, icon picker (SF Symbols grid), whitelist toggle, action buttons (Open browser / VNC / Ping / Wake on LAN), inline ping result, share. Platform-gated URL opening (`#if os(iOS)` `UIApplication.shared.open` vs `NSWorkspace.shared.open`).
- [ ] **Step 3: Validate** — build both platforms.
- [ ] **Step 4: Commit** — `feat: add device detail view`

---

### Task 18: Tools UI — Ping, Port Scan, Wake on LAN

**Files:**
- Create: `IPScanner/Views/Tools/PingToolView.swift`, `PortScanToolView.swift`, `WolToolView.swift`
- Create: `IPScanner/ViewModels/PingViewModel.swift`, `PortScanViewModel.swift`, `WolViewModel.swift`

- [ ] **Step 1: Ping tool** — target field (defaults to selected device IP), results list with RTT and status, "Ping" button; `PingService`.
- [ ] **Step 2: Port scan tool** — host field, port range/selection (common list + custom range), start/stop, results grid with service names, progress; `PortScanService`.
- [ ] **Step 3: WOL tool** — pick a device (MAC prefilled), broadcast + port fields (defaults 255.255.255.255:9), "Send" with success/error feedback; `WakeOnLANService`.
- [ ] **Step 4: Validate** — build both platforms; localized.
- [ ] **Step 5: Commit** — `feat: add network tools ui`

---

### Task 19: History, custom ranges, settings

**Files:**
- Create: `IPScanner/Views/Settings/SettingsView.swift`, `CustomRangesView.swift`
- Create: `IPScanner/Views/ScanList/HistoryView.swift`
- Create: `IPScanner/ViewModels/HistoryViewModel.swift`

- [ ] **Step 1: HistoryView** — `@Query` ScanSessions list, tap → detail (device snapshot list), export/share per session, delete sessions.
- [ ] **Step 2: CustomRangesView** — add/edit/delete `CustomNetworkRange` (name, cidr with validation via `IPv4CIDR.parse`), persisted.
- [ ] **Step 3: SettingsView** — sections: Notifications (toggle + request auth), Background scanning (toggle, note about iOS limits), Appearance (row density, default sort), Columns (visibleColumns toggles), Cumulative mode default, Whitelist help, Data (export/import JSON), About (version, privacy note), Crash reporting (status: enabled/disabled), hidden "Test Crash" button in DEBUG. Import: file picker JSON → parse → upsert metadata.
- [ ] **Step 4: Validate** — build both platforms.
- [ ] **Step 5: Commit** — `feat: add history, custom networks, and settings`

---

### Task 20: App icon (radar)

**Files:**
- Modify: `IPScanner/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `IPScanner/Assets.xcassets/AppIcon.appiconset/*.png` (generated)

- [ ] **Step 1: Generate PNGs** — write a throwaway Swift script (CoreGraphics) that renders the radar icon: deep navy background (`#0B1220`), two concentric cyan rings, a radial "sweep" wedge, one bright green blip top-right, subtle grid dots. Export a single **1024×1024** image. Use `sips` to derive the iOS universal sizes and macOS sizes (`16,32,64,128,256,512,1024`) and place them with the standard `idiom`/`size`/`scale` keys in `Contents.json` (single-size modern format where supported).
- [ ] **Step 2: Update `Contents.json`** with correct filenames per idiom/size/scale.
- [ ] **Step 3: Validate** — build (asset catalog compiles); `actool` errors none.
- [ ] **Step 4: Commit** — `feat: add app icon`

---

### Task 21: README, LICENSE, repo polish

**Files:**
- Create: `README.md`, `LICENSE` (MIT), `.github/workflows/` (optional CI badge placeholder) — plus `.gitattributes` (`*.pbxproj binary` etc. optional).

- [ ] **Step 1: README.md** (English, with an Italian note) — features list, requirements (iOS/iPadOS/macOS 26+), quick-start build without Firebase, "Crash reporting (optional)" section (works without plist; how to add your own Firebase project), Xcode Cloud secrets setup (`GOOGLE_SERVICE_INFO_B64`), known limitations (simulator, iOS background best-effort, ARP cache), testing instructions, license.
- [ ] **Step 2: LICENSE** — MIT, copyright Alain Lima, 2026.
- [ ] **Step 3: Validate** — markdown links exist; `xcodebuild` instructions in README actually run (spot-check).
- [ ] **Step 4: Commit** — `docs: add readme and license`

---

### Task 22: Final verification and push

- [ ] **Step 1: Clean build both platforms WITH plist** — `xcodebuild -scheme IPScanner -destination 'generic/platform=iOS Simulator' build` and `-destination 'platform=macOS' build`; zero warnings/errors.
- [ ] **Step 2: Clean build both platforms WITHOUT plist** (temporarily move real plist) — must still succeed.
- [ ] **Step 3: Run full test suite** — `xcodebuild test -scheme IPScanner -destination 'platform=macOS'`.
- [ ] **Step 4: `git status` review** — no real plist, no xcuserdata, no `.codegraph`, no `.remember` staged.
- [ ] **Step 5: Push** — `git push -u origin main` (remote `AlainL88/IPScanner` exists). Then, in GitHub: set repo description, topics (`swift`, `network-scanner`, `swiftui`, `ipscanner`), README as front page, and (optionally) enable Actions. Document the Xcode Cloud `GOOGLE_SERVICE_INFO_B64` secret creation steps in the final report to the user.
