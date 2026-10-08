# Postino

A native macOS HTTP client built with Swift and AppKit. No Electron, browser runtime, account, cloud sync, or third-party dependencies. Requires macOS 13 or later.

## Run

Open `build/Release/Postino.app`. To rebuild with Apple's Command Line Tools:

```sh
./scripts/build.sh
open build/Release/Postino.app
```

The build script produces an optimized app for the current Mac and signs it locally. Distribution to other Macs requires Developer ID signing and notarization. `Package.swift` is also provided for Xcode/SwiftPM development; the direct build works independently of SwiftPM's manifest libraries.

## Use

- Select a saved request or create one with **⌘N**.
- The request editor opens on **Body**, with live JSON syntax highlighting. Enter a URL, select an HTTP method, edit the body, parameters, headers, or authentication, then **⌘Return** to send. The Send button becomes Cancel while receiving a response.
- **⌘S** saves the current request. New requests go into the selected collection or folder; edits remain drafts until saved.
- Right-click a collection or folder for **Add request** and **Add folder…**. Drag requests or folders onto a collection/folder to move them, or between rows to change their order. Moves save automatically and preserve open drafts.
- **⌘I** imports one or more Postman collection or environment JSON files. Choose an environment in the top-right menu. Manage its variables with the adjacent sliders button or **⌘E**.
- **⇧⌘E** exports the selected collection as Postman Collection v2.1 JSON. The environment editor has its own Export button. Both formats can be imported into Postman.
- **⇧⌘S** saves the complete original response to a file. **Copy body** copies the complete active raw or formatted response. **⌘F** opens the native Find bar in either body editor; **⌘G** / **⇧⌘G** find the next/previous match. Response Find searches the whole file through a bounded chunk cache and sparse UTF-16 index, with replacement disabled. The request editor supports native Find and Replace.

## Large JSON

Responses stream to disk as they arrive. The native editor scrolls through a sliding UTF-8 window of at most 512 KiB. It reads ahead from disk as you scroll and releases text behind you. Command–Up/Down jumps to the start/end; the response search box scans the complete file and selects the exact match. There are no page controls. Pretty JSON creates a formatted file in the background, with bounded read/write buffers rather than parsing an entire object graph. Integer digits are preserved exactly. JSON responses under 2 MB are formatted automatically. Larger responses open raw; choose Pretty JSON when needed.

For very large request payloads, select **Body → Binary file → Choose file**, then set the appropriate Content-Type header. Binary uploads stream directly from disk. Multipart uploads also assemble and upload through a temporary file. In multipart rows, choose Text or File; the value for a File row is its local file path.

A local benchmark streamed 115,080,001 response bytes in 0.15 seconds and formatted them on disk in 4.88 seconds. The integration runner peaked at approximately 35 MB resident memory (23 MB memory footprint). This measures the native networking/formatting core, not the GUI; remote network and server performance will differ.

## Postman compatibility

Collection v2.0/v2.1 JSON and environment JSON are supported. Nested folders, descriptions, examples, collection/folder variables, disabled entries, inherited auth, and unknown metadata are preserved during exports. Environment variables override collection/folder variables. `{{variables}}` can be used in the URL, query parameters, headers, raw body, and credentials; missing or circular values produce an error before sending.

Postino executes Bearer, Basic, API key, and no authentication. Raw text/JSON, URL-encoded forms, multipart forms, and binary body files can be sent. Imported scripts and advanced auth configurations are preserved, but scripts, OAuth token acquisition, collection runners, GraphQL-specific editors, WebSockets, and Postman v3 YAML are not implemented. Unsupported authentication is reported before sending rather than silently sending the wrong request. TLS verification remains enabled; plain HTTP is allowed for local development.

Collection format reference: [Postman Collection v2.1 schema](https://schema.postman.com/json/collection/v2.1.0/docs/index.html). Environment format reference: [Postman environments](https://learning.postman.com/docs/use/send-requests/variables/managing-environments/).

## Local storage

To preserve existing data across the rename, normal app use continues to save the workspace at `~/Library/Application Support/Postauomo/workspace.json`, with owner-only file permissions. Environment values and credentials are stored locally, including in JSON exports. Responses are session-scoped, retained while tabs are open, and cleared on the next launch. History retains the latest 100 request snapshots, without response bodies.

`--demo` uses a separate `.demo` workspace beside this project and the local fixture API. It never imports your existing API files automatically.

## Verification

```sh
# Terminal 1
python3 scripts/fixture_server.py
# Terminal 2
./scripts/test.sh
```

`./scripts/test-ui.sh` checks compact layout, sidebar resizing, full method labels and body-format titles, JSON tokenization across large strings, cancellation, live highlighting without changing content or selection, flat controls and alternating bands, bounded response scrolling, UTF-8 continuity, and exact search selection. Native UI checks require access to the macOS window server.

`./scripts/test-sidebar.sh` exercises native sidebar creation, selection, filtered insertion positions, saving moved drafts, and workspace persistence in an isolated workspace.

`./scripts/test-find.sh` checks both native Find bars, request replacement, read-only response actions, Unicode positions, cross-chunk matching, full-file navigation and wraparound, and queries entered while indexing a 128 MB response. Set `PROFILE_FIND=1` to include memory and timing measurements.

`./scripts/test-editor.sh` checks all five shared table configurations, resizing, new-row focus, checkbox stability, inline deletion, and multipart file metadata.

`./scripts/test-tree.sh` checks moving and ordering collection entries, inheritance, draft preservation, cycle rejection, and Postman round trips.

The direct test runner checks import/export round trips, metadata preservation, auth, encoding, variable errors, streamed HTTP requests and multipart uploads, cancellation, exact JSON number preservation, UTF-8 page boundaries, search across read boundaries, and a response larger than 100 MB. XCTest counterparts are in `Tests/RelayCoreTests` for environments with XCTest installed.

Open request tabs keep an independent draft. A dot marks unsaved changes; Save updates the collection, and closing a modified tab or quitting offers Save, Discard, or Cancel. Collection exports contain saved entries. Click a collection or folder name to expand or collapse it. Drag the sidebar divider to resize the collection tree; its width is remembered. Import and export share one footer across the window. Rename saved requests using the tree context menu. Shared native buttons, menus, segmented controls and text inputs keep geometry consistent. Capsule buttons, dropdowns, request tabs and text inputs use solid flat fills with native keyboard and accessibility behavior. Alternating light and dark background bands separate sections; thin black dividers mark the draggable sidebar and request/response boundaries. Headers, parameters, forms, credentials, and environment variables use one configurable native table component with a top-right plus button and inline trash buttons. Header titles have no vertical separators. The environment table shares its window background. The borderless body editors share the input background, and all sections use consistent eight-point vertical gaps. Copy body shows a persistent “Copied!” confirmation.

The approved face-and-letter master is in `Resources/IconMaster.png`, with the transparent 40 pt sidebar cutout in `Resources/Logo.png`. `Resources/DockIcon.png` is the square, 1024 px source artwork; macOS 26 icon services apply the system mask, margins, and material. The Dock uses the ICNS declared in the bundle, and About loads that multiresolution resource directly. Run `./scripts/build-icon.sh` to regenerate `Resources/PostinoFace.icns`, including all 16–1024 px standard and Retina representations. The image generation prompt is in `Resources/DockIcon.prompt.md`. The shared green UI accent is sampled from the logo, with darker text variants for contrast on light backgrounds.
