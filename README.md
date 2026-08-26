# Vanmo

Vanmo is a native video player repository with:

- an iOS 17+ application (`Vanmo`)
- a native macOS 14+ application (`Vanmo-macOS`)
- a shared local Swift package (`VanmoCore`)

The applications use SwiftUI, SwiftData, Swift Concurrency, Combine, AVFoundation, and KSPlayer. Platform navigation, presentation, and player adapters remain separate; shared models and infrastructure live in `VanmoCore`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the implemented system map, supported and incomplete integration paths, persistence boundaries, and current risks.

## Repository Layout

```text
Vanmo/                       # iOS application UI and platform behavior
VanmoMac/                    # macOS application UI, AppKit integration, and windows
Packages/VanmoCore/          # Shared models and infrastructure
VanmoUITests/                # iOS device interaction XCUITest target
scripts/                     # Build and static verification helpers
scripts/ios-ui.sh            # iOS XCUITest CLI for device and Simulator; simctl manages Simulator lifecycle
docs/                        # Durable product, design, plan, quality, and operating knowledge
project.yml                  # XcodeGen source of truth
Vanmo.xcodeproj/             # Generated and committed Xcode project
init.sh                      # Shared dependency and baseline verification entry point
run_device.sh                # iOS device, simulator, and macOS build/run entry point
build_ipa.sh                 # iOS Release archive and export entry point
```

Do not create a replacement Xcode project or import source files manually. Target definitions, dependencies, resources, build settings, and entitlements are maintained in `project.yml`; regenerate the committed project with XcodeGen after changing that file.

## Getting Started

Requirements:

- a compatible Xcode installation
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Python 3 for the Harness documentation check included in `./init.sh`
- an Apple development team when signing or device execution requires one

Resolve shared dependencies and run the repository baseline:

```bash
./init.sh
```

Build or run the relevant application:

```bash
./run_device.sh              # iOS device
./run_device.sh --simulator  # iOS Simulator
./run_device.sh --macos      # native macOS app
```

`./init.sh` does not compile either application by default. Use `./init.sh --full` or `./scripts/check-app-build.sh` for Debug compile evidence, and keep launch, manual journeys, real-source checks, and Release CloudKit validation separate. See [`docs/RELIABILITY.md`](docs/RELIABILITY.md).

## Device UI Interaction

Use the repository CLI for bounded iOS interaction and evidence capture:

```bash
# Simulator XCUITest: screenshot, tree, interaction, and the tab-navigation journey
./scripts/ios-ui.sh simulator tree --output /tmp/vanmo-tree.json
./scripts/ios-ui.sh simulator assert --identifier screen.library --state exists
./scripts/ios-ui.sh simulator journey --name tab-navigation

# Physical device: the same XCUITest commands, plus signing
./scripts/ios-ui.sh device screenshot --device "My iPhone" --output /tmp/vanmo.png
./scripts/ios-ui.sh device tap --identifier tab.settings --timeout 5

# Simulator management only
./scripts/ios-ui.sh simulator launch --device "iPhone 17 Pro"
```

Device and Simulator screenshot, tree, tap, type, swipe, wait, assert, and journey commands use XCUITest. Replace selector placeholders with identifiers or exact labels from the current tree output. Physical-device commands require a connected, trusted device and valid signing; supply the Apple development team with `VANMO_DEVELOPMENT_TEAM` or `--team TEAM`. Each XCUITest run retains its result bundle, logs, and exported attachments under `build/ui-cli/runs/`. `simulator launch|terminate` still use `simctl` only to manage the Simulator and do not validate UI.

## Architecture and Capability Status

Vanmo uses MVVM/Store-style observable state and platform-specific application layers rather than a strict Clean Architecture implementation. AVFoundation handles native playback paths, while KSPlayer provides the current FFmpeg-backed paths. The exact engine selection, protocol capability, download, metadata, subtitle, persistence, and cloud-sync behavior is documented in [`ARCHITECTURE.md`](ARCHITECTURE.md).

Visible connection types are not all production-ready. Do not infer support from an enum case or menu entry; use the current implementation and architecture document as the authority.

## Documentation

- [`AGENTS.md`](AGENTS.md): concise repository operating guide and routing map
- [`ARCHITECTURE.md`](ARCHITECTURE.md): implemented boundaries, runtime data flows, and known risks
- [`docs/DESIGN.md`](docs/DESIGN.md): durable design decisions
- [`docs/PLANS.md`](docs/PLANS.md): execution-plan policy and active/completed plan routing
- [`docs/product-specs/index.md`](docs/product-specs/index.md): user-visible specifications and acceptance status
- [`docs/QUALITY_SCORE.md`](docs/QUALITY_SCORE.md): evidence-based quality snapshot
- [`docs/RELIABILITY.md`](docs/RELIABILITY.md): verification, recovery, and debugging
- [`docs/SECURITY.md`](docs/SECURITY.md): credential, data, dependency, and external-action rules
- [`docs/FRONTEND.md`](docs/FRONTEND.md): Figma, platform UI, accessibility, and visual-validation rules

## License

See [`LICENSE`](LICENSE).
