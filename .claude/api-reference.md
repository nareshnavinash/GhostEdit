# GhostEdit API Reference

## ConfigManager.swift
```
enum CLIProvider: String, Codable, CaseIterable  — .claude, .codex, .gemini
  .displayName, .executableName, .authCommand, .availableModels, .defaultModel(for:)

struct AppConfig: Codable
  provider, model, timeout, hotkeyKeyCode, hotkeyModifiers, clipboardOnlyMode,
  useStreamingMode, historyLimit, soundFeedbackEnabled, notificationsEnabled,
  developerMode, tonePreset, language, launchAtLogin
  static supportedPresets, supportedLanguages
  func resolvedPath(for:), resolvedModel(for:), promptForPreset(), languageInstruction()

class ConfigManager
  baseDirectoryURL, configURL, historyURL, promptURL, profilesURL
  bootstrapIfNeeded(), loadPrompt(), loadConfig(), saveConfig(), invalidateCache()
```

## ShellRunner.swift
```
enum ShellRunnerError: Error  — cliNotFound, authRequired, launchFailed, processFailed,
                                timeout, emptyResponse, protectedTokensModified

class ShellRunner
  init(configManager:)
  correctText(systemPrompt:, selectedText:) throws -> String
  correctTextStreaming(systemPrompt:, selectedText:, onChunk:) throws -> String
  correctTextPreservingTokens(systemPrompt:, selectedText:, maxValidationRetries:) throws -> String
  prewarm(), spawnPersistentSession(), killPersistentSession()
  static trimPreservingInternalNewlines(_:) -> String
```

## DiffSupport.swift
```
enum DiffSegmentKind: Equatable  — .equal, .insertion, .deletion
struct DiffSegment: Equatable  — kind: DiffSegmentKind, text: String

enum DiffSupport
  static wordDiff(old:, new:) -> [DiffSegment]     // word-level, for summaries
  static charDiff(old:, new:) -> [DiffSegment]     // char-level, for display
  static isIdentical(old:, new:) -> Bool
  static changeSummary(segments:) -> String          // "3 words added, 1 removed"
  static tokenize(_:) -> [String]
```

## HUDOverlaySupport.swift
```
enum HUDOverlayState: Equatable  — .working, .success, .successWithCount(Int), .error(String)
struct HUDOverlayContent: Equatable  — emoji: String, message: String

enum HUDOverlaySupport
  // Layout: windowWidth/Height, cornerRadius, iconSize, messageFontSize, verticalSpacing, contentInset
  // Timing: fadeInDuration, fadeOutDuration, workingAutoDismissDelay, successAutoDismissDelay, errorAutoDismissDelay
  // Ghost SVG: ghostBodyPath, ghostMouthPath, ghostBridgePath, ghostLeftArmPath, ghostRightArmPath
  // Eyes: GhostEye struct, ghostLeftEye, ghostRightEye
  static content(for:) -> HUDOverlayContent
  static showsSpectacles(for:) -> Bool
  static autoDismissDelay(for:) -> TimeInterval?
  static windowOrigin(screenSize:) -> CGPoint
```

## CorrectionHistoryStore.swift
```
struct CorrectionHistoryEntry: Codable, Equatable
  id: UUID, timestamp: Date, originalText, generatedText, provider, model,
  durationMilliseconds: Int, succeeded: Bool

class CorrectionHistoryStore
  init(fileURL:, fileManager:)
  bootstrapIfNeeded(), load(), append(_:, limit:), lastSuccessfulEntry(), trim(limit:)
```

## HistoryTableModel.swift
```
enum HistoryTableColumn: String, CaseIterable  — .timestamp, .status, .provider, .model, .duration, .original, .generated
struct HistoryTableRow: Equatable  — init(entry:, timestampFormatter:), value(for:)
  .status = entry.succeeded ? "Succeeded" : "Failed"
enum HistoryTableModel  — static rows(from:, timestampFormatter:)
```

## HotkeySupport.swift
```
struct HotkeyKeyOption  — title: String, keyCode: UInt32
enum HotkeySupport
  static keyOptions: [HotkeyKeyOption], defaultKeyCode: UInt32
  static keyTitle(keyCode:), makeModifiers(from:), splitModifiers(_:), displayString(keyCode:, modifiers:)
```

## StreamingPreviewSupport.swift
```
enum StreamingPreviewSupport
  struct StyledSegment  — text: String, kind: Kind (.unchanged/.added/.removed)
  static styledSegments(from:) -> [StyledSegment]
  static correctedText(from:) -> String
  static streamingStatus(charCount:) -> String
  static completedStatus(changeCount:) -> String
  static changeCount(from:) -> Int
```

## ClipboardManager.swift
```
class ClipboardManager
  enum ShortcutPosting  — .annotatedSession, .hidSystem
  struct Snapshot  — items: [ItemPayload]
  snapshot(), restore(_:), readPlainText(), readBestText(), readHTMLString()
  writePlainText(_:), simulateCopyShortcut(using:), simulatePasteShortcut(using:)
```

## TokenPreservationSupport.swift
```
struct ProtectedToken  — placeholder, originalToken
struct TokenProtectionResult  — protectedText, tokens, hasProtectedTokens

enum TokenPreservationSupport
  static protectTokens(in:) -> TokenProtectionResult
  static appendInstruction(to:) -> String
  static placeholdersAreIntact(in:, tokens:) -> Bool
  static restoreTokens(in:, tokens:) -> String
  static bestEffortRestore(in:, tokens:) -> String
  static splitAroundTokens(in:) -> (segments:, tokens:)
  static reassemble(segments:, tokens:) -> String
  static stripTokens(from:, tokens:) -> String
```

## FallbackSupport.swift
```
enum FallbackSupport
  static nextFallbackModel(currentModel:, provider:) -> String?
  static isRetriable(_: Error) -> Bool
```

## UpdateCheckSupport.swift
```
struct VersionInfo  — current, latest, isUpdateAvailable, releaseURL
enum UpdateCheckSupport
  static defaultReleaseURL: String
  static isNewer(latest:, current:) -> Bool
  static parseSemver(_:) -> (Int, Int, Int)?
  static checkVersion(current:, latestTag:, releaseURL:) -> VersionInfo
```

## AccessibilityTextSupport.swift
```
protocol AXElementProviding  — createApplication(), copyAttribute(), setAttribute()
struct SystemAXElementProvider: AXElementProviding
enum AccessibilityTextSupport
  static readSelectedText(appPID:, provider:) -> String?
  static replaceSelectedText(appPID:, with:, provider:) -> Bool
```

## WritingCoachSupport.swift
```
struct WritingCoachInsights  — positives: [String], improvements: [String], hasContent: Bool
enum WritingCoachSupport
  static systemPrompt: String
  static buildInput(samples:) -> String
  static parseInsights(_:) -> WritingCoachInsights?
  static popupText(insights:) -> String
```

## AppProfileSupport.swift
```
struct AppProfile: Codable  — bundleIdentifier, tonePreset?, model?, provider?
enum AppProfileSupport
  static resolvedConfig(base:, profiles:, bundleIdentifier:) -> AppConfig
  static apply(profile:, to:) -> AppConfig
  static loadProfiles(from:) -> [AppProfile]
  static saveProfiles(_:, to:)
```

## Other Support Files (smaller)
- **CorrectionStatisticsSupport** — format stats for display (averages, counts, tokens)
- **DeveloperModeSupport** — truncate(), formatEntry(), log phase colors
- **MenuBarIconSupport** — icon descriptor, renderIcon()
- **TooltipSupport** — formatTooltip() for menu bar
- **PartialCorrectionSupport** — splitSentences(), reassembleSentences()
- **TokenEstimationSupport** — estimateTokens(), formatTokenCount()
- **HistoryCSVExporter** — csv(entries:, timestampFormatter:)
- **SettingsExportSupport** — export(), `import`()
- **WritingCoachLayoutSupport** — panel dimensions, cappedItems()
- **SettingsLayoutSupport** — section spacing constant
- **AccessibilitySupport** — guidanceText()
- **ClaudeRuntimeSupport** — resolveClaudeCLIPath(), validateAuth()
