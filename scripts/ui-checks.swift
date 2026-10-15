import AppKit
import RelayCore

private final class UIReleaseProtocol: URLProtocol {
    static var body = Data()
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct UIChecks {
    static func main() throws {
        _ = NSApplication.shared
        let json = #"{"name":"mail \"boy\" 📨","value":-12.5e+3,"enabled":true,"nothing":null}"# as NSString
        let tokens = JSONSyntax.tokens(in: json, range: NSRange(location: 0, length: json.length))
        precondition(tokens.filter { $0.kind == .key }.count == 4)
        precondition(tokens.filter { $0.kind == .string }.count == 1)
        precondition(tokens.filter { $0.kind == .number }.map { json.substring(with: $0.range) } == ["-12.5e+3"])
        precondition(tokens.filter { $0.kind == .literal }.count == 2)
        let huge = ("{\"long\":\"" + String(repeating: "abc ", count: 1_000_000) + "\",\"tail\":false}") as NSString
        let tail = NSRange(location: huge.length - 30, length: 30)
        let tailTokens = JSONSyntax.tokens(in: huge, range: tail)
        precondition(tailTokens.first?.kind == .string && tailTokens.last?.kind == .literal, "Viewport lexing must carry string state across large prefixes")
        precondition(tailTokens.allSatisfy { NSIntersectionRange($0.range, tail) == $0.range })
        precondition(JSONSyntax.tokens(in: huge, range: tail, cancelled: { true }).isEmpty)
        let continued = #"continued text", "key":true}"# as NSString
        let continuedTokens = JSONSyntax.tokens(in: continued, range: NSRange(location: 0, length: continued.length), initiallyInString: true)
        precondition(continuedTokens.map(\.kind) == [.string, .key, .literal], "Chunk highlighting carries JSON string state")
        let clipboard = NSPasteboard.general
        let savedClipboard = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let saved = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
            return saved
        } ?? []
        defer { clipboard.clearContents(); if !savedClipboard.isEmpty { clipboard.writeObjects(savedClipboard) } }
        let controller = MainWindow()
        let window = controller.window!
        func layout() { window.contentView!.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12)); window.contentView!.layoutSubtreeIfNeeded() }
        layout()
        let split = controller.sidebarSplit.splitView
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        precondition(controller.tabs.isEmpty && controller.current == nil && controller.editorWorkspace.isHidden && !controller.emptyWorkspace.isHidden, "Startup shows the empty workspace with no automatic request")
        precondition(controller.readyIllustration != nil && controller.workspaceIllustration.image === controller.readyIllustration, "The ready-to-go postman is packaged and displayed")
        precondition(controller.workspaceTitle.stringValue == "Welcome!" && controller.workspaceMessage.stringValue == "Create or open a request to get started." && controller.workspaceNewRequest.title == "New request", "Empty workspace uses the requested title, description and action")
        let workspacePlaceholder = descendants(controller.emptyWorkspace).first { $0.identifier?.rawValue == "workspacePlaceholder" }!
        let saveMenu = NSMenuItem(title: "Save Request", action: #selector(MainWindow.saveRequest), keyEquivalent: "s")
        precondition(!controller.validateMenuItem(saveMenu) && !controller.send.isEnabled && !controller.copyRequest.isEnabled, "Request actions are disabled without an open request")
        for width: CGFloat in [980, 1200] {
            window.setContentSize(NSSize(width: width, height: 700)); split.setPosition(330, ofDividerAt: 0); layout()
            let box = workspacePlaceholder.convert(workspacePlaceholder.bounds, to: controller.emptyWorkspace)
            precondition(abs(box.midX - controller.emptyWorkspace.bounds.midX) < 1 && abs(box.midY - controller.emptyWorkspace.bounds.midY) < 1 && controller.emptyWorkspace.bounds.insetBy(dx: 15, dy: 15).contains(box), "Empty workspace is centered and fits at narrow and wide sizes")
            let image = controller.workspaceIllustration.convert(controller.workspaceIllustration.bounds, to: controller.emptyWorkspace)
            let title = controller.workspaceTitle.convert(controller.workspaceTitle.bounds, to: controller.emptyWorkspace)
            let message = controller.workspaceMessage.convert(controller.workspaceMessage.bounds, to: controller.emptyWorkspace)
            let button = controller.workspaceNewRequest.convert(controller.workspaceNewRequest.bounds, to: controller.emptyWorkspace)
            precondition(image.minY > title.maxY && title.minY > message.maxY && message.minY > button.maxY && abs(button.midX - box.midX) < 1, "Title, description and New request button are centered below the artwork")
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                window.appearance = NSAppearance(named: appearance); layout()
                let view = window.contentView!.superview!
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/workspace-empty-\(Int(width))-\(suffix).png"))
            }
        }
        window.appearance = nil
        controller.workspaceNewRequest.performClick(nil); layout()
        precondition(controller.tabs.count == 1 && controller.current?.draft.source == nil && controller.emptyWorkspace.isHidden && !controller.editorWorkspace.isHidden && controller.send.isEnabled, "Empty-state action opens a normal new request")
        controller.closeCurrentTab(); layout()
        precondition(controller.tabs.isEmpty && controller.current == nil && !controller.emptyWorkspace.isHidden && controller.editorWorkspace.isHidden && window.attachedSheet == nil, "Closing the final blank request returns to the empty workspace")
        let firstRequest = controller.store.collections[0].allRequests[0]
        controller.open(firstRequest); layout()
        precondition(controller.emptyWorkspace.isHidden && controller.current?.draft.source === firstRequest, "Opening a collection request replaces the empty state")
        controller.closeCurrentTab(); layout()
        precondition(controller.tabs.isEmpty && controller.current == nil && !controller.emptyWorkspace.isHidden, "Closing the final stored request never creates a placeholder request")
        controller.open(firstRequest); layout()
        let placeholder = descendants(controller.emptyResponse).first { $0.identifier?.rawValue == "responsePlaceholder" }!
        precondition(controller.unsentIllustration != nil && controller.errorIllustration != nil, "Both response illustrations are packaged with the app")
        precondition(controller.emptyIllustration.image === controller.unsentIllustration && !controller.emptyIllustration.isHidden, "Unsent requests show the empty mailbox")
        precondition(!descendants(controller.emptyResponse).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("⌘") }, "Placeholder shortcut hints are removed")
        func checkPlaceholder() {
            let box = placeholder.convert(placeholder.bounds, to: controller.emptyResponse)
            precondition(abs(box.midX - controller.emptyResponse.bounds.midX) < 1 && abs(box.midY - controller.emptyResponse.bounds.midY) < 1, "Response artwork and text are centered as a group")
            precondition(controller.emptyResponse.bounds.insetBy(dx: 7, dy: 7).contains(box), "Placeholder fits inside the response pane")
            precondition(controller.emptyTitle.alignment == .center && controller.emptyMessage.alignment == .center, "Both text lines have centered alignment")
        }
        checkPlaceholder()
        precondition(controller.emptyMessage.frame.height < 20, "The short empty-state subtitle stays on one centered line")
        controller.current!.error = "The connection could not be completed. Check that the server is running and that the address and environment variables are correct. Then try sending the request again."
        controller.renderResponse(); layout(); checkPlaceholder()
        precondition(controller.emptyIllustration.image === controller.errorIllustration && !controller.emptyResponse.isHidden, "Errors show the fallen postman")
        precondition(controller.emptyMessage.frame.height > 20 && controller.emptyMessage.toolTip == controller.current!.error, "Long errors wrap, with full details available in a tooltip")
        let transfer = try HTTPTransfer(directory: controller.store.responses, completion: { _ in }, progress: { _ in })
        controller.current!.transfer = transfer; controller.renderResponse(); layout()
        precondition(controller.emptyIllustration.isHidden && controller.emptyTitle.stringValue == "Receiving response…", "Receiving retains progress text without empty or error artwork")
        controller.current!.transfer = nil; controller.current!.error = nil; controller.renderResponse(); layout()
        precondition(controller.emptyIllustration.image === controller.unsentIllustration && !controller.emptyIllustration.isHidden, "Returning to an unsent state restores the mailbox")
        let toolbar = window.toolbar!
        let actionViews = toolbar.items.compactMap(\.view)
        let headerDividers = descendants(window.contentView!).compactMap { $0 as? Surface }.filter { ["toolbarDivider", "footerDivider"].contains($0.identifier?.rawValue ?? "") }
        precondition(window.titleVisibility == .hidden && window.titlebarAppearsTransparent && window.toolbarStyle == .unified, "The native window buttons share one transparent unified toolbar")
        precondition(actionViews.count == 3 && actionViews.flatMap(descendants).compactMap { $0 as? RelayButton }.contains { $0.title == "New collection" }, "The unified toolbar retains creation and environment actions")
        precondition(!actionViews.flatMap(descendants).contains { $0 === controller.save }, "Save belongs beside Send, not in the window toolbar")
        precondition(!actionViews.flatMap(descendants).compactMap { $0 as? RelayButton }.contains { $0.title == "Check for updates" }, "Update checks belong in the macOS menu bar")
        let menuDelegate = AppDelegate(); menuDelegate.controller = controller; menuDelegate.makeMenu()
        let appMenu = NSApp.mainMenu!.items[0].submenu!
        precondition(appMenu.items.contains { $0.action == #selector(MainWindow.checkForUpdates) && $0.target === controller }, "The Postino system menu provides manual update checks")
        let fileMenu = NSApp.mainMenu!.items.first { $0.title == "File" }!.submenu!
        precondition(fileMenu.items.contains { $0.action == #selector(MainWindow.copyRequestAsCurl) && $0.keyEquivalent == "c" && $0.keyEquivalentModifierMask == [.command, .shift] }, "Copy as cURL has a native File-menu shortcut")
        let toolbarButtons = actionViews.flatMap(descendants).compactMap { $0 as? RelayButton }
        precondition(toolbarButtons.filter { ["New request", "New collection"].contains($0.title) }.allSatisfy { $0.isEnabled && $0.target === controller }, "Creation controls retain their enabled state and action targets in the toolbar")
        let originalName = controller.current!.request.name
        controller.current!.request.name = originalName + " modified"; controller.draftChanged(); toolbar.validateVisibleItems()
        precondition(controller.save.isEnabled, "Save enables for a modified draft")
        controller.current!.request.name = originalName; controller.draftChanged(); toolbar.validateVisibleItems()
        precondition(!controller.save.isEnabled, "Save disables again when the draft matches the collection")
        precondition(!descendants(split.arrangedSubviews[0]).contains { $0 is NSImageView || ($0 as? NSTextField)?.stringValue == "Postino" }, "Sidebar starts with navigation, without duplicate branding")
        precondition(split.arrangedSubviews.count == 2 && split.frame.height > 400, "Sidebar split content must be present")
        precondition(controller.requestSegment.selectedSegment == 0 && controller.requestHost.subviews[0].isHidden == false && controller.bodyHost.isDescendant(of: controller.requestHost.subviews[0]), "Body is first and selected by default")
        for width: CGFloat in [1200, 980, 1100] {
            window.setContentSize(NSSize(width: width, height: 760)); layout()
            checkPlaceholder()
            // AppKit can constrain the requested size to the current display's usable width.
            let contentWidth = window.contentView!.bounds.width
            let toolbarDivider = headerDividers.first { $0.identifier?.rawValue == "toolbarDivider" }!
            let dividerBox = toolbarDivider.convert(toolbarDivider.bounds, to: window.contentView)
            let close = window.standardWindowButton(.closeButton)!
            let closeBox = close.convert(close.bounds, to: window.contentView)
            precondition(closeBox.minY > dividerBox.maxY, "Native window buttons stay above the toolbar divider")
            let actionBoxes = actionViews.map { $0.convert($0.bounds, to: window.contentView) }
            precondition(actionBoxes.allSatisfy { $0.minY > dividerBox.maxY && $0.maxX <= contentWidth && $0.width > 0 }, "Toolbar actions fit above the content at every supported window width")
            precondition(actionBoxes[0].minX > closeBox.maxX && zip(actionBoxes, actionBoxes.dropFirst()).allSatisfy { $0.maxX < $1.minX }, "Window controls and toolbar actions never overlap")
            let copyBox = controller.copyRequest.convert(controller.copyRequest.bounds, to: window.contentView)
            let sectionsBox = controller.requestSegment.convert(controller.requestSegment.bounds, to: window.contentView)
            precondition(copyBox.minX > sectionsBox.maxX && copyBox.maxX <= contentWidth && controller.copyRequest.frame.height == 28, "Copy as cURL fits beside the request sections")
            let sendBox = controller.send.convert(controller.send.bounds, to: window.contentView)
            let saveBox = controller.save.convert(controller.save.bounds, to: window.contentView)
            precondition(abs(saveBox.minX - sendBox.maxX - 8) < 1 && abs(saveBox.midY - sendBox.midY) < 1, "Save sits immediately to the right of Send")
            precondition(headerDividers.allSatisfy { abs($0.frame.width - contentWidth) < 1 && $0.frame.height == 1 }, "Header and footer dividers span the whole window")
            split.setPosition(200, ofDividerAt: 0); layout(); let narrow = split.arrangedSubviews[0].frame.width
            precondition(controller.outline.tableColumns[0].width <= controller.outline.enclosingScrollView!.contentView.bounds.width + 1, "Tree column must fit a narrow sidebar")
            split.setPosition(330, ofDividerAt: 0); layout(); let wide = split.arrangedSubviews[0].frame.width
            precondition(wide - narrow > 100, "Sidebar must resize over its supported range: \(narrow) to \(wide), content \(contentWidth)")
            precondition(controller.outline.tableColumns[0].width <= controller.outline.enclosingScrollView!.contentView.bounds.width + 1, "Tree columns must stay within the sidebar")
            precondition(controller.bodyMode.frame.width >= controller.bodyMode.intrinsicContentSize.width - 1, "Body format titles must fit")
            for item in controller.bodyMode.itemTitles {
                let width = (item as NSString).size(withAttributes: [.font: controller.bodyMode.font!]).width
                precondition(width <= controller.bodyMode.frame.width - 30, "Every body mode must be legible")
            }
            controller.requestSegment.selectedSegment = 3; controller.requestSectionChanged(); layout()
            let authBox = controller.authMode.convert(controller.authMode.bounds, to: window.contentView)
            let authCopyBox = controller.copyRequest.convert(controller.copyRequest.bounds, to: window.contentView)
            precondition(authBox.maxX < authCopyBox.minX && authCopyBox.maxX <= contentWidth, "Authorization controls fit at every supported window width")
            controller.requestSegment.selectedSegment = 0; controller.requestSectionChanged(); layout()
        }
        let all = descendants(window.contentView!) + actionViews.flatMap(descendants)
        let resizeSplits = all.compactMap { $0 as? ResizeSplitView }
        precondition(resizeSplits.count == 2 && resizeSplits.contains { $0.isVertical } && resizeSplits.contains { !$0.isVertical }, "Both split boundaries use the shared resize component")
        let responseSplit = resizeSplits.first { !$0.isVertical }!
        let requestHeight = responseSplit.arrangedSubviews[0].frame.height
        controller.current!.error = String(repeating: "The server could not be reached. ", count: 8)
        controller.renderResponse(); responseSplit.setPosition(responseSplit.bounds.height - 250, ofDividerAt: 0); layout(); checkPlaceholder()
        precondition(controller.emptyIllustration.frame.height < 140 && controller.emptyIllustration.frame.height >= 24, "Artwork shrinks to retain readable error text in a short response pane: image \(controller.emptyIllustration.frame), pane \(controller.responseHost.frame), split \(responseSplit.arrangedSubviews.map(\.frame))")
        controller.current!.error = nil; controller.renderResponse(); responseSplit.setPosition(requestHeight, ofDividerAt: 0); layout()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                precondition(resizeSplits.allSatisfy { $0.dividerColor == controlFillColor }, "Both divider colors match buttons in light and dark appearance")
                precondition(headerDividers.count == 2 && headerDividers.allSatisfy { $0.color == controlFillColor }, "Header and footer borders match the resize dividers in either appearance")
            }
        }
        precondition(all.compactMap { $0 as? RelayButton }.allSatisfy { $0.title.isEmpty || $0.image == nil }, "Buttons must use text or icons, never both")
        let segments = all.compactMap { $0 as? RelaySegments }.first { $0 !== controller.requestSegment && $0 !== controller.responseSegment }!
        precondition(abs(segments.frame.width - segments.intrinsicContentSize.width) < 1, "Sidebar segments must fit their buttons")
        precondition(!(controller.folderCell("Folder", bold: false) is NSImageView))
        for method in ["GET", "POST", "PATCH", "DELETE", "OPTIONS", "PROPFIND"] {
            let request = RequestItem(); request.method = method
            let tab = RequestTabView(request: request, dirty: true, active: true, index: 0, target: controller)
            tab.frame.size = NSSize(width: 180, height: 28); tab.layoutSubtreeIfNeeded()
            let methodLabel = descendants(tab).compactMap { $0 as? NSTextField }.first!
            let textWidth = (method as NSString).size(withAttributes: [.font: methodLabel.font!]).width
            precondition(methodLabel.frame.width >= ceil(textWidth) + 4, "Full method names must fit in tabs")
        }
        let folderCell = controller.folderCell("Folder", bold: false) as! TreeCellView
        folderCell.frame = NSRect(x: 0, y: 0, width: 200, height: 26); folderCell.layoutSubtreeIfNeeded()
        precondition(abs(folderCell.content.frame.midY - folderCell.bounds.midY) < 1, "Folder labels are vertically centered in the selection row")
        let editor = controller.body
        editor.set(json as String, highlight: true); layout()
        editor.text.setSelectedRange(NSRange(location: 3, length: 2)); let selection = editor.text.selectedRange()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        precondition(editor.text.string == json as String && editor.text.selectedRange() == selection, "Highlighting preserves content and selection")
        let keyOffset = json.range(of: "name").location
        precondition(editor.text.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: keyOffset, effectiveRange: nil) != nil, "JSON keys receive live highlighting")
        editor.syntaxHighlighting = false
        precondition(editor.text.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: keyOffset, effectiveRange: nil) == nil, "Switching away from JSON clears highlighting")
        precondition(all.compactMap { $0 as? ControlSurface }.allSatisfy { !descendants($0).contains { $0 is NSVisualEffectView } }, "Flat control surfaces have no material or vibrancy views")
        if #available(macOS 26.0, *) {
            precondition(all.compactMap { $0 as? ControlSurface }.allSatisfy { !descendants($0).contains { $0 is NSGlassEffectView } }, "Flat control surfaces have no glass views")
            precondition(all.compactMap { $0 as? RelayButton }.allSatisfy { $0.bezelStyle != .glass && $0.cell is FlatButtonCell }, "Buttons use solid flat bezels")
            precondition(all.compactMap { $0 as? RelaySegments }.allSatisfy { $0.borderShape == .capsule }, "Selection groups keep capsule corners")
        }
        precondition(!all.compactMap { $0 as? NSBox }.contains { $0.boxType == .separator }, "Background bands replace horizontal separator lines")
        precondition(controller.tabScroll.backgroundColor == bandDarkColor && controller.tabScroll.contentView.drawsBackground && controller.tabScroll.contentView.backgroundColor == bandDarkColor, "Request tabs paint the darker band above the lighter request controls")
        let strip = controller.tabScroll, originalTabSize = controller.tabBar.frame.size
        controller.tabBar.setFrameSize(NSSize(width: strip.contentSize.width + 1000, height: 44))
        strip.contentView.scroll(to: NSPoint(x: 400, y: 0)); strip.reflectScrolledClipView(strip.contentView)
        func scrollTabs(vertical: Int32 = 0, horizontal: Int32 = 0) {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)!
            strip.scrollWheel(with: NSEvent(cgEvent: event)!); layout()
        }
        scrollTabs(vertical: -40)
        let verticalDestination = strip.contentView.bounds.origin.x
        precondition(verticalDestination > 400 && strip.contentView.bounds.origin.y == 0, "Vertical wheel motion scrolls tabs horizontally without moving the row")
        strip.contentView.scroll(to: NSPoint(x: 400, y: 0))
        scrollTabs(horizontal: -40)
        precondition(abs(strip.contentView.bounds.origin.x - verticalDestination) < 1, "Equivalent horizontal and vertical scroll events move tabs equally")
        scrollTabs(vertical: -10000)
        precondition(abs(strip.contentView.bounds.maxX - controller.tabBar.frame.maxX) < 1, "Tab scrolling clamps at the last tab without overscroll")
        scrollTabs(vertical: 10000)
        precondition(strip.contentView.bounds.origin == .zero, "Reverse scrolling clamps at the beginning")
        strip.contentView.scroll(to: NSPoint(x: 0, y: 20))
        precondition(strip.contentView.bounds.origin.y == 0 && !strip.hasVerticalScroller && strip.verticalScrollElasticity == .none, "The tab strip cannot scroll or bounce vertically")
        controller.tabBar.setFrameSize(originalTabSize); controller.refreshTabBar(); layout()
        precondition((controller.requestHost as Surface).color == bandDarkColor, "Request body uses the darker band")
        precondition(all.compactMap { $0 as? Surface }.first { $0.identifier?.rawValue == "requestControlsBand" }?.color == bandLightColor, "Request controls use the lighter band")
        precondition(all.compactMap { $0 as? Surface }.first { $0.identifier?.rawValue == "responseBand" }?.color == bandLightColor, "Response uses the lighter band")
        precondition(controller.send.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .white, "Send text stays opaque white")
        for popup in all.compactMap({ $0 as? RelayPopup }) {
            precondition(popup.controlSurface?.superview === popup.superview, "Flat popup surface is attached beneath its native control")
        }
        precondition(editor.layer?.borderWidth == 0 && controller.response.layer?.borderWidth == 0, "JSON panels have no outline")
        precondition(editor.text.backgroundColor == inputBackgroundColor && editor.scroll.backgroundColor == inputBackgroundColor, "JSON and inputs share a background")
        let urlBox = controller.url.convert(controller.url.bounds, to: window.contentView)
        let segmentBox = controller.requestSegment.convert(controller.requestSegment.bounds, to: window.contentView)
        precondition(abs(urlBox.minY - segmentBox.maxY - 8) < 0.5, "URL and section group have the same eight-point gap as the top inset")
        let bodyBox = controller.body.convert(controller.body.bounds, to: window.contentView)
        let modeBox = controller.bodyMode.convert(controller.bodyMode.bounds, to: window.contentView)
        precondition(abs(modeBox.midY - segmentBox.midY) < 0.5 && modeBox.minX > segmentBox.maxX && modeBox.maxY > bodyBox.maxY, "Body format sits beside the request pills")
        for section in [1, 2, 3, 0] {
            controller.requestSegment.selectedSegment = section; controller.requestSectionChanged(); layout()
            precondition(controller.bodyMode.isHidden == (section != 0) && controller.authMode.isHidden == (section != 3), "Only the selected section's dropdown is visible")
            if section == 3 {
                let authBox = controller.authMode.convert(controller.authMode.bounds, to: window.contentView)
                precondition(abs(authBox.midY - segmentBox.midY) < 1 && authBox.minX > segmentBox.maxX, "Authentication dropdown sits beside the request pills")
            }
        }
        precondition(all.compactMap { $0 as? RelaySegments }.allSatisfy { $0.frame.height == 28 && $0.controlSize == .large }, "Selection groups match action-button height")
        precondition(controller.tabScroll.frame.height == 44 && controller.tabBar.subviews.allSatisfy { $0.frame.minY == 8 && $0.frame.height == 28 }, "Request tabs use matching vertical insets")
        precondition(!all.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Formatted JSON") || $0.stringValue.hasPrefix("Page 1 of") }, "Footer has no paging or format noise")
        let fixture = controller.store.responses.appendingPathComponent("continuous-check.txt")
        let line = "{\"message\":\"café 📨\",\"value\":123}\n"
        let fixtureText = String(repeating: line, count: 60_000) + "TAIL-MARKER"
        try fixtureText.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let bytes = Array(fixtureText.utf8)
        var cursor: UInt64 = 0; var reconstructed = ""
        while cursor < UInt64(bytes.count) {
            let value = try ResponseReader.Window.read(fixture, start: cursor)
            precondition(value.start == cursor && value.end > cursor, "Sequential reads preserve UTF-8 boundaries")
            precondition(value.text.utf8.count <= ResponseReader.Window.capacity)
            precondition(!value.text.contains("�"), "UTF-8 is never split")
            reconstructed += value.text; cursor = value.end
        }
        precondition(reconstructed == fixtureText, "Every byte remains accessible across windows")
        let reader = controller.responseReader
        controller.response.isHidden = false; controller.emptyResponse.isHidden = true; layout()
        reader.open(fixture, highlight: false)
        func waitFor(_ test: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 8)
            while !test() && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
            precondition(test(), "Response reader completes asynchronously")
        }
        waitFor { reader.window != nil }
        let responseText = controller.response.text, responseLayout = responseText.layoutManager!
        precondition(responseLayout.firstUnlaidCharacterIndex() == (responseText.string as NSString).length, "The bounded response is fully laid out before scrolling")
        let initialHeight = responseText.frame.height
        responseText.displayIfNeeded(); layout()
        precondition(abs(responseText.frame.height - initialHeight) < 1, "Rendering does not extend the response's scroll height later")
        let initialEnd = reader.window!.end
        func visibleByte() -> UInt64 {
            let glyphs = responseLayout.glyphRange(forBoundingRect: controller.response.scroll.contentView.bounds.offsetBy(dx: -responseText.textContainerInset.width, dy: -responseText.textContainerInset.height), in: responseText.textContainer!)
            let chars = responseLayout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            return reader.window!.start + UInt64((responseText.string as NSString).substring(to: chars.location).utf8.count)
        }
        // Simulate continued momentum before the pending disk window can apply.
        let responseLength = (responseText.string as NSString).length
        responseText.scrollRangeToVisible(NSRange(location: responseLength - 50_000, length: 0))
        responseText.scrollRangeToVisible(NSRange(location: responseLength - 10_000, length: 0))
        let liveByte = visibleByte()
        waitFor { reader.window!.end > initialEnd }
        precondition(reader.window!.start > 0, "Scrolling advances beyond the first bounded window")
        precondition(visibleByte() == liveByte, "A window swap preserves the latest momentum position rather than its stale load-time position: \(liveByte) → \(visibleByte()), window \(reader.window!.start), bounds \(controller.response.scroll.contentView.bounds)")
        let forwardStart = reader.window!.start
        layout()
        precondition(reader.window!.start == forwardStart, "The restored viewport does not bounce between disk windows")
        responseText.scrollRangeToVisible(NSRange(location: 10_000, length: 0))
        let reverseByte = visibleByte()
        waitFor { reader.window!.start < forwardStart }
        precondition(visibleByte() == reverseByte, "Reverse scrolling preserves the viewport through a window swap")
        controller.response.text.scrollToEndOfDocument(nil)
        waitFor { controller.response.text.string.hasSuffix("TAIL-MARKER") }
        precondition(controller.response.text.string.utf8.count <= ResponseReader.Window.capacity)
        controller.response.text.scrollToBeginningOfDocument(nil)
        waitFor { reader.window!.start == 0 }
        reader.seek(UInt64(bytes.count - 11), term: "TAIL-MARKER")
        waitFor { controller.response.text.selectedRange().length == 11 }
        let selected = (controller.response.text.string as NSString).substring(with: controller.response.text.selectedRange())
        precondition(selected == "TAIL-MARKER", "Full-file search selects the exact byte offset")
        controller.current!.response = HTTPResult(file: fixture, status: 200, headers: [:], bytes: Int64(bytes.count), duration: 0.1, url: "http://localhost", contentType: "text/plain")
        controller.copyResponseBody()
        waitFor { !controller.copyingResponse }
        precondition(clipboard.string(forType: .string) == fixtureText, "Copy body copies the whole response beyond the visible window")
        precondition(controller.copyResponse.title == "Copied!", "Copy success is visible")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        precondition(controller.copyResponse.title == "Copied!", "Copy feedback persists long enough to read")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.7))
        precondition(controller.copyResponse.title == "Copy body", "Copy feedback resets")
        let longJSON = controller.store.responses.appendingPathComponent("continuous-syntax.json")
        try ("{\"long\":\"" + String(repeating: "a", count: 1_000_000) + "\",\"tail\":true}").write(to: longJSON, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: longJSON) }
        reader.open(longJSON, highlight: true)
        reader.seek(900_000, term: "aaaa")
        waitFor { reader.window?.start == 900_000 - 64 * 1024 && controller.response.text.selectedRange().length == 4 }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        let matchColor = controller.response.text.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: controller.response.text.selectedRange().location, effectiveRange: nil) as? NSColor
        precondition(matchColor == syntaxStringColor, "Disk lexical context keeps mid-string chunks highlighted correctly")
        reader.open(fixture, highlight: false); reader.clear()
        let copiedTab = controller.current!, originalURL = controller.current!.request.url
        let originalVariables = copiedTab.request.variables
        copiedTab.request.variables["curl_base"] = "https://example.com"
        controller.url.stringValue = "{{curl_base}}/unsaved-copy"
        controller.copyRequestAsCurl(); waitFor { !controller.copyingRequest }
        precondition(NSPasteboard.general.string(forType: .string)?.contains("https://example.com/unsaved-copy") == true && controller.copyRequest.title == "Copied!", "Copy as cURL commits current edits, resolves variables and confirms clipboard success")
        precondition(copiedTab.draft.source?.url == originalURL, "Copying never mutates the saved collection request")
        copiedTab.request.variables = originalVariables; copiedTab.request.setURL(originalURL); controller.displayCurrent()
        let originalEnvironments = controller.store.environments, originalEnvironmentIndex = controller.store.selectedEnvironment
        let sourceEnvironment = try Environment(json: ["name": "Staging", "id": "original-id", "metadata": ["preserve": true], "values": [["key": "TOKEN", "value": "demo-token", "enabled": false, "type": "secret"], ["key": "", "value": "unfinished"]]])
        let activeEnvironment = try Environment(json: ["name": "Production", "values": [JSON]()])
        controller.store.environments = [sourceEnvironment, activeEnvironment]; controller.store.selectedEnvironment = 1
        controller.editEnvironments(); controller.environmentIndex = 0; controller.updateEnvironmentEditor(); layout()
        let environmentButtons = descendants(controller.environmentWindow!.contentView!).compactMap { $0 as? NSButton }
        precondition(environmentButtons.contains { $0.title == "New" } && !environmentButtons.contains { $0.title == "New environment" }, "Environment creation uses the short New label")
        let duplicate = environmentButtons.first { $0.title == "Duplicate" }!
        precondition(duplicate.isEnabled, "Duplicate is available for an existing environment")
        controller.envName!.stringValue = "Edited staging"
        duplicate.performClick(nil); layout()
        let copy = controller.store.environments[controller.environmentIndex]
        precondition(copy.name == "Edited staging (copy)" && copy.values.count == 2 && !copy.values[0].enabled && copy.values[0].extra["type"] as? String == "secret", "Duplication commits the name and preserves all rows and flags")
        precondition(copy.original["id"] as? String != "original-id" && (copy.original["metadata"] as? [String: Bool])?["preserve"] == true, "Environment copies have distinct identity and preserve metadata")
        precondition(controller.store.environments[controller.store.selectedEnvironment] === activeEnvironment, "Duplication preserves the active environment after insertion")
        copy.values[0].value = "copy-only"
        precondition(sourceEnvironment.values[0].value == "demo-token", "Editing a duplicate cannot mutate its source")
        controller.environmentIndex = 0; controller.updateEnvironmentEditor(); duplicate.performClick(nil); layout()
        precondition(controller.store.environments[controller.environmentIndex].name == "Edited staging (copy 2)", "Repeated duplication chooses a distinct name")
        controller.closeEnvironmentEditor()
        controller.store.environments = []; controller.store.selectedEnvironment = -1; controller.editEnvironments(); layout()
        let emptyEnvironmentButtons = descendants(controller.environmentWindow!.contentView!).compactMap { $0 as? NSButton }
        let emptyDuplicate = emptyEnvironmentButtons.first { $0.title == "Duplicate" }!
        precondition(!emptyDuplicate.isEnabled, "Empty environment lists cannot be duplicated")
        emptyEnvironmentButtons.first { $0.title == "New" }!.performClick(nil); layout()
        precondition(controller.store.environments.count == 1 && emptyDuplicate.isEnabled, "New creates an environment and enables duplication")
        controller.closeEnvironmentEditor()
        controller.store.environments = originalEnvironments; controller.store.selectedEnvironment = originalEnvironmentIndex; controller.refreshEnvironments(); controller.store.save()
        // Drive native update dialogs with a local URLProtocol fixture: no real
        // downloads, replacements, or GitHub requests are performed by UI tests.
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [UIReleaseProtocol.self]
        let updateSession = URLSession(configuration: configuration)
        let suite = "app.postino.update-checks.\(UUID().uuidString)"
        let updateDefaults = UserDefaults(suiteName: suite)!
        defer { updateDefaults.removePersistentDomain(forName: suite); updateSession.invalidateAndCancel() }
        controller.showWindow(nil); layout()
        defer { window.orderOut(nil) }
        var updateBusy = false
        let updates = AppUpdateController(window: window, defaults: updateDefaults, checker: AppUpdateChecker(session: updateSession),
            installed: InstalledRelease(info: ["PostinoReleaseTag": "postino-100-1", "PostinoBuildDate": "2026-10-12T10:00:00Z"]),
            canPresent: { true }, stateChanged: { updateBusy = $0 }, restart: { update in update.discard(); preconditionFailure("Dialog tests must not restart") })
        func latest(_ tag: String) throws {
            UIReleaseProtocol.body = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "name": "Test release", "html_url": "https://github.com/Dome015/postino/releases/tag/\(tag)", "published_at": "2026-10-13T12:00:00Z", "draft": false, "prerelease": false, "assets": []])
        }
        func dismissUpdate(_ response: NSApplication.ModalResponse) {
            window.endSheet(window.attachedSheet!, returnCode: response); layout()
        }
        try latest("postino-200-1")
        updates.check(manual: true); precondition(updateBusy)
        waitFor { window.attachedSheet != nil && !updateBusy }
        let updateViews = descendants(window.attachedSheet!.contentView!)
        precondition(updateViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "A newer version of Postino is available." }, "Available-update dialog uses the requested message")
        precondition(Set(updateViews.compactMap { $0 as? NSButton }.map(\.title)) == ["Update and restart", "Remind me later"], "Update dialog provides restart or reminder choices")
        func captureSheet(_ name: String) throws {
            let sheet = window.attachedSheet!
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                sheet.appearance = NSAppearance(named: appearance); layout()
                let view = sheet.contentView!.superview!
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/\(name)-\(suffix).png"))
            }
        }
        try captureSheet("update-dialog")
        dismissUpdate(.alertSecondButtonReturn)
        updates.checkAutomaticallyIfDue(); layout()
        precondition(UIReleaseProtocol.requests == 1 && window.attachedSheet == nil, "Automatic checks respect the daily interval")
        try latest("postino-100-1")
        updateDefaults.set(Date.distantPast, forKey: "PostinoLastUpdateCheck")
        updates.checkAutomaticallyIfDue(); waitFor { !updateBusy }; layout()
        precondition(window.attachedSheet == nil, "Automatic checks with no update remain quiet")
        updates.check(manual: true); waitFor { window.attachedSheet != nil && !updateBusy }
        precondition(descendants(window.attachedSheet!.contentView!).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "No updates found." }, "Manual checks with no update use the requested message")
        try captureSheet("no-updates-dialog")
        dismissUpdate(.alertFirstButtonReturn)
        let otherSheet = NSAlert(); otherSheet.messageText = "Other action"; otherSheet.beginSheetModal(for: window)
        try latest("postino-300-1")
        updateDefaults.set(Date.distantPast, forKey: "PostinoLastUpdateCheck")
        updates.checkAutomaticallyIfDue(); waitFor { !updateBusy }
        precondition(window.attachedSheet === otherSheet.window, "Automatic notifications must not interrupt another sheet")
        dismissUpdate(.alertFirstButtonReturn)
        waitFor { window.attachedSheet != nil }
        precondition(descendants(window.attachedSheet!.contentView!).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "A newer version of Postino is available." }, "Deferred notifications appear after the existing sheet closes")
        dismissUpdate(.alertSecondButtonReturn)
        print("Passed JSON lexer, large viewport, cancellation, live highlighting, sidebar resizing, compact controls, body modes, method tabs, bounded scrolling, search, UTF-8 continuity, and disk JSON context checks")
    }
}
