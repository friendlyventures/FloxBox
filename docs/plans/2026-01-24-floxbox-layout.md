# FloxBox AppStore/Direct Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure FloxBox to mirror PortalBox layout: Xcode project with direct + App Store app targets backed by a local Swift package, plus tooling to build both variants.

**Architecture:** Keep app targets thin (entrypoint + assets). Move UI and shared logic to `Packages/FloxBoxCore` and provide a direct-only companion target `FloxBoxCoreDirect`. App Store target links only `FloxBoxCore` and compiles with `APP_STORE`; direct target links both products and compiles with `DIRECT_DISTRIBUTION`. Entitlements live under `FloxBox/` with App Store sandbox enabled.

**Tech Stack:** SwiftUI, Swift Package Manager, Xcode project, mise, swiftlint, swiftformat.

Note: User requested no worktrees; execute on `main`.

### Task 1: Scaffold `FloxBoxCore` package with distribution config

**Files:**
- Create: `Packages/FloxBoxCore/Package.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Distribution/FloxBoxDistributionConfiguration.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class FloxBoxDistributionTests: XCTestCase {
    func testAppStoreLabel() {
        XCTAssertEqual(FloxBoxDistributionConfiguration.appStore.label, "App Store")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: FAIL with "No such module 'FloxBoxCore'" or missing type errors.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FloxBoxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloxBoxCore", targets: ["FloxBoxCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FloxBoxCore",
            path: "Sources/FloxBoxCore"
        ),
        .testTarget(
            name: "FloxBoxCoreTests",
            dependencies: ["FloxBoxCore"],
            path: "Tests/FloxBoxCoreTests"
        ),
    ]
)
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Distribution/FloxBoxDistributionConfiguration.swift`:

```swift
public struct FloxBoxDistributionConfiguration: Equatable {
    public let label: String

    public init(label: String) {
        self.label = label
    }

    public static let appStore = Self(label: "App Store")
    public static let direct = Self(label: "Direct")
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore
git commit -m "feat: scaffold FloxBoxCore package"
```

### Task 2: Add `FloxBoxCoreDirect` product with direct-only helper

**Files:**
- Modify: `Packages/FloxBoxCore/Package.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCoreDirect/FloxBoxDirectServices.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreDirectTests/FloxBoxCoreDirectTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCoreDirect

final class FloxBoxCoreDirectTests: XCTestCase {
    func testDirectConfigLabel() {
        XCTAssertEqual(FloxBoxDirectServices.configuration().label, "Direct")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: FAIL with "No such module 'FloxBoxCoreDirect'" or missing type errors.

**Step 3: Write minimal implementation**

Update `Packages/FloxBoxCore/Package.swift` products/targets:

```swift
products: [
    .library(name: "FloxBoxCore", targets: ["FloxBoxCore"]),
    .library(name: "FloxBoxCoreDirect", targets: ["FloxBoxCoreDirect"]),
],
// ...
targets: [
    .target(
        name: "FloxBoxCore",
        path: "Sources/FloxBoxCore"
    ),
    .target(
        name: "FloxBoxCoreDirect",
        dependencies: ["FloxBoxCore"],
        path: "Sources/FloxBoxCoreDirect",
        swiftSettings: [
            .define("DIRECT_DISTRIBUTION"),
        ]
    ),
    .testTarget(
        name: "FloxBoxCoreTests",
        dependencies: ["FloxBoxCore"],
        path: "Tests/FloxBoxCoreTests"
    ),
    .testTarget(
        name: "FloxBoxCoreDirectTests",
        dependencies: ["FloxBoxCoreDirect"],
        path: "Tests/FloxBoxCoreDirectTests"
    ),
]
```

`Packages/FloxBoxCore/Sources/FloxBoxCoreDirect/FloxBoxDirectServices.swift`:

```swift
import FloxBoxCore

public enum FloxBoxDirectServices {
    public static func configuration() -> FloxBoxDistributionConfiguration {
        .direct
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore
git commit -m "feat: add FloxBoxCoreDirect product"
```

### Task 3: Move app UI into package and add app root

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppRoot.swift`
- Delete: `FloxBox/ContentView.swift` (also remove from Xcode target)

**Step 1: Write the failing test**

Add to `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift`:

```swift
func testAppRootCompiles() {
    _ = FloxBoxAppRoot.makeScene(configuration: .appStore)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: FAIL with "Cannot find 'FloxBoxAppRoot' in scope".

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`:

```swift
import SwiftUI

public struct ContentView: View {
    private let configuration: FloxBoxDistributionConfiguration

    public init(configuration: FloxBoxDistributionConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text(configuration.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppRoot.swift`:

```swift
import SwiftUI

public enum FloxBoxAppRoot {
    public static func makeScene(
        configuration: FloxBoxDistributionConfiguration
    ) -> some Scene {
        WindowGroup {
            ContentView(configuration: configuration)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore FloxBox/ContentView.swift
git commit -m "feat: move app UI into FloxBoxCore"
```

### Task 4: Update app entrypoint to use package + distribution modes

**Files:**
- Modify: `FloxBox/FloxBoxApp.swift`

**Step 1: Write the failing test**

Run: `xcodebuild -project FloxBox.xcodeproj -scheme FloxBox -configuration Debug build`
Expected: FAIL because `FloxBoxCore` module is not linked yet (or after change).

**Step 2: Write minimal implementation**

`FloxBox/FloxBoxApp.swift`:

```swift
import SwiftUI
import FloxBoxCore
#if !APP_STORE
import FloxBoxCoreDirect
#endif

@main
struct FloxBoxApp: App {
    private let configuration: FloxBoxDistributionConfiguration

    init() {
        #if APP_STORE
        configuration = .appStore
        #else
        configuration = FloxBoxDirectServices.configuration()
        #endif
    }

    var body: some Scene {
        FloxBoxAppRoot.makeScene(configuration: configuration)
    }
}
```

**Step 3: Run test to verify it fails (until Task 5 completes)**

Run: `xcodebuild -project FloxBox.xcodeproj -scheme FloxBox -configuration Debug build`
Expected: FAIL with "No such module 'FloxBoxCore'" (expected until package wiring in Task 5).

**Step 4: Commit**

```bash
git add FloxBox/FloxBoxApp.swift
git commit -m "feat: route app entrypoint through FloxBoxCore"
```

### Task 5: Add entitlements + wire Xcode project with App Store target

**Files:**
- Create: `FloxBox/FloxBox.entitlements`
- Create: `FloxBox/FloxBoxAppStore.entitlements`
- Modify: `FloxBox.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

Run: `xcodebuild -project FloxBox.xcodeproj -scheme FloxBox-AppStore -configuration Debug build`
Expected: FAIL with "scheme not found".

**Step 2: Write minimal implementation**

1) Entitlements:

`FloxBox/FloxBox.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

`FloxBox/FloxBoxAppStore.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

2) Xcode project wiring (mirror `PortalBox.xcodeproj` structure):
- Add `Packages/FloxBoxCore` as `XCLocalSwiftPackageReference` with `relativePath = Packages/FloxBoxCore;`
- Add `XCSwiftPackageProductDependency` for `FloxBoxCore` and `FloxBoxCoreDirect`
- Add file reference group `Packages/FloxBoxCore` under main group
- Existing target `FloxBox` (direct):
  - Link `FloxBoxCore` and `FloxBoxCoreDirect` in Frameworks build phase
  - Set `SWIFT_ACTIVE_COMPILATION_CONDITIONS`:
    - Debug: `DEBUG DIRECT_DISTRIBUTION $(inherited)`
    - Release: `DIRECT_DISTRIBUTION $(inherited)`
  - Set `CODE_SIGN_ENTITLEMENTS = FloxBox/FloxBox.entitlements`
  - Set `INFOPLIST_KEY_CFBundleDisplayName = "FloxBox Debug"` for Debug and `"FloxBox"` for Release (optional parity with PortalBox)
  - Set `PRODUCT_BUNDLE_IDENTIFIER`:
    - Debug: `org.friendlyventures.FloxBoxDebug`
    - Release: `org.friendlyventures.FloxBox`
- New target `FloxBox-AppStore`:
  - Duplicate the `FloxBox` target structure (sources/resources phases, build configs)
  - Link only `FloxBoxCore` (omit `FloxBoxCoreDirect`)
  - Set `PRODUCT_NAME = FloxBox` so the bundle is `FloxBox.app`
  - Set `SWIFT_ACTIVE_COMPILATION_CONDITIONS`:
    - Debug: `DEBUG APP_STORE $(inherited)`
    - Release: `APP_STORE $(inherited)`
  - Set `CODE_SIGN_ENTITLEMENTS = FloxBox/FloxBoxAppStore.entitlements`
  - Use same bundle identifiers as direct target (Debug/Release) for parity

**Step 3: Run test to verify it passes**

Run:
- `xcodebuild -project FloxBox.xcodeproj -scheme FloxBox -configuration Debug build`
- `xcodebuild -project FloxBox.xcodeproj -scheme FloxBox-AppStore -configuration Debug build`
Expected: both PASS.

**Step 4: Commit**

```bash
git add FloxBox/FloxBox.entitlements FloxBox/FloxBoxAppStore.entitlements FloxBox.xcodeproj/project.pbxproj
git commit -m "feat: add App Store target and package wiring"
```

### Task 6: Add mise tasks and tool configs for build parity

**Files:**
- Create: `.mise.toml`
- Create: `.swift-version`
- Create: `.swiftformat`
- Create: `.swiftlint.yml`

**Step 1: Write the failing test**

Run: `mise build`
Expected: FAIL because `.mise.toml` does not exist.

**Step 2: Write minimal implementation**

Copy config baselines from PortalBox:

```bash
cp /Users/shayne/code/PortalBox/.swift-version /Users/shayne/code/FloxBox/.swift-version
cp /Users/shayne/code/PortalBox/.swiftformat /Users/shayne/code/FloxBox/.swiftformat
cp /Users/shayne/code/PortalBox/.swiftlint.yml /Users/shayne/code/FloxBox/.swiftlint.yml
```

Create `.mise.toml` (PortalBox-based, names updated):

```toml
[tools]
pre-commit = "latest"
swiftformat = "latest"
swiftlint = "latest"

[tasks.build]
description = "Default build (Direct distribution) for local dev and CI parity"
run = [
  "xcodebuild -project FloxBox.xcodeproj -scheme FloxBox -configuration Debug build"
]

[tasks.build-appstore]
description = "Build the App Store variant (manual submissions only)"
run = [
  "xcodebuild -project FloxBox.xcodeproj -scheme FloxBox-AppStore -configuration Debug build"
]

[tasks.format]
description = "Run after Swift edits to keep formatting consistent"
run = [
  "swiftformat ."
]

[tasks.lint]
description = "Run SwiftLint rules"
run = [
  "swiftlint --fix",
  "swiftlint --strict"
]

[tasks.check]
description = "Format then lint"
run = [
  "mise format",
  "mise lint"
]

[tasks.install-githooks]
description = "Install git hooks via pre-commit"
run = '''
#!/usr/bin/env bash
set -euo pipefail

git config --local --unset-all core.hooksPath || true

pre-commit install -f --install-hooks \
  --hook-type pre-commit \
  --hook-type prepare-commit-msg
'''
```

**Step 3: Run test to verify it passes**

Run:
- `mise build`
- `mise build-appstore`
Expected: both PASS.

**Step 4: Commit**

```bash
git add .mise.toml .swift-version .swiftformat .swiftlint.yml
git commit -m "chore: add mise build tasks and lint config"
```
