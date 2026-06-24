# PumpSync iOS

PumpSync is the iOS app that syncs Tandem Source insulin and carbohydrate data into Apple Health.

This repository is frontend-only. It owns the SwiftUI app, App Store/TestFlight metadata, screenshots, app legal docs, and iOS CI. Backend API code, infrastructure, backend workflows, data-deletion tooling, Docker images, and Azure operations live in [`eslutz/PumpSync-Backend`](https://github.com/eslutz/PumpSync-Backend).

The shared project wiki is the single source of truth for cross-repository documentation:

- [PumpSync wiki](https://github.com/eslutz/PumpSync/wiki)

## Repository Layout

- `PumpSync/`: SwiftUI app sources, resources, entitlements, and app configuration.
- `PumpSyncTests/`: unit tests.
- `PumpSyncUITests/`: UI tests and screenshot automation entry points.
- `project.yml`: XcodeGen source of truth for schemes, configurations, build settings, entitlements, and generated project files.
- `docs/app-store/`: App Store metadata, screenshots, accessibility notes, and review assets.
- `docs/legal/`: privacy, terms, data deletion request, and App Store privacy notes.
- `scripts/ios/`: iOS screenshot capture scripts.

## Documentation

Start with the [PumpSync wiki](https://github.com/eslutz/PumpSync/wiki) for setup, architecture, backend routing, hosted/self-hosted/demo behavior, testing, App Store readiness, and privacy.

This repository keeps app-owned source documents only:

- [`docs/README.md`](docs/README.md)
- [`docs/app-store/`](docs/app-store/)
- [`docs/legal/`](docs/legal/)
- [`AGENTS.md`](AGENTS.md)
