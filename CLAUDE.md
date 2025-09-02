# Claude Development Guide for Revise

## Project Overview

Revise is a premium iOS writing app focused on short-form text perfection through non-destructive editing and AI-powered variations. This is a SwiftUI-first application targeting iOS 18+ with the latest APIs.

## Architecture Principles

### No MVVM Pattern
- Use @Observable objects directly
- Inject shared state via SwiftUI environment
- Keep business logic in Observable classes
- Views can directly own their state when not shared

### Core Components

1. **MagneticTextView**: UITextView wrapper for SwiftUI
   - Magnetic text selection with word/sentence/line snapping
   - Haptic feedback for premium feel
   - Smart content detection (poetry vs prose)
   - Gesture-based selection

2. **Version Timeline**: 
   - Vertical axis for chronological edits
   - Auto-save on every edit
   - Commit points: minor (pause), major (paragraph), tagged (export)
   - Two-finger swipe navigation
   - Visual scrubber on right edge

3. **Branch System**:
   - Horizontal axis for alternative versions
   - Created via: explicit branch, AI variations, or major rewrites
   - Swipe left/right to switch branches
   - Visual tree with node types (edit, AI, starred)


## Key Implementation Details

### Text Editor Requirements
- Must wrap UITextView for advanced text manipulation
- Implement magnetic selection at word/sentence/line boundaries
- Provide haptic feedback on selection changes
- Auto-detect content type (poetry/prose/code)

### Version Control
- Every edit triggers auto-save
- Use differential storage for efficiency
- Implement smart commit grouping (rapid typo fixes vs deliberate edits)
- Support branching for exploring alternatives

### Gesture Navigation
- Vertical swipe: timeline navigation
- Horizontal swipe: branch switching
- Pinch: zoom time density or enter tree view
- Force press: peek at version
- Three-finger tap: quick tree overlay

### AI Integration
- Three modes: Rephrase, Tone Shift, Constrain
- Each AI suggestion creates new branch
- Maintain context of current writing style
- Cache responses for performance

## Testing Requirements

- Test magnetic selection across different text types
- Verify version persistence and restoration
- Test gesture recognition and conflicts
- Validate AI response handling
- Performance testing with large documents

## Important Notes

1. **iOS 26 APIs**: Use latest TextKit 2 and SwiftUI features
3. **Memory**: Implement smart caching for version history
4. **Accessibility**: Full VoiceOver support required
5. **Typography**: Variable fonts responsive to context


## Typography & Fonts

### Custom Fonts
- **Literata**: Serif font for body text and poetry
- **Inter**: Sans-serif font for UI elements

### Font Usage
```swift
// Basic usage
Text("Hello World").font(.literata())

// With text styles
Text("Title").font(.literata(.title))
Text("Body").font(.inter(.body))

// View modifier shorthand
Text("Poetry").literataFont(.body)
Text("UI Label").interFont(.caption)
```

**Important**: Call `CustomFonts.registerFonts()` in app initialization.

## Design Guidelines

- **Colors**: Minimal palette, focus on typography
- **Animations**: Subtle, purposeful, spring-based
- **Feedback**: Immediate haptic response
- **Layout**: Generous padding, readable line lengths


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

