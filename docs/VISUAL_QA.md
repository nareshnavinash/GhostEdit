# Visual QA Checklist — Run Before Each Release

## Prerequisites
- Build: `xcodebuild build -project GhostEdit.xcodeproj -scheme GhostEdit -configuration Release`
- Install: copy to /Applications, codesign, launch
- Open TextEdit with sample text for testing

## 1. Menu Bar
- [ ] Ghost icon appears in menu bar (not blurry, correct size)
- [ ] Click icon → dropdown menu shows all items
- [ ] Menu items: Fix Grammar, Fix Grammar (Cloud), Settings, History, Quit
- [ ] Hotkey labels shown next to menu items

## 2. HUD Overlay States
- [ ] Trigger cmd+E on text → HUD appears with "Correcting..." + spinner
- [ ] Correction completes → HUD shows green checkmark + char count
- [ ] Trigger on text with changes → HUD shows inline diff (red/green)
- [ ] Trigger on empty selection → error sound, no HUD
- [ ] Trigger without accessibility → HUD shows error message in red

## 3. Streaming Preview (cmd+shift+E)
- [ ] Trigger on selected text → streaming window opens
- [ ] Left pane: original text with line numbers
- [ ] Right pane: corrected text appears progressively
- [ ] Progress: character count updates during streaming
- [ ] Completion: "Done" label, similarity %, change count
- [ ] Change navigation: arrows highlight each change
- [ ] Changes highlighted: red (deletion) / green (insertion)
- [ ] Tab key: accepts correction, closes window, pastes text
- [ ] Esc key: cancels, closes window, does NOT paste
- [ ] R key (after completion): regenerates with new LLM call

## 4. Settings Window
- [ ] Menu → Settings opens settings window
- [ ] 5 toolbar tabs: General / Hotkey / Behavior / Local Models / Advanced
- [ ] General tab: Provider dropdown (Claude/Gemini/Codex), model dropdown, executable path
- [ ] Hotkey tab: Local hotkey + Cloud hotkey with modifier checkboxes
- [ ] Hotkey tab: Preview label updates when modifiers change
- [ ] Behavior tab: Sound toggle, notification toggle, clipboard-only toggle
- [ ] Local Models tab: Repo ID field, Python path, download button
- [ ] Advanced tab: Timeout, history limit, diff preview duration
- [ ] Save: validates all fields, shows alert on error
- [ ] Save: persists to ~/.ghostedit/config.json
- [ ] Cancel: discards changes

## 5. History Window
- [ ] Menu → History opens history window
- [ ] Table shows: timestamp, original, corrected, provider, model, status badge
- [ ] Status badge: green checkmark for success, red X for failed
- [ ] Search field: filters across all text columns
- [ ] Segment control: All / Success / Failed
- [ ] Double-click row: shows detail view
- [ ] Undo button: reverts to original text via clipboard
- [ ] Export CSV: saves valid CSV file
- [ ] Relative timestamps: "2 minutes ago", "yesterday", etc.

## 6. Diff Preview Window
- [ ] Appears for non-streaming corrections (if enabled in settings)
- [ ] Left: original with red strikethrough for deletions
- [ ] Right: corrected with green underline for insertions
- [ ] Apply button (Tab): applies correction
- [ ] Cancel button (Esc): discards correction

## 7. Live Feedback Widget
- [ ] Enable in settings → widget appears near focused text field
- [ ] Widget dot: gray=idle, orange=checking, green=clean, red=issues
- [ ] Click widget → popover shows issue list
- [ ] Each issue: word, suggestion, Fix button, Ignore button
- [ ] Fix button: applies suggestion inline
- [ ] Ignore button: adds word to ignored list
- [ ] Widget repositions when focus changes
- [ ] Widget hides when no text field is focused
- [ ] cmd+E with live feedback active: applies all fixes at once

## 8. Developer Console
- [ ] Toggle via developer mode setting
- [ ] Shows timestamped log entries with color-coded phases
- [ ] Clear button: empties log
- [ ] Copy button: copies all entries to clipboard

## 9. Cross-App Verification
Test correction in each of these apps (different text input methods):
- [ ] TextEdit (standard Cocoa text field)
- [ ] Safari (web form fields)
- [ ] VS Code (Electron app — clipboard fallback)
- [ ] Slack (Electron + emoji — U+FFFC handling)
- [ ] Terminal (limited accessibility)
- [ ] Notes (rich text)

## 10. Edge Cases
- [ ] Very long text (>10K chars): no freeze, correction completes
- [ ] Text with URLs/emails: preserved after correction
- [ ] Text with @mentions: preserved after correction
- [ ] Text with code blocks: preserved after correction
- [ ] Multiple rapid triggers: second trigger rejected ("Already processing")
- [ ] App quit during correction: clean shutdown, no zombie processes
