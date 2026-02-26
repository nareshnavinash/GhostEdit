# Testing Patterns

**Analysis Date:** 2026-02-26

## Test Framework

**Runner:**
- XCTest (Apple's native framework)
- Xcode scheme: `GhostEditTests`
- Runs via `xcodebuild test` or `xcrun xctest`

**Assertion Library:**
- XCTest assertions: `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`, `XCTAssertThrows`, etc.
- No custom assertion helpers

**Run Commands:**
```bash
# Run all tests
xcodebuild test -project GhostEdit.xcodeproj -scheme GhostEditTests -destination 'platform=macOS'

# Watch/iterative mode (not native, use Xcode UI)
# Press Cmd+U in Xcode

# Coverage report (enforced by pre-commit hook)
./scripts/run_tests_with_coverage.sh
```

## Test File Organization

**Location:**
- Tests co-located in `GhostEditTests/` directory
- Mirror source file names: `ConfigManager.swift` → `ConfigManagerTests.swift`
- All tests in single bundle target

**Naming:**
- Class: `[SourceClass]Tests` (final class, extends XCTestCase)
- Method: `test[Scenario]` (e.g., `testBootstrapCreatesDefaultFiles()`)
- Scenario describes precondition + expected result

**Structure:**
```
GhostEditTests/
├── ConfigManagerTests.swift
├── TokenPreservationSupportTests.swift
├── ShellRunnerTests.swift
├── DiffSupportTests.swift
└── [Other]Tests.swift
```

## Test Structure

**Suite Organization:**

All tests inherit from `XCTestCase` and use `// MARK:` sections:

```swift
final class ConfigManagerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for root in tempRoots {
            try? fileManager.removeItem(at: root)
        }
        tempRoots.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Bootstrap
    func testBootstrapCreatesDefaultFiles() throws { }

    // MARK: - Load/Save
    func testLoadConfigReturnsCachedValue() throws { }

    // MARK: - Helpers
    private func makeManager() -> (ConfigManager, URL) { }
}
```

**Patterns:**
- **Setup:** None in `setUp()`. Instead, create test-specific state in each test or factory method
- **Teardown:** `override func tearDownWithError()` to clean temporary files/resources
- **Assertion:** One logical assertion per test (may have multiple `XCTAssert` calls for same concept)

## Mocking

**Framework:**
- Manual mocks: Create test-specific implementations conforming to protocols
- Example: `PersistentCLISessionProtocol` with mock in test setup
- No mock generation libraries (Mockito-style)

**Patterns:**

Inject dependencies at init:
```swift
let runner = ShellRunner(
    configManager: testEnv.manager,
    fileManager: fileManager,
    environment: injectedEnv,
    homeDirectoryPath: testEnv.homeURL.path
)
```

Provide test-only setters for internal dependencies:
```swift
runner.setPersistentSessionForTesting(mockSession)
runner.setSessionFactoryForTesting({ mockSession })
```

**What to Mock:**
- File system operations (use temp directory)
- Network/CLI calls (use mock executables or echo scripts)
- Time-dependent behavior (not needed in this codebase)

**What NOT to Mock:**
- Core logic (DiffSupport, TokenPreservationSupport)
- Data structures (AppConfig, CorrectionHistoryEntry)
- Configuration loading (use temp config files instead)

## Fixtures and Factories

**Test Data:**

Temporary directories and files created per test:

```swift
private func makeManager() -> (ConfigManager, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ghostedit-tests-\(UUID().uuidString)", isDirectory: true)
    tempRoots.append(root)
    let manager = ConfigManager(fileManager: .default, homeDirectoryURL: root)
    return (manager, root)
}
```

Executable scripts for CLI testing:
```swift
private func makeExecutableScript(
    named: String,
    contents: String,
    homeURL: URL
) throws -> URL {
    let scriptURL = homeURL.appendingPathComponent(named)
    try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: scriptURL.path
    )
    return scriptURL
}
```

**Location:**
- Fixture helpers are private methods in test class
- No separate fixture files/factories
- Data created inline per test need

## Coverage

**Requirements:**
- **100% line coverage enforced** on 26 guarded files (see below)
- Pre-commit and pre-push hooks run `scripts/run_tests_with_coverage.sh`
- Coverage gate fails build if any guarded file < 100%

**Guarded Files (100% coverage required):**
- `ConfigManager.swift`
- `ShellRunner.swift`
- `ClaudeRuntimeSupport.swift`
- `CorrectionHistoryStore.swift`
- `HistoryTableModel.swift`
- `HistoryCSVExporter.swift`
- `HotkeySupport.swift`
- `WritingCoachSupport.swift`
- `AccessibilitySupport.swift`
- `AccessibilityTextSupport.swift`
- `SettingsLayoutSupport.swift`
- `TokenPreservationSupport.swift`
- `MenuBarIconSupport.swift`
- `WritingCoachLayoutSupport.swift`
- `HUDOverlaySupport.swift`
- `DeveloperModeSupport.swift`
- `DiffSupport.swift`
- `SettingsExportSupport.swift`
- `CorrectionStatisticsSupport.swift`
- `TooltipSupport.swift`
- `FallbackSupport.swift`
- `TokenEstimationSupport.swift`
- `PartialCorrectionSupport.swift`
- `AppProfileSupport.swift`
- `UpdateCheckSupport.swift`
- `StreamingPreviewSupport.swift`
- `SpellCheckSupport.swift`
- `LiveFeedbackSupport.swift`

**NOT guarded** (no coverage requirement):
- `AppDelegate.swift` (UI, hard to test)
- `ClipboardManager.swift` (system integration)
- `HotkeyManager.swift` (system integration)
- `LaunchAtLoginManager.swift` (system integration)
- `PersistentCLISession.swift` (process management)
- `PersistentShellSession.swift`
- `main.swift` (entry point)

**View Coverage:**
```bash
# Run the coverage script
./scripts/run_tests_with_coverage.sh

# Output: Per-file coverage percentage
# Example:
# ConfigManager.swift: 100.00%
# TokenPreservationSupport.swift: 100.00%
```

**Script location:** `/scripts/run_tests_with_coverage.sh`

## Test Types

**Unit Tests:**
- **Scope:** Individual functions/methods in isolation
- **Approach:** Direct call with test data, assert output
- **Example:** `DiffSupport.wordDiff()`, `TokenPreservationSupport.protectTokens()`
- **Coverage:** 95%+ of test count

**Integration Tests:**
- **Scope:** Multiple modules working together
- **Approach:** Create ConfigManager + ShellRunner, exercise full correction flow
- **Example:** ShellRunner with mock CLI scripts
- **Coverage:** ~5% of test count, some in ShellRunnerTests

**E2E Tests:**
- **Framework:** Not used
- **Reason:** Too tightly coupled to system (AX API, menu bar, hotkeys)
- **Alternative:** Manual testing; critical paths covered by unit + integration tests

## Common Patterns

**Async Testing:**
```swift
// XCTest does not have built-in async/await support (for this Swift version)
// Not needed: no async operations in GhostEditCore
// If needed in future: use expectation(description:) + waitForExpectations()
```

**Error Testing:**

Test that correct error is thrown:
```swift
func testCorrectTextThrowsWhenCLINotFound() throws {
    let runner = ShellRunner(configManager: configWithMissingCLI)
    XCTAssertThrowsError(
        try runner.correctText(systemPrompt: "p", selectedText: "x")
    ) { error in
        XCTAssertEqual(error as? ShellRunnerError, .cliNotFound(provider: .claude))
    }
}
```

Test graceful fallback:
```swift
func testLoadConfigReturnsDefaultWhenConfigIsInvalid() throws {
    try "{ invalid json }".write(to: configURL, atomically: true, encoding: .utf8)
    let config = manager.loadConfig()
    XCTAssertEqual(config, AppConfig.default)
}
```

**Temporary File Handling:**

Always collect and cleanup:
```swift
private var tempRoots: [URL] = []

override func tearDownWithError() throws {
    for root in tempRoots {
        try? FileManager.default.removeItem(at: root)
    }
    tempRoots.removeAll()
}

private func makeManager() -> (ConfigManager, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-\(UUID().uuidString)", isDirectory: true)
    tempRoots.append(root)  // Register for cleanup
    return (ConfigManager(...), root)
}
```

**Data Round-Trip Testing:**

Encode → Decode → Assert equality:
```swift
func testSoundFeedbackEnabledRoundTrip() throws {
    var config = manager.loadConfig()
    config.soundFeedbackEnabled = false
    try manager.saveConfig(config)
    manager.invalidateCache()

    XCTAssertFalse(manager.loadConfig().soundFeedbackEnabled)
}
```

**Isolation with Factory Methods:**

Create clean test environment per test:
```swift
private func makeRunnerEnvironment() -> (manager: ConfigManager, runner: ShellRunner, homeURL: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shell-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    tempRoots.append(root)

    let manager = ConfigManager(fileManager: .default, homeDirectoryURL: root)
    let runner = ShellRunner(configManager: manager, homeDirectoryPath: root.path)

    return (manager, runner, root)
}
```

## Test-Only APIs

**Setter methods for dependency injection:**

Classes provide test-only setters to inject mocks:
```swift
/// Test-only: inject a mock persistent session.
func setPersistentSessionForTesting(_ session: PersistentCLISessionProtocol?) {
    persistentSessionLock.lock()
    persistentSession = session
    persistentSessionLock.unlock()
}

/// Test-only: override the factory.
func setSessionFactoryForTesting(_ factory: @escaping () -> PersistentCLISessionProtocol) {
    sessionFactory = factory
}
```

These methods are only called in tests and documented as such.

## Test Discipline

**One assertion per test concept:**
Multiple XCTAssert calls OK if testing single behavior; separate tests for separate concerns:

```swift
// GOOD: Each test is focused
func testConfigBootstrapCreatesFiles() { }
func testConfigBootstrapPreservesExisting() { }

// AVOID: Mixed concerns in one test
func testConfigBootstrap() {
    // setup
    // assert created
    // modify
    // assert preserved
    // load
    // assert loaded
}
```

**Arrange-Act-Assert:** Tests follow AAA pattern implicitly:
```swift
// Arrange: Create fixtures
let (manager, homeURL) = makeManager()

// Act: Call function
try manager.bootstrapIfNeeded()

// Assert: Check results
XCTAssertTrue(FileManager.default.fileExists(...))
```

---

*Testing analysis: 2026-02-26*
