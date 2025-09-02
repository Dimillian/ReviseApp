# Repository Guidelines

## Project Structure & Module Organization
- Source in `Revise/` (entry: `ReviseApp.swift`, main views like `ContentView.swift`).
- Design system in `Revise/DesignSystem/` (`Color.swift`, `Font.swift`).
- Assets in `Revise/Assets.xcassets/`; fonts in `Revise/Fonts/`.
- Tests in `ReviseTests/` and UI tests in `ReviseUITests/`.
- Xcode project: `Revise.xcodeproj` (scheme: `Revise`). See `CLAUDE.md` for architecture details.

## Build, Test, and Development Commands
- Open in Xcode: `xed .` or `open Revise.xcodeproj`.
- Build (Debug): `xcodebuild -scheme Revise -configuration Debug -destination 'generic/platform=iOS' build`.
- Run tests (unit+UI): `xcodebuild -scheme Revise -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test`.
- Clean build artifacts: `xcodebuild -scheme Revise clean`.

## Coding Style & Naming Conventions
- Swift with 2-space indentation; keep lines focused; no trailing whitespace.
- Types in PascalCase; functions/variables in lowerCamelCase; files match primary type name.
- Prefer SwiftUI with `@Observable` and environment injection; no MVVM. Keep business logic in observable classes.
- Use design tokens: `Color.*` for semantic colors and `Font.literata`/`Font.inter` for typography.

## Testing Guidelines
- Framework: XCTest. Name files `*Tests.swift`; test methods `test_*`.
- Prioritize: magnetic selection accuracy, version persistence/restore, gesture conflict handling, AI suggestion lifecycle.
- Run on iOS 26 simulators; keep tests deterministic and fast. Add UI screenshots only when assertions are insufficient.

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise summary; reference issues (e.g., `Fix: selection snaps to word (#123)`).
- PRs: clear what/why, screenshots or GIFs for UI changes, test plan, and linked issues. Keep PRs focused and small when possible.
- Ensure builds and tests pass before requesting review.

## Architecture Notes
- Target iOS 26; SwiftUI + TextKit 2.
- Core components: MagneticTextView, Version Timeline, Branch System. Each edit auto-saves; AI variations create branches.
- Read `README.md` and `CLAUDE.md` before touching editor, versioning, or gesture code.

## Security & Configuration Tips
- Do not commit secrets or tokens. Keep third-party assets/fonts licensed and in `Revise/Fonts/`.
- Maintain accessibility (VoiceOver) and performance budgets when modifying UI/gestures.

