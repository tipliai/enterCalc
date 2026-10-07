# EnterCalc

**EnterCalc: Your Calculation Crunching Companion**

You enter calculations, EnterCalc returns results. EnterCalc is a native calculator for iOS and macOS, focused on simplicity, intuitive quality-of-life improvements, and easy multitasking.

Download on the Apple App Store: [apps.apple.com/app/id6777242723](https://apps.apple.com/app/id6777242723)

## Support

- Public support page: [tipliai.github.io/enterCalc/support](https://tipliai.github.io/enterCalc/support/)
- GitHub issues: [github.com/tipliai/enterCalc/issues](https://github.com/tipliai/enterCalc/issues)
- Repository: [github.com/tipliai/enterCalc](https://github.com/tipliai/enterCalc)

## Features

- Free & open-source under the MIT License
- Open multiple calculator panels with independent calculations and settings
- Calculation history with quick reuse of previous results
- Advanced copy, paste, undo, and redo support
- One-click copying for fast workflows
- Preserve calculation context when copying and pasting
- Digit-level editing for quick corrections
- Hardware keyboard and shortcut support
- Landscape mode support
- Optional scientific notation
- Configurable rounding behavior
- Function keys you can reassign per page — press and hold on iOS, right-click on macOS
- Currency mode with a choice of symbol, plus live VAT (add or remove) and Tip panes with region-aware VAT presets you can edit
- Multiple number formatting styles
- Multiple language and localization options
- Support for alternative keyboard layouts
- Light and Dark Mode support with multiple themes
- Optional tactile and audio feedback on supported devices
- Accessibility-focused design
- Lightweight and distraction-free
- Privacy-focused, operates entirely on your device with no tracking or analytics

## Release Scope

The initial `1.0.0` release focused on the core Basic calculator experience. `1.1.0` builds on it with:

- **Currency mode**: a currency key you can toggle (it stays on through AC and is highlighted while on), a symbol picker in Settings, and the caret kept after the symbol while editing
- **VAT and Tip panes**: results apply as soon as a pane opens, with a trash button to take them off. VAT can be added or removed, with three presets from a verified table of each region's rates. Tip has presets and a slider from Off to 40%. Long-press a preset to set your own rate, typed to any precision and shown to three decimals
- **Configurable function keys**: reassign the top-row keys on each page — press and hold on iOS, right-click on macOS
- **Page switching**: keyboard shortcuts, swipes that need clear intent and no longer drop fast taps, a fixed rail for the page dots, and a theme crossfade
- **Percent fixes**: `9% + 9%` gives `18%`, and in currency mode `$10 + 10%` gives `$11`
- **Faster key presses on iOS**: feedback work moved off the press path, roughly halving the time to handle a tap
- **Settings and accessibility**: a feedback link and a rating prompt, an equals key labelled to suit the layout and language, keyboard resizing of the display on macOS, VoiceOver labels for the macOS header controls, and the macOS theme repainting correctly when switched to System

Planned future enhancements include:

- Scientific mode
- Programmer mode
- Additional customization and workflow improvements

## System Requirements

- macOS 14.0+
- iOS 17.0+

## Contributing

Contributions, feedback, and issue reports are welcome.

### Development Requirements
- macOS 14.0+ for the macOS app target
- iOS 17.0+ for the iOS app target

For Apple-platform work in Xcode, open `apple/EnterCalc.xcworkspace` or `apple/xcode/EnterCalc.xcodeproj`.
Opening the `apple/` folder itself will surface the local Swift package (`EnterCalc` / `EnterCalcCore`) instead of the app project.

### Additional Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — Issue reporting guidance and pull request policy
- [docs/keyboard.md](docs/keyboard.md) — Keyboard actions and context behavior matrix for iOS and macOS
