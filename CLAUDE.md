# Claude Development Guide for Revise

## Project Overview

Revise is a premium iOS writing app focused on short-form text perfection through non-destructive editing and AI-powered variations. This is a SwiftUI-first application targeting iOS 26+ with the latest APIs.

## Architecture Principles

### No MVVM Pattern
- Use @Observable objects directly
- Inject shared state via SwiftUI environment
- Keep business logic in Observable classes
- Views can directly own their state when not shared

### Data Persistence with SwiftData
- Uses SwiftData (iOS 17+) for all data persistence
- No manual JSON encoding/decoding or file management
- Core Data models: Document, Branch, Version
- Relationships are managed automatically by SwiftData

### Core Components

1. **MagneticTextView**: UITextView wrapper for SwiftUI
   - Magnetic text selection with word/sentence/line snapping
   - Haptic feedback for premium feel
   - Smart content detection (poetry vs prose)
   - Gesture-based selection

2. **Version Timeline**: 
   - Vertical axis for chronological edits
   - Auto-save on every edit with coalescing (2 second window)
   - Visual timeline with centered dots in glass-effect capsule
   - Drag gesture for scrubbing through versions
   - Shows word count and timestamp on hover (expanded mode)

3. **Branch System**:
   - Horizontal axis for alternative versions
   - Created via: explicit branch, AI variations, or major rewrites
   - Pinch gesture reveals branch graph visualization
   - Visual tree with node tiles showing preview text
   - Branch graph shows parent-child relationships with curved edges

4. **Data Models (SwiftData)**:
   - **Document**: Has unique id, title, lastEdited, currentBranch, and branches[]
   - **Branch**: Has unique id, belongs to Document (non-optional), has parent Branch (optional), versions[], and currentVersion
   - **Version**: Has unique id, belongs to Branch (non-optional), stores text, changeKind, word/character counts, cursor position, and selection ranges


## Key Implementation Details

### Text Editor Requirements
- Must wrap UITextView for advanced text manipulation
- Implement magnetic selection at word/sentence/line boundaries
- Provide haptic feedback on selection changes
- Auto-detect content type (poetry/prose/code)

### Version Control
- Every edit triggers auto-save via VersionController
- Coalescing: rapid edits within 2 seconds update the same version
- Maximum 100 versions per branch (oldest removed when exceeded)
- VersionController manages all version operations (add, undo, redo, navigate)
- Branch creation copies current version as seed for new branch

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

## Important Architectural Details

### SwiftData Implementation
- **ModelContainer**: Configured in ReviseApp with all three models
- **@Query**: Used in views for reactive data fetching with predicates
- **ModelContext**: Accessed via @Environment for data mutations
- **Relationships**: Properly configured with inverse relationships and cascade delete rules
- **Non-optional relationships**: Branch must have Document, Version must have Branch

### Key Controllers
- **VersionController**: Manages all version operations, replaces old VersionStore
  - Handles version coalescing, undo/redo, branch operations
  - Integrates with ModelContext for persistence
- **EditorController**: Manages text editor state and interactions
  - Handles synonym selection, text restoration, haptic feedback
  - Communicates with VersionController for version management

### UI State Management
- Timeline state (hidden/visible/expanded) managed locally in EditorView
- Branch graph visibility controlled by pinch gesture
- Editor scale for zoom effect during branch visualization
- All UI state uses @State, business logic in @Observable controllers

## Important Notes

1. **iOS 26+ Only**: Uses latest TextKit 2, SwiftUI, and SwiftData features
2. **No Legacy Storage**: All data persistence through SwiftData, no JSON files
3. **Memory**: SwiftData handles caching, max 100 versions per branch
4. **Accessibility**: Full VoiceOver support required
5. **Typography**: Literata for content, Inter for UI, with dynamic sizing


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
- **Use XcodeBuildMCP for building**: Always use the MCP tools for building and validation
- **Build validation**: Use `mcp__XcodeBuildMCP__build_sim` to verify code compiles without errors
- **Never launch the app**: Only build to validate - let the user launch and test the app
- Clean build artifacts: Use `mcp__XcodeBuildMCP__clean` when needed
- Discover project structure: Use `mcp__XcodeBuildMCP__discover_projs`

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
- **Target iOS 26+**: SwiftUI + TextKit 2 + SwiftData
- **Core components**: MagneticTextView, Version Timeline, Branch System
- **Data flow**: SwiftData models → @Query in views → VersionController for mutations → auto-save
- **No manual file I/O**: All persistence via SwiftData ModelContainer
- **Branch creation**: Explicit user action, AI variations, or major rewrites
- Read `README.md` and `CLAUDE.md` before touching editor, versioning, or gesture code

## Security & Configuration Tips
- Do not commit secrets or tokens. Keep third-party assets/fonts licensed and in `Revise/Fonts/`.
- Maintain accessibility (VoiceOver) and performance budgets when modifying UI/gestures.

