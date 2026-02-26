# Technology Stack

**Analysis Date:** 2026-02-26

## Languages

**Primary:**
- Swift 5.0 - All application code, UI, and business logic in `GhostEdit/Sources/`
- Rust 2021 edition - On-device grammar checking via Harper bridge in `harper-bridge/`

**Secondary:**
- Objective-C - Carbon HIToolbox integration for system-wide hotkey handling (Carbon.HIToolbox)

## Runtime

**Environment:**
- macOS 13.0+ (deployment target)
- AppKit runtime (native macOS application, menu bar)

**Package Manager:**
- Swift Package Manager (SPM) - Indirect via Xcode
- Cargo 1.x - Rust dependency management for `harper-bridge`
- Xcode project file: `project.yml` (XcodeGen-generated from YAML source)

## Frameworks

**Core (macOS System Frameworks):**
- **AppKit** - Menu bar app, NSWindow, NSView, NSTableView, custom UI components
  - Location: `GhostEdit/Sources/AppDelegate.swift` and UI support modules
- **ApplicationServices** - Accessibility API for system text field interaction
  - Used in: `AccessibilityTextSupport.swift`, `AccessibilitySupport.swift`
- **Carbon.HIToolbox** - System hotkey registration and event handling
  - Used in: `HotkeyManager.swift`, `HotkeySupport.swift`
- **Foundation** - Core data structures, file I/O, process management
  - Used throughout all source files
- **CoreGraphics** - HUD overlay rendering and graphics
  - Used in: `HUDOverlaySupport.swift`, `LiveFeedbackSupport.swift`
- **UserNotifications** - User notification delivery
  - Used in: `AppDelegate.swift`
- **UniformTypeIdentifiers** - File type handling
  - Used in: `AppDelegate.swift`
- **ServiceManagement** - Launch at login functionality
  - Used in: `LaunchAtLoginManager.swift`
- **FoundationModels** (macOS 26+, optional) - On-device LLM inference
  - Conditional import in: `FoundationModelSupport.swift`

**Testing:**
- XCTest (built-in Xcode framework) - Unit tests
  - Test project: `GhostEditTests/`
  - Coverage enforcement via `scripts/run_tests_with_coverage.sh`

**Build/Dev:**
- XcodeGen - Generates Xcode project from `project.yml`
- Xcode 15+ (implied by Swift 5.0 and macOS 13.0 support)

## Key Dependencies

**Critical (Application Layer):**
- **harper-core** (Rust crate 0.26) - On-device grammar/spelling linting engine
  - Used in: `HarperBridge.swift` via C FFI
  - Provides: Real-time spell check, grammar suggestions
  - Build: Compiled to static lib (`harper-bridge/libharper_bridge.a`)

**Supporting Rust Crates (via harper-bridge):**
- **serde** 1.x - Serialization/deserialization
- **serde_json** 1.x - JSON parsing for Harper lint output

**Infrastructure:**
- No external HTTP/REST dependencies (no Alamofire, URLSession usage for APIs)
- External API calls via CLI tools (claude, codex, gemini command-line interfaces)

## Configuration

**Environment:**
- Home directory path discovery via `FileManager.default.homeDirectoryForCurrentUser`
- CLI provider resolution from `AppConfig` (Provider enum: claude, codex, gemini)
- Model selection per provider stored in JSON config

**Build:**
- Project manifest: `project.yml`
  - Generated Xcode project: `GhostEdit.xcodeproj`
  - Build settings: Swift 5.0, macOS 13.0 deployment
  - Link flags: `-lharper_bridge` for Rust integration
- Test coverage configuration: `scripts/run_tests_with_coverage.sh`
  - 100% line coverage enforced on 26 guarded files (see CONCERNS.md)

**Version Management:**
- Marketing version: `6.0.0` (in `project.yml`)
- Build number: `26` (incremented per release)
- Version stored in `project.pbxproj` (2 occurrences each for MARKETING_VERSION and CURRENT_PROJECT_VERSION)

## Platform Requirements

**Development:**
- Xcode 15+ (Swift 5.0 compatibility)
- macOS 13.0+ (for building and running)
- Rust toolchain (for harper-bridge compilation)
- Ruby (for XcodeGen: `gem install xcodegen`)

**Production:**
- macOS 13.0+ required
- No additional runtime dependencies (all dependencies linked at build time)
- Code-signed for gatekeeper compatibility
- Hardened runtime enabled (`ENABLE_HARDENED_RUNTIME: YES`)

## Project Structure

**Three-Target Architecture:**
- **GhostEditCore** - Framework (all source files except `main.swift`)
  - Bundle ID: `com.ghostedit.core`
  - 100% testable, no AppKit dependencies except UI support modules
- **GhostEdit** - Application (links GhostEditCore, includes `main.swift` + assets)
  - Bundle ID: `com.ghostedit.app`
  - Menu bar app (LSUIElement: true)
- **GhostEditTests** - Unit test bundle
  - Imports only GhostEditCore
  - 432+ tests enforcing 100% coverage on critical modules

## External Tool Integration

GhostEdit integrates with **CLI tools** for AI correction (not HTTP APIs):

- **Claude CLI** (`claude`) - Anthropic's command-line interface
  - Path configurable in settings or auto-discovered from `$PATH`
  - Authentication: `claude auth login` via terminal
- **Codex CLI** (`codex`) - OpenAI's Codex interface
  - Path configurable in settings
  - Authentication: `codex login`
- **Gemini CLI** (`gemini`) - Google's Gemini interface
  - Path configurable in settings
  - Authentication: via `gemini` command

Process communication via shell execution with streaming JSON output and timeout handling.

---

*Stack analysis: 2026-02-26*
