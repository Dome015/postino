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
        precondition(split.arrangedSubviews.count == 2 && split.frame.height > 400, "Sidebar split content must be present")
        precondition(controller.requestSegment.selectedSegment == 0 && controller.requestHost.subviews[0].isHidden == false && controller.bodyHost.isDescendant(of: controller.requestHost.subviews[0]), "Body is first and selected by default")
        for width: CGFloat in [1200, 980, 1100] {
            window.setContentSize(NSSize(width: width, height: 760)); layout()
            split.setPosition(200, ofDividerAt: 0); layout(); let narrow = split.arrangedSubviews[0].frame.width
            precondition(controller.outline.tableColumns[0].width <= controller.outline.enclosingScrollView!.contentView.bounds.width + 1, "Tree column must fit a narrow sidebar")
            split.setPosition(330, ofDividerAt: 0); layout(); let wide = split.arrangedSubviews[0].frame.width
            precondition(wide - narrow > 100, "Sidebar must resize over its supported range")
            precondition(controller.outline.tableColumns[0].width <= controller.outline.enclosingScrollView!.contentView.bounds.width + 1, "Tree columns must stay within the sidebar")
            precondition(controller.bodyMode.frame.width >= controller.bodyMode.intrinsicContentSize.width - 1, "Body format titles must fit")
            for item in controller.bodyMode.itemTitles {
                let width = (item as NSString).size(withAttributes: [.font: controller.bodyMode.font!]).width
                precondition(width <= controller.bodyMode.frame.width - 30, "Every body mode must be legible")
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(window.contentView!)
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
        precondition(controller.tabScroll.backgroundColor == bandDarkColor, "Request tabs use the darker band")
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
        precondition(matchColor == .systemGreen, "Disk lexical context keeps mid-string chunks highlighted correctly")
        reader.open(fixture, highlight: false); reader.clear()
        print("Passed JSON lexer, large viewport, cancellation, live highlighting, sidebar resizing, compact controls, body modes, method tabs, bounded scrolling, search, UTF-8 continuity, and disk JSON context checks")
    }
}
