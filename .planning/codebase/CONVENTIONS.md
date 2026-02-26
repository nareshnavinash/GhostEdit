# Coding Conventions

**Analysis Date:** 2026-02-26

## Naming Patterns

**Files:**
- Support modules: `[Name]Support.swift` (e.g., `TokenPreservationSupport.swift`, `DiffSupport.swift`)
- Managers: `[Name]Manager.swift` (e.g., `ConfigManager.swift`)
- Controllers: `[Name]Controller.swift` (e.g., `SettingsWindowController.swift`)
- Core classes: Direct names like `ShellRunner.swift`, `CorrectionHistoryStore.swift`
- Protocol implementations: Match protocol name (e.g., `PersistentCLISession.swift` implements `PersistentCLISessionProtocol`)
- Main entry point: `main.swift` and `AppDelegate.swift`

**Functions:**
- camelCase: `correctText()`, `protectTokens()`, `loadConfig()`
- Boolean checks: start with `is` or `has`: `hasProtectedTokens`, `isIdentical()`
- Verbs for actions: `load`, `save`, `resolve`, `normalize`, `restore`, `append`
- Private helpers end with `Locked` or `Sync`: `readLocked()`, `spawnPersistentSessionSync()`

**Variables:**
- camelCase: `protectedText`, `selectedText`, `originalToken`, `baseDirectoryURL`
- File paths: Include `URL` or `Path` suffix: `baseDirectoryURL`, `promptURL`, `configURL`
- Computed properties: use `resolved` prefix for normalized/processed values: `resolvedProvider`, `resolvedClaudePath`, `resolvedModel()`
- Temporary collections: `tempRoots`, `tempURLs` (for cleanup in tests)

**Types:**
- PascalCase for structs, enums, classes: `AppConfig`, `CorrectionHistoryEntry`, `DiffSegment`
- Error enums: `[Domain]Error` (e.g., `ShellRunnerError`, `FoundationModelError`)
- Enum cases: lowercased unless special (e.g., `.success`, `.error(String)`, `.successWithCount(Int)`)
- Protocol names: `[Name]Protocol` for test doubles (e.g., `PersistentCLISessionProtocol`)

## Code Style

**Formatting:**
- No auto-formatter configured (Xcode defaults)
- 4-space indentation (Xcode default)
- Line length: no hard limit enforced, but keep under 120 chars for readability

**Linting:**
- No SwiftLint or similar tool configured
- Code follows Apple Swift conventions
- Access control is explicit (`private`, `final`, etc.)

## Import Organization

**Order:**
1. Foundation (system frameworks)
2. Other Cocoa frameworks (AppKit, etc.)
3. No third-party dependencies in GhostEditCore
4. Test imports: `@testable import GhostEditCore`

**Path Aliases:**
- None detected. Relative imports from within GhostEditCore framework

**Module structure:**
- GhostEditCore is a framework target containing all logic
- GhostEdit app target only contains `main.swift` + assets
- Tests import GhostEditCore via `@testable`

## Error Handling

**Patterns:**
- Custom error enums conforming to `LocalizedError` with computed `errorDescription`
  ```swift
  enum ShellRunnerError: LocalizedError {
      case cliNotFound(provider: CLIProvider)
      case timedOut(seconds: Int)

      var errorDescription: String? {
          switch self {
          case let .cliNotFound(provider):
              return "The \(provider.executableName) CLI could not be found."
          // ...
          }
      }
  }
  ```

- `throws` methods return descriptive errors via enum cases
- Error handling in callers: `try?` for optional results, `try` for propagation
- Guard statements with early return: `guard condition else { return nil/[] }`

## Logging

**Framework:** console + developer mode
- `devLog(.category, "message")` for debug logging (see `DeveloperModeSupport`)
- Categories: `.cliResolution`, `.streaming`, etc.
- No third-party logging framework

**Patterns:**
- Log at decision points: CLI resolution, session spawn/kill
- Include context: provider name, model, file paths
- Dev mode only—no logging in release builds

## Comments

**When to Comment:**
- MARK sections for large files to organize functionality: `// MARK: - [Section Name]`
- Algorithm explanations: see `DiffSupport.swift` Myers diff implementation
- Non-obvious business logic or workarounds
- Avoid restating what code obviously does

**Style:**
- MARK format: `// MARK: - [Section]` (with dash)
- Inline comments rare; prefer clear naming
- No block documentation (///) used in this codebase
- Private function documentation minimal

**Example from codebase:**
```swift
// MARK: - Myers diff (simple O(ND) algorithm)
// V[k] stores the furthest-reaching x-coordinate on diagonal k.
// Diagonals range from -maxD to +maxD, so we offset by maxD.
```

## Function Design

**Size:**
- Most functions: 10-40 lines
- Complex algorithms split into private helpers
- Large controllers broken into `// MARK:` sections within class

**Parameters:**
- Max 4-5 parameters; use struct wrapper if more needed
- Prefer named parameters over positional
- Use trailing closures for callbacks

**Return Values:**
- Explicit types, no implicit returns (except single-expression closures)
- `throws` for error cases, not `Result` wrappers
- Void return with side effects acceptable for handlers/callbacks

**Example:**
```swift
func correctText(
    systemPrompt: String,
    selectedText: String
) throws -> String
```

## Module Design

**Exports:**
- Support enums are namespaces with `static` methods only
  ```swift
  enum TokenPreservationSupport {
      static func protectTokens(in text: String) -> TokenProtectionResult
  }
  ```

- Managers are `final class` with dependency injection
  ```swift
  final class ConfigManager {
      private let fileManager: FileManager
      init(fileManager: FileManager = .default, homeDirectoryURL: URL? = nil)
  }
  ```

- Structures for data (`AppConfig`, `CorrectionHistoryEntry`) conform to `Codable, Equatable`

**Barrel Files:**
- No barrel files (index files). Each source file stands alone
- Import specific types directly: `@testable import GhostEditCore`

## Testing Code Structure

**Test class naming:** `[SourceClass]Tests` (e.g., `ConfigManagerTests`, `TokenPreservationSupportTests`)

**Setup/Teardown:**
```swift
override func tearDownWithError() throws {
    // Cleanup resources
    try super.tearDownWithError()
}
```

**Helper methods:**
- Prefix with `make`: `makeManager()`, `makeRunnerEnvironment()`, `makeExecutableScript()`
- Return tuple if multiple values: `(ConfigManager, URL)`
- Store temporary resources: `tempRoots`, `tempURLs` arrays for cleanup

## Access Control

**Pattern:**
- `final` on classes to prevent subclassing
- `private` for implementation details
- `private(set)` for properties modified only internally but read externally (rare)
- No `public` or `open` in GhostEditCore (all internal to framework)

**Example:**
```swift
final class ConfigManager {
    private let fileManager: FileManager
    private var cachedConfig: AppConfig?

    let baseDirectoryURL: URL
    let promptURL: URL
}
```

## Closure and Functional Patterns

**Higher-order functions:**
- `mapError` for error transformation
- `guard let` chains for optional unwrapping in sequences
- Trailing closure syntax for single closure parameter

**Example:**
```swift
func prewarm() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
        guard let self else { return }
        // work
    }
}
```

**Weak self capture:** Always used in closures to prevent cycles; explicit guard check required

## Configuration and Constants

**Stored where used:**
- `AppConfig` struct for persistent settings
- Static properties on enums: `CLIProvider.default`, `AppConfig.default`
- Hardcoded paths use `URL` builders: `.appendingPathComponent("name", isDirectory: true)`

**Example:**
```swift
enum CLIProvider: String, Codable, CaseIterable {
    case claude
    case codex
    case gemini

    static let `default`: CLIProvider = .claude
}
```

---

*Convention analysis: 2026-02-26*
