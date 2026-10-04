# Mint for contributors

A native macOS app built with SwiftUI, SwiftData, Swift Charts and Swift Testing. It has no third-party dependencies. Use Apple's frameworks and their documented APIs, not private APIs or workarounds.

## Commands

```bash
xcodebuild test -scheme Mint -destination 'platform=macOS' -derivedDataPath build.noindex
./install.sh                     # Release build into /Applications
swift scripts/make-icon.swift    # redraw the app icon
```

Build into `build.noindex` (git-ignored) so Spotlight skips the build copies.

## Layout

- `Mint/Model`: data and money math, with no UI.
  - The SwiftData models are `Entry`, `RecurringSeries` and `BalanceAdjustment`.
  - `Ledger` works out balances, forecasts and statistics.
  - `Scheduler` creates and edits repeats.
  - `ReminderPlanner` decides which reminders to send, and `ReminderCenter` sends them.
  - `AppModel` holds window state shared by the menus and the views.
- `Mint/Views`: one file per screen, plus shared pieces.
  - `DesignSystem.swift` holds the theme, `Page`, cards, `StatusMark`, bars and money text.
  - `Keyboard.swift` handles row selection and the Entry menu.
  - `ShortcutsView.swift` is the in-app shortcut list.
- `MintTests`: Swift Testing. Tests use an in-memory store and never touch real data. `-demo YES` also uses memory only (see `AppEnvironment`).
- `docs/Guide.md`: the user guide.

## Conventions

- Money is whole cents (`Int`). Format it with `Money`, and dates with `DayText`.
- Day math goes through `Ledger` (its `calendar` and `today`), so tests can pin the date.
- Saves happen right away (`saveNow`). There is no Save button except in the entry editor.
- Doc comments say what something is for, in plain words. Match the surrounding style.

## Design

- Calm, and minty without being loud. Take colors from `Theme`: green for money in and paid, red for money out and problems, amber for scheduled.
- Show only what matters. Prefer a symbol or a small chart to a sentence, as with the status marks, `Bar` and the outlook line.
- Everything must work from the keyboard. A new action needs a menu item with a shortcut, an entry in `ShortcutsView` and a line in `docs/Guide.md`.
- Check both light and dark mode, and narrow windows.

## Keeping docs current

A user-visible change gets a line in `docs/Guide.md`. Change the README only when installing or data storage changes.
