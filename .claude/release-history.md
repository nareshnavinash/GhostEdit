# GhostEdit Release History

## v5.4.0-beta.1 (build 25) — 2026-02-25
**Low Priority UI Polish + Bug Fix**
- Fixed history status badge showing wrong state (used boolean directly, identifier-based subview lookup)
- Character-level diff in streaming preview (was word-level)
- Line number ruler on both text views
- Previous/Next Change navigation buttons
- Hotkey tooltip on menu item, app icon on version item
- Save confirmation overlay, NSSwitch for login toggle
- Window position restoration for all 5 windows
- Search/filter in History (NSSearchField + segmented All/Success/Failed)
- Char count on success HUD, color tint per state, slide-up animation, progress spinner
- Transparent title bars, consistent button styling, update badge, text preview limits, stats bar

## v5.3.0-beta.1 (build 24) — 2026-02-25
**Medium Priority UI Polish**
- Inline descriptions for settings fields
- Model description display
- Hotkey badge in menu
- Colored duration in history
- Relative timestamps
- Empty state for history
- Styled headers with color-coded backgrounds
- Button styling (green primary buttons)

## v5.2.0-beta.1 (build 23) — 2026-02-24
**High Priority UI Items**
- SF Symbols throughout menus and settings
- Tabbed settings window (General/Hotkey/Behavior/Advanced)
- Status badges in history table
- Other high priority cosmetic items

## v5.1.0-beta.1 — 2026-02-24
- Persistent CLI sessions for zero-bootstrap corrections
- Coverage fixes

## v5.0.1 — 2026-02-22
- Em dash stripping from model output
- Initial release with full test coverage

## Key Patterns for Version Bumps
- `MARKETING_VERSION` in project.pbxproj (2 occurrences: Debug + Release)
- `CURRENT_PROJECT_VERSION` in project.pbxproj (2 occurrences for app target; test target stays at 1)
- Note: project.yml has stale version (5.0.1/build 21) — the xcodeproj is the source of truth
