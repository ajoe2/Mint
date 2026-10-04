# Mint

A simple Mac app for tracking your bank balance: what you spend, earn, invest and receive in subsidies, and what's coming up.

## How it works

**Balance.** On first launch, enter your bank balance and the date it's from. From then on, your balance is that amount plus everything paid or received since.

**Adjusting the balance.** When Mint and your bank disagree, choose **Adjust…** on the Overview (or **File → Adjust Balance…**, ⇧⌘B) and enter what your bank shows for any day up to today. The balance then counts from that amount and day:

- Entries paid on or before that day are treated as part of the amount.
- Entries paid later change the balance from there, and scheduled entries still count on their dates.
- Entries from before the adjustment still count in Statistics.
- Choosing an earlier day replaces any balances set on or after it. The sheet warns you first, and ⌘Z undoes it.

Each adjustment shows in Transactions as a **Manual adjustment**, with how much it changed the balance. Adjustments don't count as income or spending.

**Kinds of entries:**

| Kind       | Effect on balance |
|------------|-------------------|
| Spend      | Takes money out   |
| Income     | Adds money        |
| Investment | Takes money out, into your investments |
| Subsidy    | Adds money, tracked apart from income |

**Status.** Every entry is **Unpaid** (red), **Scheduled** (yellow) or **Paid** (green). Income and subsidies say Not received and Received; investments say Not invested and Invested.

- **Unpaid**, the default: no money has moved yet. Give it a **due date** to see it in Coming up, marked **Due soon** in the week before and **Overdue** after.
- **Scheduled**: set for a future date, and counted as paid on that day. Marked **Late** if that's after the due date.
- **Paid**: the money has moved and counts toward your balance.

Click a row's status label to change its status and dates without opening the entry.

**Repeating entries.** Rent, paychecks and subscriptions can repeat weekly, every 2 weeks, monthly, every 3 months or yearly, up to a year ahead. When you edit or delete one, you choose between just that one, or that one and the ones after it. Repeats already paid or due are left alone.

**Screens:**

- **Overview:** your balance, where it'll be in four weeks, its lowest point ahead, and a chart from a month ago to three months out (hover for amounts). Below that: **Overdue** entries with a **Mark Paid** button, **Coming up** in the next four weeks with your balance after each, and **This month** so far.
- **Transactions:** everything in one list: overdue, coming up (later months a click away), entries with no date, then past months, including adjustments. Filter by kind at the top.
- **Statistics:** totals by kind, net, and spending by category for this month, this year or all time, plus money in and out for each of the last 12 months.

Search (⌘F) finds entries by name, category or notes. Press Return to move into the results.

Click an entry to edit it, or right-click it for **Mark as Paid Today**, **Duplicate** and **Delete**.

**Keyboard.** Everything works from the keyboard; **Help → Keyboard Shortcuts** (⌘?) lists every shortcut. The main ones:

- ⌘N adds an entry. ⌘1–⌘3 switch screens, and ⇧⌘] and ⇧⌘[ (or ⌥⌘→ and ⌥⌘←, or ⌃⇥ and ⌃⇧⇥) go to the next or previous one.
- In Overview and Transactions, ↑ and ↓ move between entries and ⌘↑ and ⌘↓ jump to the first and last. Return (or ⌘O) edits, Space (or ⌘I) changes the status, ⇧⌘C marks paid, ⌘D duplicates and Delete deletes.
- ← and → switch the Transactions filter and the Statistics period.
- In the entry editor, ⌘1–⌘4 pick the kind and Return saves.

**Reminders.** Mint sends a notification a day before anything unpaid is due, and again the day after if it's still unpaid. Click one to open the entry, or use its **Mark Paid** button. It also warns you a day before your balance is expected to drop below your limit ($0 unless you change it), and the Overview shows the same warning. Notifications arrive even when Mint isn't open. macOS asks for permission the first time there's something to remind you about.

**Settings** (⌘,) turns each kind of reminder on or off and sets the limit, how far ahead and at what time. It also lists your starting balance and adjustments so you can delete a mistake. **Reset…** erases all entries, balances and settings, and can't be undone.

## Running it

Requires macOS 27 and Xcode 27. To build Mint and install it in Applications:

```bash
./install.sh
```

Run it again after any change. If Mint is open, the script quits it and reopens it afterward.

You can also open `Mint.xcodeproj` and press ⌘R. Both copies use the same data.

### Sample data

Demo mode fills Mint with example entries and saves nothing. Quit Mint, then:

```bash
open /Applications/Mint.app --args -demo YES
```

In Xcode, add `-demo YES` under **Product → Scheme → Edit Scheme… → Run → Arguments**. Demo mode never sends notifications.

## Your data

Mint stores everything with SwiftData in its sandbox container, `~/Library/Containers/com.ajoe.Mint/`. Time Machine backs it up.

## Development

```bash
xcodebuild test -scheme Mint -destination 'platform=macOS' -derivedDataPath build.noindex
```

Building into `build.noindex` keeps the test copy of the app out of Spotlight.

- `Mint/Model`: the data model (`Entry`, `RecurringSeries`, `BalanceAdjustment`) and the money math. `Ledger` works out balances, projections and statistics, `Scheduler` creates and edits repeating entries, and `ReminderPlanner` decides which reminders `ReminderCenter` sends.
- `Mint/Views`: the SwiftUI screens.
- `MintTests`: Swift Testing tests. They use an in-memory store, so they never touch your data.
- `scripts/make-icon.swift`: draws the app icon. Run `swift scripts/make-icon.swift` from this folder after changing it.
