# Mac, iPad, and iPhone plan

Status: planning only · 2026-11-16

## Decision

Make this a native Apple-family product with one repository and shared document logic. Ship the Mac app first, then a universal iPad/iPhone app. Keep the same ordinary `.tex`, `.md`, `.bib`, image, and PDF files across devices. Editing, Markdown preview, and LaTeX compilation must work without an account or network connection on every device before that device is advertised as fully supported.

Apple supports shared SwiftUI code across macOS, iPadOS, and iOS, while recommending separate targets when platform-specific APIs differ substantially. That fits this app: the Mac editor uses AppKit and launches `latexmk`; iPad/iPhone use UIKit text editing and need an embedded TeX engine. Share file models, document parsing, diagnostics, command semantics, and tests, with a macOS app target and one universal iOS/iPadOS target. [Apple multiplatform guidance](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target), [AppKit text view](https://developer.apple.com/documentation/appkit/nstextview), [UIKit text view](https://developer.apple.com/documentation/uikit/uitextview).

## Device experience

| Device | Workspace and layout | Default local action |
| --- | --- | --- |
| Mac | Several folder windows; file tree, source, PDF/Markdown preview, problems | `.tex` via installed `latexmk`; `.md` via native Markdown renderer |
| iPad | Files-app folder/project access; sidebar and resizable source/preview split; external keyboard; multiple windows where supported | `.tex` via embedded on-device engine after feasibility gate; `.md` via native renderer |
| iPhone | Files-app folder/project access; one focused source, preview, or problems screen at a time | Same on-device TeX and Markdown actions as iPad, with compact navigation |

Apple's `WindowGroup` supports multiple windows on macOS and iPadOS; iPad multiwindow requires the app's multiple-scenes setting. [WindowGroup](https://developer.apple.com/documentation/SwiftUI/WindowGroup). iPhone uses the same documents and actions, with a narrower presentation rather than a compressed desktop split.

## Files and cross-device continuity

Use the Files app/document picker on iPhone and iPad. Hold access to user-selected folders with security-scoped URLs and release access when finished. Projects can stay entirely on-device or in a user-chosen Files provider such as iCloud Drive; there is no required account or proprietary sync server. Treat provider changes like external edits and surface conflicts before overwriting a dirty buffer. [Apple file importer](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aoncompletion%3A%29), [security-scoped URLs](https://developer.apple.com/documentation/foundation/nsurl/).

For a mobile build, copy the selected project into an app-private temporary build folder while preserving relative paths, then compile that snapshot. Keep generated logs and PDFs out of the user's Files folder until they choose Export. This prevents partial build artifacts from appearing in a synced folder and lets the build finish if a provider changes its files mid-run. Generated PDFs and build logs are outputs, not a new project format. Any cloud Files provider may need network access to transfer changes between devices, but an already-local project must remain editable and buildable offline.

## Mobile LaTeX compiler gate

The Mac's `Process` + `latexmk` approach does not transfer directly to iPhone/iPad. Offline LaTeX on those devices is possible: Texifier documents an onboard iPhone/iPad TeX compiler and offline PDF output. Its engine and package behavior also show why a mobile compiler is substantial product work. [Texifier iOS typesetting](https://www.texifier.com/docs/apps/typesetting?platform=ios), [Texifier engine notes](https://www.texifier.com/docs/tutorials/tex/typesetters/external).

**First candidate:** compile Tectonic as an in-process iOS framework with a fixed TeX resource bundle and a small Swift bridge. Tectonic describes its engine as embeddable, and an independent project demonstrates an offline iOS XCFramework with bundled resources. Use that project as implementation evidence, not as an unreviewed binary dependency. Tectonic's top-level code uses MIT terms, while derived/native components and TeX resources carry additional licenses that must be audited before distribution. [Tectonic project](https://tectonic-typesetting.github.io/en-US/), [independent iOS integration](https://github.com/jeffasante/foqos-tectonic), [Tectonic license](https://github.com/tectonic-typesetting/tectonic/blob/master/LICENSE).

Build a throwaway iOS proof before locking in the engine. Test on a physical iPhone and iPad, in airplane mode, with the article, multi-file paper, image, bibliography, font and error fixtures. Check PDF output, diagnostics, cancellation, bundle size, memory, battery, missing-package behavior, and compilation time. If Tectonic fails the required corpus, compare a bundled WebAssembly TeX engine; do not switch to cloud compilation by default. Tectonic's XeTeX-based behavior may differ from a Mac project's selected pdfLaTeX/LuaLaTeX path, so record unsupported documents instead of claiming full parity. [SwiftLaTeX WebAssembly engines](https://github.com/SwiftLaTeX/SwiftLaTeX).

Bundle executable engine code and the core TeX resources with the app and keep shell escape off. Do not download new executable functionality or quietly send projects to a server; Apple's App Review guideline 2.5.2 constrains downloaded code and app-contained behavior. [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). A cloud or Mac-companion compiler would be a separately labeled optional feature only if the user later asks for it; it is not the default mobile build path.

## Release gates

1. **Mac:** complete the existing local edit/build/preview release and keep shared file/document logic free of AppKit-only assumptions.
2. **Mobile foundation:** universal iPad/iPhone target opens and saves ordinary project folders through Files; renders Markdown and displays existing PDFs; passes conflict and offline tests.
3. **Mobile compiler proof:** physical devices compile the fixture corpus fully offline with an embedded engine. Document unsupported packages and reject any silent server fallback.
4. **Mobile release:** native iPad and iPhone layouts, accessibility, external keyboard support, cancellation, file-provider recovery, TestFlight and App Store review. Only claim full LaTeX support after gate 3 passes. TestFlight/App Store distribution requires an Apple Developer Program team. [Apple distribution guidance](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/).

The two app targets share the product name and visual mark, with platform-specific icon exports. Mac remains useful if the mobile compiler gate takes longer than planned.

## Local development status

Xcode 27.2 on this Mac provides macOS, iOS, and iOS Simulator SDKs. Available simulator profiles include iPhone and iPad models. This verifies the development environment can start the mobile target; it does not replace the physical-device, offline compiler and App Store checks above. No mobile app target or engine proof has been built yet.
