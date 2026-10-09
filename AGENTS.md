# Working on Postino

This document is the technical reference and working guide for this repository. Keep `README.md` short and aimed at people discovering and using the app; put architecture, implementation constraints, build instructions, tests, and maintenance details here. Follow explicit user instructions when they change the product requirements, and update this guide when the implementation changes.

## Product and scope

Postino is a native, local macOS REST client built with Swift, Foundation, and AppKit. Its priorities are a simple interface, Postman collection/environment interchange, responsive editing, and practical handling of very large JSON responses. There is no browser runtime, account system, cloud sync, or third-party runtime dependency.

The app name is **Postino**. Earlier names include Postauomo and Relay. Several identifiers intentionally retain those names for data compatibility; do not perform a blanket rename.

## Repository map

| Location | Responsibility |
| --- | --- |
| `Sources/Postino/main.swift` | App lifecycle, menus, keyboard shortcuts, About panel, quit confirmation. |
| `Sources/Postino/MainWindow.swift` | Window composition, request tabs, draft coordination, send/cancel, response presentation, import/export, clipboard feedback. |
| `Sources/Postino/Components.swift` | Shared native buttons, popup menus, segmented controls, colors, layout helpers, and request tabs. |
| `Sources/Postino/ControlBar.swift` | Background bands, flat capsule surfaces, control chrome, centered tree cells, resize-divider drawing. |
| `Sources/Postino/TextInputs.swift` | Shared text/search fields and native field-editor positioning. |
| `Sources/Postino/PairEditor.swift` | Configurable table editor for headers, parameters, environments, forms, and credentials. |
| `Sources/Postino/CodeEditor.swift` | Native text editor, JSON tokenization/highlighting, selection callbacks, and Find routing. |
| `Sources/Postino/ResponseReader.swift` | Bounded UTF-8 response viewport, scrolling, seeking, and JSON context. |
| `Sources/Postino/ResponseFind.swift` | Full-file read-only native Find client and sparse UTF-16 search index. |
| `Sources/Postino/CollectionSidebar.swift` | Collection tree context menus, creation, selection, drag/drop, and insertion mapping. |
| `Sources/Postino/Environments.swift` | Environment-management window and variable editing. |
| `Sources/Postino/Workspace.swift` | Workspace persistence, history, storage migration, demo mode, and response cleanup. |
| `Sources/RelayCore/Models.swift` | Postman models, unknown metadata preservation, variables, and JSON interchange. |
| `Sources/RelayCore/RequestDraft.swift` | Independent open drafts, dirty-state detection, and save snapshots. |
| `Sources/RelayCore/CollectionTree.swift` | Tree moves, ordering, cycle prevention, and inheritance refresh. |
| `Sources/RelayCore/HTTP.swift` | Variable resolution, request/auth/body construction, streamed transfers, and cancellation. |
| `Sources/RelayCore/ResponseFile.swift` | Buffered disk operations, JSON formatting, UTF-8 paging helpers, and byte search. |
| `Tests/RelayCoreTests/RelayCoreTests.swift` | XCTest counterparts for core behavior. |
| `scripts/` | Direct builds, regression runners, local fixture API, and icon generation. |
| `Fixtures/` | Postman collection/environment samples. |
| `Resources/` | Approved logo, Dock artwork, multiresolution icon, and design prompt. |
| `Info.plist` | App identity, versions, minimum macOS, icon declaration, and transport settings. |
| `.github/workflows/release.yml` | Manually triggered macOS build, UI checks, packaging, and GitHub release creation. |

## Build and toolchain

Run commands from the repository root. The canonical local and release build is:

```sh
./scripts/build.sh
open build/Release/Postino.app
```

Pinned versions live in `scripts/toolchain-versions.sh`:

- Xcode **26.4.1**, or matching Apple Command Line Tools.
- Apple Swift **6.3.1**, compiled in Swift 5 language mode.
- macOS SDK **26.4**. The installed tools may report 26.4.1; the SDK settings and Mach-O linked version are 26.4.
- Deployment target **macOS 13.0**. The build SDK and the minimum runtime version are separate settings.

For a full Xcode installation, select it for the command without changing the system-wide developer directory:

```sh
DEVELOPER_DIR=/Applications/Xcode_26.4.1.app/Contents/Developer ./scripts/build.sh
```

The script resolves `swiftc` through `xcrun`, explicitly selects the SDK, and verifies the compiler version before compiling. It builds an optimized `RelayCore` dynamic library and the app executable, copies resources, applies ad hoc signatures, and copies the bundle to the release directory.

Outputs:

- `build/Postino.app`: development bundle.
- `build/Release/Postino.app`: release bundle and normal handoff path.
- `build/modules/RelayCore.swiftmodule`: module used by direct test runners.
- `.build/ModuleCache`: compiler cache.
- `Contents/Resources/BuildInfo.json` inside each bundle: SDK, compiler version, architecture, and deployment target.

Builds target the current machine's architecture. The release workflow currently produces an Apple Silicon app; these are not universal binaries. `Package.swift` supports Xcode/SwiftPM development, but the direct build avoids problems with mismatched SwiftPM manifest libraries on Command Line Tools installations.

### SDK-dependent appearance

AppKit can select different control artwork and sizing based on the SDK recorded in the executable, even when both apps run on the same macOS version. An older `macos-14` runner previously produced legacy rectangular segmented controls while the local SDK 26.4 build produced capsules.

Preserve these safeguards:

- Keep local and CI versions synchronized through `scripts/toolchain-versions.sh`.
- Pass the SDK explicitly to the compiler and the SDK/deployment versions explicitly to the linker with `-platform_version`.
- Check `LC_BUILD_VERSION` in both the executable and `libRelayCore.dylib`. Some Command Line Tools drivers otherwise record the deployment target as the linked SDK when `-sdk` is explicit.
- Keep the native UI regression runner on the same SDK/linker settings.
- Keep the runtime availability guard around macOS 26 APIs such as `borderShape`. An availability check does not make an API visible to an older build SDK.

Do not resolve missing SDK APIs merely by removing native styling or allowing CI to use its default toolchain. When changing pinned versions, rebuild and visually check the native controls first.

```sh
xcrun vtool -show-build build/Release/Postino.app/Contents/MacOS/Postino
xcrun vtool -show-build build/Release/Postino.app/Contents/Frameworks/libRelayCore.dylib
codesign --verify --deep --strict build/Release/Postino.app
```

Both binaries should record SDK 26.4 and minimum macOS 13.0 with the current pins. Equivalent UI is expected on the same macOS version and appearance settings; this does not imply byte-identical bundles across different build machines.

## Release workflow

The owner launches **Actions → Release Postino → Run workflow** and supplies `release_name`. The selected ref is built. The workflow:

1. Checks out the source on `macos-26`.
2. Reads the shared version file and selects `/Applications/Xcode_26.4.1.app/Contents/Developer` through `DEVELOPER_DIR`.
3. Runs `scripts/build.sh` and `scripts/test-ui.sh`.
4. Verifies the release signature and prints `BuildInfo.json`.
5. Packages `Postino.app` with `ditto -c -k --sequesterRsrc --keepParent`.
6. Creates a release at the checked-out SHA with the supplied title, generated notes, an automatically generated `postino-<run-id>-<attempt>` tag, and the app ZIP attached.

`GITHUB_TOKEN` receives `contents: write` for release creation. The workflow does not need a personal access token. The pinned Xcode must exist on the runner; absence should fail clearly rather than silently fall back.

The current signatures are ad hoc, not Developer ID signatures, and the build does not notarize the app. Downloaded releases can trigger Gatekeeper on first launch. Proper distribution signing and notarization require separate Apple credentials and workflow changes; do not describe the current release as notarized.

## Verification

Rebuild before running regression scripts after source changes so the compiled `RelayCore` module and dynamic library are current. Choose the checks relevant to the changed behavior, and perform visual checks for UI changes. Documentation-only edits need link/content checks, not a full app rebuild.

### Core integration checks

Start the fixture API in one terminal, then run the checks in another:

```sh
python3 scripts/fixture_server.py
```

```sh
./scripts/build.sh
./scripts/test.sh
```

The fixture listens on `127.0.0.1:18765`. Core checks cover import/export metadata, inheritance, auth, encoding, variable errors, streamed HTTP requests, multipart uploads, cancellation, exact JSON numbers, UTF-8 boundaries, cross-buffer search, and responses larger than 100 MB. Keep fixture requests local and do not substitute real production APIs or credentials in tests.

### Focused regression runners

| Command | Coverage |
| --- | --- |
| `./scripts/test-ui.sh` | Native control geometry, capsule groups, flat surfaces, bands, sidebar resizing, method/body-format labels, JSON highlighting and cancellation, bounded scrolling, UTF-8 continuity, search selection, and copy feedback. |
| `./scripts/test-editor.sh` | All five shared table configurations, resizing, row focus, explicit addition, checkbox stability, inline deletion, and multipart file metadata. |
| `./scripts/test-sidebar.sh` | Native tree creation/selection, filtered insertion, saving moved drafts, and workspace persistence. |
| `./scripts/test-tree.sh` | Core moves/reordering, inheritance, draft preservation, cycle rejection, and Postman round trips. |
| `./scripts/test-find.sh` | Both native Find bars, request replacement, read-only response actions, UTF-16/UTF-8 mapping, cross-chunk matches, full-file navigation/wraparound, and queries entered while indexing a 128 MB response. |
| `PROFILE_FIND=1 ./scripts/test-find.sh` | The Find checks with timing and peak-memory measurements. |

XCTest equivalents are in `Tests/RelayCoreTests` for environments with a working XCTest/SwiftPM toolchain. The direct runners are the reliable path on the project's Command Line Tools setup.

Native AppKit checks require access to the macOS window server. A process abort in `RegisterApplication` before assertions run can indicate a sandbox/window-server restriction; inspect diagnostics and distinguish it from an application assertion failure. Core HTTP checks also require localhost network access.

The native Find tests and interactive Find share macOS's Find pasteboard. Do not run them concurrently. Clipboard-related checks preserve and restore pasteboard contents on normal completion; a crashed runner may not execute cleanup.

### Visual checks and isolated workspaces

Launch a test copy with `--demo` for manual UI work:

```sh
build/Release/Postino.app/Contents/MacOS/Postino --demo
```

Demo mode uses a `.demo` directory derived from the app bundle location: two containing directories above the bundle. `build/Release/Postino.app` uses `build/.demo`, while `build/Postino.app` uses the repository's `.demo`. Dedicated test bundles under `build/<check>/run/` use `build/<check>/.demo`. Demo defaults point to the local fixture API. Do not assume every copied bundle shares the same demo directory.

For visual changes, inspect narrow and wide windows, selected/unselected and disabled controls, focused inputs, and relevant menus or editors. Check dark/light appearance when colors change. Verify the packaged/extracted app when modifying release tooling, not only a development preview. Confirm the running process is the intended bundle and uses demo mode before interacting with its workspace.

Avoid launching a second normal app instance for checks: workspace initialization clears session response files. Never use the real workspace as disposable test data.

## Architecture and state

Keep transport and interchange logic in the Foundation-only `RelayCore` module, and native views/controllers in `Sources/Postino`. UI mutations belong on the main thread. Disk processing, formatting, indexing, and expensive highlighting should stay off the main thread.

Open tabs own independent `RequestDraft` instances. Editing a tab must not silently mutate a saved collection entry. `isDirty` drives the tab dot and Save state; save updates the collection, and closing a modified tab or quitting offers Save, Discard, or Cancel. Exports contain saved entries, so unsaved drafts are not implicitly exported.

Preserve request/node identity during moves. `CollectionTree.move` adjusts insertion indexes when moving within a container, prevents cycles, and refreshes inherited auth/variables. UI drop indexes must map correctly through filtered trees. Moving an open request must preserve its draft and future save destination.

`HistoryEntry` wraps history dictionaries in `NSObject` for the native outline/table data source. Preserve that stable object representation; passing unstable bridged dictionaries previously caused a history-tab crash.

Background jobs use cancellation objects and generation IDs. Cancel work when tabs/files change, and reject stale callbacks before modifying text, selections, response state, or temporary files.

## Large payloads and native Find

- `HTTPTransfer` writes incoming `URLSession` data directly to a response file, disables URL caching, and reports progress on the main thread. Do not collect a full response `Data` just to display it.
- `ResponseReader.Window` loads at most **512 KiB**, preserves UTF-8 boundaries, and slides through the file as the user scrolls. Command–Up/Down reaches the start/end. Preserve selection/scroll context when replacing the window.
- JSON highlighting operates on a viewport and carries string/escape context across disk windows. Use temporary attributes; highlighting must not change the source text, undo history, or selection.
- `ResponseFile.pretty` uses buffered reads/writes without creating an object graph or converting numeric tokens through `Double`. Preserve exact integer digits and numeric spelling. Cancellation removes partial output.
- JSON responses below **2,000,000 bytes** are formatted automatically when presented after a transfer; larger responses open raw and can be formatted on demand.
- Raw request text is held in memory. For very large uploads, Binary file mode streams a local file; multipart mode assembles a temporary upload file in bounded buffers and uploads it from disk.
- **Copy body** reads the complete active raw/formatted response on a worker and sends text to the clipboard. This operation necessarily materializes the complete text and is not a constant-memory operation. **Save response** exports the original response file.

Both body editors use the native in-window Find bar. Request Find uses the editable `NSTextView`; response Find uses `NSTextFinderClient` against the full immutable file and disables replacement. Find must cover the entire response, not just the displayed window.

`ResponseSearchDocument` builds a sparse UTF-16 index over UTF-8 chunks, maintains an open file descriptor, and caches only two chunks. File access is locked because AppKit can request strings on a worker thread. Use local autorelease pools around chunk reads/decoding to keep temporary allocations under control.

Preserve cross-chunk matches (`endsWithSearchBoundary = false`), Unicode offset mapping, next/previous/wrap behavior, and queries entered before indexing completes. The native finder receives the whole logical response range for full-file incremental counts; highlight geometry and drawing must be limited to the actual viewport. Translate global selections to the loaded window before revealing a match. Paint the selected match's actual glyphs in native Find indicators.

AppKit's full-file matching may allocate temporary memory proportional to the response size, even though the application's chunk cache and display are bounded. Do not claim constant-memory search or apply networking-core memory numbers to the GUI. Profile the relevant operation and distinguish peak RSS, memory footprint, response storage, and UI text layout.

## Postman interchange and request execution

Supported imports are Postman Collection v2.0/v2.1 JSON and environment JSON. Collection exports use v2.1. Preserve nested folders, descriptions, examples, collection/folder variables, disabled entries, inherited auth, and unknown original metadata during round trips.

Models retain `original`/`extra` dictionaries and update known fields rather than rebuilding entire documents from only UI-visible data. Local `_relayID` values preserve request identity in workspace snapshots and must not leak into external Postman exports. Regenerate derived URL components during export to avoid stale host/path/query data.

Variable precedence is collection → folder → selected environment. Resolve `{{variables}}` in URLs, query parameters, headers, bodies, and auth values. Missing variables and circular references must produce clear errors before a request is sent. Substitution precedes URL encoding; exports must retain unresolved placeholders.

Executed auth modes are no auth, Bearer, Basic, and API key in headers/query parameters. Executed body modes are raw text/JSON, URL-encoded form, multipart form, and binary file. Preserve multipart file paths, field types, content types, and extra imported metadata.

Imported scripts and advanced auth metadata are preserved but not executed. OAuth token acquisition, collection runners, dedicated GraphQL editors, WebSockets, and Postman v3 YAML are not implemented. Unsupported auth/body modes must report an error rather than silently sending a different request.

TLS verification remains enabled. Plain HTTP is allowed for local development. Reject header names/values containing newlines, and preserve multipart quoting/escaping and temporary-upload cleanup.

References: [Postman Collection v2.1 schema](https://schema.postman.com/json/collection/v2.1.0/docs/index.html) and [Postman environments](https://learning.postman.com/docs/use/send-requests/variables/managing-environments/).

## Persistence and compatibility

Normal storage remains `~/Library/Application Support/Postauomo/workspace.json`. If that directory is absent and legacy `Relay` storage exists, `Workspace` copies it to the newer location and falls back to legacy storage if copying fails. Keep this migration behavior intact.

- Workspace snapshots contain collections, environments, selected environment, and the latest **100** history entries.
- Saves are atomic, serialized on a utility queue, and normally debounced by **0.4 seconds**. Immediate saves flush through that queue.
- The workspace file uses permissions **0600**, and the workspace directory is created with **0700** permissions.
- Environment values and credentials are stored locally in JSON, including exports. There is no Keychain-backed secret store; do not describe these values as encrypted.
- Responses live under the workspace's `Responses` directory and are session-scoped. They are retained while tabs need them and cleared during the next workspace initialization. History does not retain response bodies.
- Stable compatibility identifiers include bundle ID `app.postauomo.http`, the `RelayCore` module, `_relayID`, and `PostauomoMain`/`PostauomoSidebarWidth` preferences.

Do not rename storage, identifiers, or preferences without implementing and verifying migration. Use sample credentials and isolated workspaces in diagnostics; avoid printing real environment values in logs or screenshots.

## UI conventions

The current design is **flat**, with solid fills and rounded capsule controls. Earlier glass experiments were superseded; do not reintroduce glass containers or effects as a generic modernization step.

- Reuse `RelayButton`, `RelayPopup`, `RelaySegments`, shared inputs, `ControlSurface`, and `PairEditor` rather than creating per-screen variants.
- Common controls are **28 pt** high with **14 pt** capsule radii and **8 pt** vertical gaps. Maintain consistent inset/gap relationships within each band.
- Alternate `bandLightColor` and `bandDarkColor` for major vertical sections. Ordinary horizontal separator rules were removed; thin draggable split dividers remain.
- Buttons use text or an icon, not both. Primary Send text is opaque white. Keep keyboard behavior, focus rings, tooltips, and accessibility labels intact.
- Request tabs contain full method names, a request title, a dirty dot when needed, and an internal close button. Rename through the context menu; do not restore the separate rename bar.
- Body is the first/default request section. Body-format popups must fit every title without truncation.
- JSON editors have no border and share `inputBackgroundColor` with text inputs.
- Keep text and placeholders vertically centered before and after focus. Table value fields and row actions must remain within the viewport at narrow sizes.
- `PairEditor` owns shared row addition/removal: a small plus button at the top right, inline trash buttons, and focus of a newly added row. Toggling enabled state must not add rows. Preserve empty-table behavior and last-row deletion.
- Table headers have no vertical separators. Environment tables match their surrounding window background.
- Collection/folder names toggle expansion along with disclosure arrows. Do not add folder icons back to the tree. Keep sidebar segments fitted to their contents, with vertically centered selected rows.
- One shared footer holds import/export actions. Avoid collection/request counters, paging controls, and redundant response-format labels.
- **Copy body** provides a visible, accessible “Copied!” confirmation for approximately **2.5 seconds**, rather than only a momentary button state change.
- Sidebar width is remembered. Both sidebar/main and request/response splits must remain draggable.

Native menu shortcuts include ⌘N (new request), ⌘S (save), ⌘Return (send), ⌘I (import), ⇧⌘E (export collection), ⇧⌘S (save response), and **⌥⌘E** (manage environments). Preserve native Find shortcuts: ⌘F, ⌘G/⇧⌘G, ⌘E (use selection for Find), and ⌥⌘F (Find and Replace where editable).

## Branding and icons

The approved logo is a cartoon postman's face and gloved hand holding a letter. Preserve the matte blue cap, large mustache, clean cheek, and separation between the mustache and envelope. Use the approved assets rather than generating a replacement during unrelated work.

- `Resources/IconMaster.png`: approved face-and-letter master.
- `Resources/Logo.png`: transparent sidebar/header artwork, displayed at 40 pt in the app.
- `Resources/DockIcon.png`: 1024 px square source for the Dock icon.
- `Resources/PostinoFace.icns`: active multiresolution app icon declared in `Info.plist`.
- `Resources/DockIcon.prompt.md`: logo-generation/design notes.

Run `./scripts/build-icon.sh` to regenerate all standard/Retina icon representations from 16–1024 px. macOS 26 icon services apply the system mask, margins, and material. About loads the multiresolution icon directly. Validate the actual Dock result when changing artwork or packaging; a cached old icon or a low-resolution representation can differ from the resource preview.

The UI accent is the approved green (`0, 183/255, 115/255`), with darker ink variants for contrast on light backgrounds. Keep artwork and functional UI colors consistent.
