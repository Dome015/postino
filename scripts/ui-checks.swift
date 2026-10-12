import AppKit
import RelayCore

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
        let controller = MainWindow()
        let window = controller.window!
        func layout() { window.contentView!.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12)); window.contentView!.layoutSubtreeIfNeeded() }
        layout()
        let split = controller.sidebarSplit.splitView
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
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
        precondition(actionViews.count == 4 && actionViews.flatMap(descendants).compactMap { $0 as? RelayButton }.contains { $0.title == "New collection" }, "The unified toolbar retains actions and clearly labels collection creation")
        let toolbarButtons = actionViews.flatMap(descendants).compactMap { $0 as? RelayButton }
        precondition(toolbarButtons.filter { ["New request", "New collection"].contains($0.title) }.allSatisfy { $0.isEnabled && $0.target === controller }, "Creation controls retain their enabled state and action targets in the toolbar")
        let originalName = controller.current!.request.name
        controller.current!.request.name = originalName + " modified"; controller.draftChanged(); toolbar.validateVisibleItems()
        precondition(controller.save.isEnabled, "Save enables for a modified draft inside the native toolbar")
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
            precondition(actionBoxes[0].minX > closeBox.maxX && actionBoxes[0].maxX < actionBoxes[1].minX && actionBoxes[1].maxX < actionBoxes[2].minX && actionBoxes[2].maxX < actionBoxes[3].minX, "Window controls and toolbar actions never overlap")
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
        precondition(abs(modeBox.minY - bodyBox.maxY - 8) < 0.5, "Body dropdown and editor use the same eight-point gap")
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
        reader.open(fixture, highlight: false)
        func waitFor(_ test: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 8)
            while !test() && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
            precondition(test(), "Response reader completes asynchronously")
        }
        waitFor { reader.window != nil }
        let initialEnd = reader.window!.end
        controller.response.text.scrollRangeToVisible(NSRange(location: (controller.response.text.string as NSString).length - 100, length: 0))
        waitFor { reader.window!.end > initialEnd }
        precondition(reader.window!.start > 0, "Scrolling advances beyond the first bounded window")
        controller.response.text.scrollToEndOfDocument(nil)
        waitFor { controller.response.text.string.hasSuffix("TAIL-MARKER") }
        precondition(controller.response.text.string.utf8.count <= ResponseReader.Window.capacity)
        controller.response.text.scrollToBeginningOfDocument(nil)
        waitFor { reader.window!.start == 0 }
        reader.seek(UInt64(bytes.count - 11), term: "TAIL-MARKER")
        waitFor { controller.response.text.selectedRange().length == 11 }
        let selected = (controller.response.text.string as NSString).substring(with: controller.response.text.selectedRange())
        precondition(selected == "TAIL-MARKER", "Full-file search selects the exact byte offset")
        let clipboard = NSPasteboard.general
        let savedClipboard = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let saved = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
            return saved
        } ?? []
        defer { clipboard.clearContents(); if !savedClipboard.isEmpty { clipboard.writeObjects(savedClipboard) } }
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
        print("Passed JSON lexer, large viewport, cancellation, live highlighting, sidebar resizing, compact controls, body modes, method tabs, bounded scrolling, search, UTF-8 continuity, and disk JSON context checks")
    }
}
