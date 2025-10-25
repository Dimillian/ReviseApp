# Claude Development Guide for Revise

## Project Snapshot

Revise is an iOS 26+ writing companion built with SwiftUI, SwiftData, and Apple’s on-device Foundation Models. The app treats every edit as a version, lets writers branch into alternate drafts, and surfaces AI-assisted wording suggestions when contextually relevant. The shipping experience consists of a drafts list that seeds new documents with AI-generated titles, a detail editor with an always-available version timeline, and a zoomable branch graph for exploring divergent ideas.

## App Entry & Navigation Flow

- `ReviseApp` hosts a single `WindowGroup` backed by a SwiftData `ModelContainer` for `Document`, `Branch`, and `Version` models. The container is attached at the scene level so every screen can access the same `ModelContext`.
- Before presenting the main UI, the app checks `SystemLanguageModel.default.isAvailable`. If the on-device large language model is unavailable the app renders `UnavailableView`; otherwise it shows a `NavigationStack` with the documents list.
- `DocumentsListView` queries documents with `@Query(sort: \Document.lastEdited, order: .reverse)` and pushes `EditorView` for document navigation using value-based `NavigationLink`s.

## Data Layer

SwiftData models live in `Revise/Models` and define all persisted state:

- **Document** – uniquely identified (`@Attribute(.unique)`), stores title, last edit date, and the currently selected branch. Owns branches with cascade deletion.
- **Branch** – uniquely identified, linked to its `Document`, tracks creation timestamp, optional parent branch, optional `baseVersion`, ordered versions, and the branch’s active version. The static `Branch.main` constant labels the initial branch.
- **Version** – uniquely identified snapshot of text. Records timestamp, body text, change kind (`manual`, `synonym`, `ai`, `undo`, `redo`), counts, caret position, selected/highlighted ranges, and optional synonym or AI metadata. Convenience initialisers compute counts and range metadata.

Relationships are declared with SwiftData annotations so inverse lookups and cascade deletes happen automatically. All persistence goes through the injected `ModelContext`; there is no manual file or JSON storage.

## Controllers & Business Logic

- **VersionController** (`Revise/Version/VersionController.swift`)
  - Owns a `Document` reference plus an optional `ModelContext` (set from the view) to save mutations.
  - Maintains coalesced manual edits by reusing the latest version when changes arrive within a 2s window.
  - Limits per-branch history to 100 versions, pruning the oldest entries beyond the cap.
  - Supports undo/redo, arbitrary navigation, branch creation (cloning the current version into the new branch), branch switching, renaming, and deletion (except the `main` branch).
  - Generates data for branch graph visualisation: preview strings, diff highlights, and adjacency edges.

- **EditorController** (`Revise/Editor/EditorController.swift`)
  - Bridges the SwiftUI view to the underlying `UITextView` (`MagneticTextView`). Tracks the live `UITextView`, handles word selection, restores versions, and coordinates with `VersionController`.
  - Debounces edits (500ms) before adding a version, computes changed ranges for highlight previews, and requests title updates from the AI `Thesaurus`.
  - Manages the custom synonym workflow: when a single word is selected it suppresses the default menu, queries synonyms, and builds a custom `UIEditMenu` populated with AI responses. Applying a synonym records a `.synonym` version and highlights the replaced text.
  - Exposes undo/redo/branch creation helpers used by the toolbar menu.

- **Managers** (`Revise/Editor/Managers`)
  - `TextDiffManager` computes changed ranges and word counts for versioning and preview diffing.
  - `HighlightManager` centralises highlight styling when restoring historical versions.
  - `SynonymManager` wraps async loading state and menu construction for the synonym experience.

## Editor Experience

`EditorView` orchestrates the editing surface:

- Uses `MagneticTextEditor`, a `UIViewRepresentable` wrapper, to provide single-tap word selection, intrinsic content sizing, and typewriter styling.
- Tracks timeline visibility via `TimelineViewState` (`hidden`, `visible`, `expanded`). Users can toggle states by tapping the title/subtitle or by horizontal drags on the editor surface. The timeline itself is always vertical and supports scrub gestures plus tap-to-jump.
- Captures pinch gestures: shrinking the editor below 0.85 scale reveals the `BranchGraphView`. Releasing the gesture either snaps back to the editor or settles into a 0.75 zoomed-out graph state with haptic feedback.
- When the branch graph is visible, it renders branch nodes positioned by hierarchy, draws curved edges, and allows tapping nodes to switch branches. Nodes display AI/synonym badges and diff-aware previews computed by `VersionController`.
- The toolbar menu provides branch creation (AI-titled), branch switching, undo/redo, and sharing.

## AI & Language Model Integration

- The `Thesaurus` type (in `Revise/AI/Thesaurus.swift`) wraps `LanguageModelSession` from the Foundation Models framework.
- It pre-warms a session on init and exposes helpers to:
  - Propose synonyms for a selected word given sentence context (used by `SynonymManager`).
  - Suggest document titles for new drafts and new branches.
  - Generate inline document titles when content changes to keep the navigation title fresh.
- Because these calls rely on `SystemLanguageModel`, the app gates the editor UI when the model is unavailable.

## UI & Design System

- Semantic colours live in `Revise/DesignSystem/Color.swift` as dynamic Light/Dark-aware values with convenience aliases for SwiftUI `ShapeStyle` usage.
- Typography is defined in `Revise/DesignSystem/Font.swift` via `Font.literata` and `Font.inter` helpers. UIKit components manually request the same font names to keep parity with SwiftUI.
- Default editor appearance: Literata at large sizes for body text, Inter for chrome and metadata, warm gold caret (`Color.successGold`) for the typewriter feel.

## Document List Experience

- `DocumentsListView` shows each document’s title plus relative `lastEdited` time, word/version/branch counts, and routes selection into the editor.
- Creating a new document spins up a task that requests an AI-generated two-word title, inserts a main branch with an empty seed version, and pushes straight into the editor.
- Deleting uses SwiftData cascade rules to clear branches and versions automatically.

## Build, Test, and Development Workflow

- Use the MCP Xcode build tools for validation:
  - `mcp__XcodeBuildMCP__discover_projs` to inspect schemes.
  - `mcp__XcodeBuildMCP__build_sim` to compile against the iOS Simulator SDK.
  - `mcp__XcodeBuildMCP__clean` when a clean build is required.
- Run logic tests with the default `ReviseTests` target and UI flows in `ReviseUITests` (both XCTest-based). Keep tests deterministic and focused on versioning, diffing, and gesture behaviours.
- Maintain SwiftUI’s @Observable-driven architecture (no MVVM layers). Shared state lives in observables injected via environment, while view-local state remains in `@State`.
- Enforce Swift style conventions: two-space indentation, PascalCase types, lowerCamelCase members, and files named after the primary type.

## Accessibility & Product Expectations

- VoiceOver should narrate timeline entries, branch tiles, and synonym menus with meaningful labels.
- Keep animations purposeful and lightweight: timeline transitions use `.bouncy`, graph reveal uses spring animations, and haptic feedback punctuates important state changes.
- Preserve non-destructive editing guarantees: every text mutation should either coalesce or produce a new `Version` so history always matches what the user typed or accepted from AI.

## Security & Asset Handling

- Do not commit secrets or unlicensed assets. Custom fonts are shipped inside `Revise/Fonts/` and referenced by name.
- All AI prompts stay on-device through Foundation Models—no network calls or external dependencies.
