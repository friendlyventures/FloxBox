# FloxBox CI/CD (Beta on main + Stable tags + Sparkle on GitHub Pages)

## Goals
- Produce a **beta build for every commit on `main`** (latest-only Sparkle feed).
- Produce **stable builds for version tags** (e.g., `v0.1.0`) with a separate feed.
- Use the **same self-hosted runner** and **same secrets/env vars** as BentoBox.
- Host Sparkle appcasts on **GitHub Pages** (no external storage service).

## Non-goals
- Delta updates (can be added later via `generate_appcast`).
- Multiple channels beyond beta/stable.
- DMG/PKG distribution (Sparkle update uses ZIP only for now).

## Release Channels
- **Beta feed**: `https://<org>.github.io/<repo>/beta/appcast.xml`
- **Stable feed**: `https://<org>.github.io/<repo>/appcast.xml`

Each feed contains **one item only** (latest build). The beta feed updates on every main commit; the stable feed updates only on version tags.

## Versioning Policy
- **Beta:**
  - `CFBundleShortVersionString = <short SHA>` (matches BentoBox pattern)
  - `CFBundleVersion = git rev-list --count HEAD` (monotonic)
  - `SUFeedURL = .../beta/appcast.xml`
- **Stable:**
  - `CFBundleShortVersionString = <tag version>`
  - `CFBundleVersion = <run number or commit count>`
  - `SUFeedURL = .../appcast.xml`

## Build System (Shared Composite Action)
Create a reusable composite action modeled after BentoBox’s `.github/actions/build`, adapted for FloxBox:

**Inputs**
- `version` (short SHA or tag)
- `build_number`
- `short_commit_hash`
- Signing & notarization secrets (same as BentoBox)
- Sparkle public key (`SPARKLE_KEY_PUB`)

**Steps**
1. **Setup keychain** (import certs, store notarization profile).
2. **Build app** (Release config).
3. **Update Info.plist**:
   - `CFBundleVersion`, `CFBundleShortVersionString`
   - `SUPublicEDKey` (Sparkle public key)
   - `SUFeedURL` (beta or stable)
4. **Codesign**:
   - Sign Sparkle framework + XPCs first.
   - Sign the main app bundle.
5. **Notarize** (zip the app, submit with notarytool, staple).
6. **Create Sparkle ZIP** (e.g., `floxbox-macos-universal.zip`).

Outputs: Sparkle ZIP + app bundle ready for signing and appcast.

## Workflows

### 1) Beta on main (every commit)
**Trigger:** `push` to `main`

**Jobs:**
- **build-beta** (self-hosted)
  - Checkout full history
  - Compute build number + short SHA
  - Call build action with `version=<short SHA>`
  - Run Sparkle `sign_update` against the ZIP
  - Generate `_site/beta/appcast.xml` with a single `<item>`
  - Copy ZIP to `_site/beta/`
  - Upload Pages artifact
- **deploy-pages** (self-hosted)
  - Deploy artifact via `actions/deploy-pages`

### 2) Stable on tag
**Trigger:** `push` tags `v*`

**Jobs:**
- **build-stable** (self-hosted)
  - Checkout, resolve version from tag
  - Call build action with `version=<tag>`
  - Generate `_site/appcast.xml` (single item)
  - Copy ZIP to `_site/`
  - Upload Pages artifact
- **deploy-pages** (self-hosted)
  - Deploy artifact via `actions/deploy-pages`

## Sparkle Appcast Generation
- Use Sparkle’s `sign_update` tool (downloaded in CI, pinned to current release) to produce:
  - `sparkle:edSignature`
  - `length`
- Appcast includes one `<item>` per feed (latest-only).
- Appcast and ZIP are hosted via GitHub Pages.

## Required Secrets (same as BentoBox)
- `BUILD_CERTIFICATE_BASE64`
- `INSTALLER_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `CERTIFICATE_NAME`
- `INSTALLER_CERTIFICATE_NAME`
- `NOTARIZATION_APPLE_ID`
- `NOTARIZATION_TEAM_ID`
- `NOTARIZATION_PASS`
- `SPARKLE_KEY_PUB` (public)
- `SPARKLE_KEY` or `SPARKLE_EDDSA_PRIVATE_KEY` (private signing key)

## Runner
- Use **the same self-hosted runner** label as BentoBox (`runs-on: self-hosted`).

## Validation Checklist
- Beta appcast live at `/beta/appcast.xml`
- Stable appcast live at `/appcast.xml`
- `SUFeedURL` in built app points to correct feed
- Sparkle update test succeeds on a beta build
- Beta deploy preserves stable feed/ZIP on Pages (and vice versa)
