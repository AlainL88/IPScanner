# IPScanner — Design

Data: 2026-08-15 · Stato: approvato dall'utente · Autore: Alain Lima

Clone multipiattaforma open source (iOS + iPadOS + macOS) di "IP Scanner - Scanner di Rete" (Matia Labs / 10base-t): network scanner LAN scritto in SwiftUI con Swift 6, Swift Concurrency e solo framework Apple nativi.

## Decisioni approvate dall'utente

- **App icon**: direzione "Radar di scansione" (anelli radar concentrici, fondo blu-notte, accento ciano, blip verde). Implementata come asset AppIcon (iOS + macOS).
- **Upgrade "Pro" (StoreKit 2)**: escluso. Nessun limite di dispositivi, nessun IAP. Adatto a un repo open source MIT.
- **dSYM upload Crashlytics su Xcode Cloud**: richiesto esplicitamente dall'utente (vedi sezione CI).

## 1. Progetto Xcode

- Formato moderno Xcode 26 a **cartelle sincronizzate** (`PBXFileSystemSynchronizedRootGroup`): i file creati in `IPScanner/` e `IPScannerTests/` sono inclusi automaticamente nei rispettivi target. Gli unici edit manuali al `project.pbxproj` riguardano build settings, dipendenza SPM Firebase, run-script build phase e test target; ogni edit è validato con `xcodebuild`.
- **Un solo target multipiattaforma** `IPScanner`:
  - `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `TARGETED_DEVICE_FAMILY = 1,2`.
  - Deployment target **26.0** per iOS/iPadOS/macOS. VisionOS rimosso.
  - `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; viste e ViewModel marcati esplicitamente `@MainActor`; servizi di rete come `actor` off-main.
  - `PRODUCT_NAME = IPScanner`, `PRODUCT_BUNDLE_IDENTIFIER = com.alain.IPScanner`.
  - Entitlements per piattaforma via `CODE_SIGN_ENTITLEMENTS[sdk=*]` (iOS vs macOS): sandbox e network client/server solo su macOS, CloudKit + aps-environment su entrambe.
  - `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`.
- **Target test** `IPScannerTests` (XCTest, synchronized folder `IPScannerTests/`).

## 2. Firebase Crashlytics (opzionale a build-time)

- **Deviazione dallo spec**: singolo target ⇒ bundle ID condiviso iOS/macOS ⇒ **una sola app Firebase** (`ipscanner-c089c`) e **un solo `GoogleService-Info.plist`** valido per entrambe le piattaforme.
- `CrashReportingService`: verifica `Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")` prima di `FirebaseApp.configure()`; se assente logga "Crashlytics disabled: GoogleService-Info.plist not found" e non inizializza. Nessun `fatalError`. Flag `isEnabled`.
- Chiamata da `App.init()`.
- **Run Script Build Phase** (dopo "Copy Bundle Resources"): guard `exit 0` se il plist manca; altrimenti invoca `Crashlytics/run` dal checkout SPM. Gli dSYM locali vengono caricati automaticamente durante Archive.
- **Plist reale**: tolto dallo staging git, aggiunto a `.gitignore`, mai committato. Creato `GoogleService-Info.plist.example` con placeholder.
- **Test Crash nascosto** (solo Debug): `fatalError()` per verificare l'invio end-to-end.

### Xcode Cloud (dSYM + configurazione)

- `ci_scripts/ci_post_clone.sh`: se `GOOGLE_SERVICE_INFO_B64` è definita, la decodifica e scrive `IPScanner/GoogleService-Info.plist` prima della build; altrimenti logga che Crashlytics resta disabilitato.
- `ci_scripts/ci_post_xcodebuild.sh` (**upload dSYM dedicato**): se il plist esiste E `$CI_ARCHIVE_PATH` contiene `dSYMs/`, localizza `firebase-ios-sdk/Crashlytics/run` nei checkout SPM (`$CI_DERIVED_DATA_PATH/SourcePackages/checkouts`) e lo invoca con `-dSYMs "$CI_ARCHIVE_PATH/dSYMs"`. Se mancano plist o archive, esce 0 senza errori.
- Path esatto dello script `run` e flag verificati contro la documentazione ufficiale Firebase durante l'implementazione.
- `Package.resolved` committato per build riproducibili.

## 3. Servizi di rete (nessuna dipendenza SPM)

| Servizio | Tecnica |
|---|---|
| `SubnetService` | `getifaddrs` per IP locale, netmask e subnet. |
| `SimplePing.swift` (vendorizzato) | Porta Swift di SimplePing Apple: socket `SOCK_DGRAM` + `IPPROTO_ICMP`, checksum ICMP, sequence number; riscritto con async/await (niente delegate pattern). ~400 righe, incapsulato da `PingService`. |
| `PingService` (actor) | Sweep ICMP concorrente sulla subnet/range; `AsyncStream<ScanProgress>` per la UI. |
| `ARPTableService` | Legge la cache ARP via `sysctl` (`PF_ROUTE`, `AF_INET`, `NET_RT_FLAGS`, `RTF_LLINFO`) per i MAC dei device che hanno risposto. |
| `BonjourDiscoveryService` | `NWBrowser` (mDNS) per arricchire hostname e servizi esposti. |
| `PortScanService` | `NWConnection` TCP concorrente con `TaskGroup`, concorrenza limitata, porte e timeout configurabili. |
| `WakeOnLANService` | Magic packet (6×FF + 16×MAC) inviato in UDP broadcast `255.255.255.255:9` via `NWConnection`. |
| `OUILookupService` | Dataset bundlato `Resources/oui-database.json` generato da `oui.txt` IEEE (~30k voci, formato compatto), lookup per prefisso OUI, cache in memoria. |
| `NetworkScannerCoordinator` (actor) | Orchestrazione ping sweep → ARP → Bonjour, con `AsyncStream` di progress verso la UI. |

## 4. Persistenza e sync

- **SwiftData**: `Device`, `ScanSession`, `CustomNetworkRange`, `DeviceMetadataOverride` (nome/icona custom, whitelist flag).
- Container con `cloudKitDatabase: .automatic`; entitlement CloudKit già presenti, identificatore container `iCloud.com.alain.IPScanner`.
- Sync CloudKit della lista dispositivi personalizzata.

## 5. Notifiche e background

- Notifiche locali (`UNUserNotificationCenter`) per nuovi dispositivi / cambio stato.
- iOS: `BGAppRefreshTask` (BackgroundTasks). Limiti di frequenza documentati in UI e README.
- macOS: timer libero (nessuna restrizione di background execution).

## 6. UI (SwiftUI)

- `NavigationSplitView` a 3 colonne: **sidebar (reti/range custom)** → **lista dispositivi** → **dettaglio dispositivo**. Su iPhone collassa in stack di navigazione.
- Lista: ordinamento per nome/IP/MAC/ultimo visto, colonne configurabili (es. MAC), dimensione riga regolabile, modalità cumulativa (storico, incl. device non più presenti), whitelist per evidenziare i nuovi, swipe actions (rinomina, apri, ping), empty state curato, progress di scansione con indicatori, transizioni leggere all'apparizione dei device.
- Strumenti: **Ping**, **Port Scan**, **Wake on LAN**; apertura in browser (`http://ip`), VNC (`vnc://ip`), altri URL scheme.
- Cronologia scansioni, Settings (preferenze, colonne, notifiche, range custom).
- Import/export CSV/JSON via `ShareLink` / `NSSharingServicePicker`; email via `MFMailComposeViewController` (iOS) / `NSSharingService.mail` (macOS); **P2P Bonjour** (`NWListener` + `NWBrowser` + `NWConnection`) per scambiare payload JSON tra due istanze.
- Design: palette semantica adattiva (Light/Dark), SF Symbols, Dynamic Type, target tocco ≥44pt, VoiceOver su ogni elemento interattivo.

## 7. Localizzazione

- **String Catalog** `Localizable.xcstrings`: inglese (base) + italiano.
- Nome app localizzato; stringhe di notifiche, errori e Info.plist localizzate.
- Formati di date, numeri e unità con `Locale.current`.

## 8. Test unitari

- Parsing OUI (`OUILookupService`).
- Costruzione magic packet WOL.
- Espansione range CIDR.
- `CrashReportingService` in assenza del plist (disabilitato, nessun crash).

## 9. Repo open source

- `LICENSE` MIT. `README.md` (inglese + nota in italiano): funzionalità, requisiti (iOS/iPadOS/macOS 26+), quick start senza configurazione Firebase, sezione "Crash reporting (optional)" (funziona senza plist, istruzioni per configurare il proprio progetto), setup secret Xcode Cloud (`GOOGLE_SERVICE_INFO_B64`), note sui limiti (simulatore, background best-effort, cache ARP).
- `.gitignore` standard Swift/Xcode + esclusione dei `GoogleService-Info.plist` reali.
- Push sul remote esistente `github.com/AlainL88/IPScanner`.
- Commit concisi, stile convenzionale, nessun riferimento ad AI/co-authoring.

## 10. Verifica finale

- Build `xcodebuild` per simulatore iOS e macOS, con e senza plist presente.
- Zero errori e zero warning.
- Test unitari verdi.
