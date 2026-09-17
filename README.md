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
scripts/                     # Build and static verification helpers
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

`./init.sh` does not compile either application by default. Use `./init.sh --full` or `./scripts/check-app-build.sh` serially for isolated Debug compile evidence. Do not start the iOS and macOS script platforms as parallel processes, and do not point Xcode at `build/app-build-evidence/SourcePackages`. Keep launch, manual journeys, real-source checks, and real CloudKit validation (signed device or Mac plus iCloud account plus bound container) separate. See [`docs/RELIABILITY.md`](docs/RELIABILITY.md).

## iOS Visual Verification

iOS UI evidence is visual. The repository has no UI-test target.

```bash
# Physical device: install and launch, then capture screenshots and a recording
./run_device.sh

# Simulator: the agent launches and operates the app
./run_device.sh --simulator
xcrun simctl io booted screenshot /tmp/vanmo-simulator.png
xcrun simctl io booted recordVideo /tmp/vanmo-simulator.mp4
```

Physical-device journeys require a connected, trusted device and valid signing. After launch, capture screenshots and a screen recording of the exact walk. Simulator journeys are agent-operated; `simctl` launch or terminate alone does not prove a user journey. See [`docs/RELIABILITY.md`](docs/RELIABILITY.md).

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
