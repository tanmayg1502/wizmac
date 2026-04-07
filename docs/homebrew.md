# Wizmac Homebrew Packaging

Wizmac now has two Homebrew entry points:

- a Homebrew cask for the packaged `Wizmac.app` at [Casks/wizmac.rb](../Casks/wizmac.rb)
- a source-built formula for CLI and service users at [Formula/wizmac.rb](../Formula/wizmac.rb)

The app bundle packaging helper lives at [scripts/build_wizmac_app.sh](../scripts/build_wizmac_app.sh). It turns SwiftPM release outputs into a signed `Wizmac.app` bundle, embeds both `WizmacService` and the `wizmac` CLI, and by default creates a `Wizmac.zip` archive for cask distribution.

## Recommended End-User Install

Ship Wizmac primarily as a cask:

```bash
brew tap <owner>/<tap>
brew install --cask wizmac
open /Applications/Wizmac.app
```

The cask installs:

- `Wizmac.app` into `/Applications`
- a `wizmac` symlink into `$(brew --prefix)/bin`
- the bundled `WizmacService` next to the menu bar app executable so the app can keep the shared service alive

On first launch, the app is responsible for permission prompts, launch-at-login registration, and keeping the shared local MCP service on `http://127.0.0.1:7877/mcp` available.

## Formula For CLI And Service Users

The formula remains available for power users who want a source-built CLI plus `brew services` support:

```bash
brew tap <owner>/<tap>
brew install wizmac
brew services start wizmac
```

## Tap Install

When the formula and cask are published from a tap repository, the install flow should look like the usual Homebrew pattern:

```bash
brew tap <owner>/<tap>
brew install wizmac
brew install --cask wizmac
```

Use the cask for end users. Use the formula when you want `brew services start wizmac` for a source-built service install.

## App Bundle Packaging

Build the local app bundle and ZIP archive:

```bash
scripts/build_wizmac_app.sh --version 0.1.0
```

By default, the script writes into `.build/package/`:

- `.build/package/Wizmac.app`
- `.build/package/Wizmac.zip`
- `.build/package/Wizmac.app/Contents/Resources/bin/wizmac`

The script ad-hoc signs the assembled bundle by default so Gatekeeper-style checks work locally. For release builds, pass a Developer ID identity:

```bash
scripts/build_wizmac_app.sh --version 0.1.0 --codesign-identity "Developer ID Application: Your Name (TEAMID)"
```

Use `--no-zip` when you only want the local app bundle.

## Release Flow

The intended release flow is:

1. Build the app bundle and ZIP with `scripts/build_wizmac_app.sh --version <release-version> --codesign-identity "<Developer ID>"`.
2. Notarize the resulting `Wizmac.app` or `Wizmac.zip`.
3. Publish `Wizmac.zip` as the GitHub release asset that `Casks/wizmac.rb` points at.
4. Keep `Formula/wizmac.rb` for power users who prefer a source build and `brew services`.

Tagged releases must be signed and notarized. If they are not, macOS may show a dialog saying it could not verify Wizmac and offer only `Move to Trash`.

This repo also includes [.github/workflows/release-homebrew.yml](../.github/workflows/release-homebrew.yml), which automates the same flow on tag pushes when the signing and notarization secrets are configured.

## Validation

For a local packaging check, run:

```bash
swift build
swift test --filter WizmacControlPlaneTests
swift test --filter WizmacAppTests
scripts/build_wizmac_app.sh --no-zip
```

Homebrew install validation should happen from the published tap and release asset, not from a repo-local `brew install ./Formula/wizmac.rb` flow.
