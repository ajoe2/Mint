# Mint

A simple Mac app for tracking your bank balance: what you spend, earn, invest and receive in subsidies, and what's coming up.

## Install

Requires macOS 27 and Xcode 27.

```bash
git clone git@github.com:ajoe2/Mint.git
cd Mint
./install.sh
```

The script builds Mint and puts it in your Applications folder. Run it again to update; if Mint is open, it quits and reopens it.

On first launch, enter your bank balance and the date it's from. Then add your paycheck and regular bills, and Mint shows where your balance is heading.

## Learn more

- [User guide](docs/Guide.md): balances, entries, screens, keyboard shortcuts and reminders. In the app, **Help → Keyboard Shortcuts** (⌘?) lists every shortcut.
- [AGENTS.md](AGENTS.md): building, testing and how the code is organized.

## Try it with sample data

Demo mode fills Mint with example entries, saves nothing and sends no notifications. Quit Mint, then:

```bash
open /Applications/Mint.app --args -demo YES
```

## Your data

Mint keeps everything on your Mac, in `~/Library/Containers/com.ajoe.Mint/`. Time Machine backs it up.
