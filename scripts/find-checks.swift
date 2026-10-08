import AppKit
import RelayCore

@main
struct FindChecks {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let controller = MainWindow(), window = controller.window!
        func memory(_ phase: String) {
            guard ProcessInfo.processInfo.environment["PROFILE_FIND"] == "1" else { return }
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("Peak RSS after \(phase): \(usage.ru_maxrss / 1_048_576) MiB"); fflush(stdout)
        }
        memory("window setup")
        func pump() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
        func wait(_ message: String, _ check: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 15)
            while !check() && Date() < deadline { pump() }
            precondition(check(), message)
        }
        let clipboard = NSPasteboard(name: .find)
        let savedClipboard = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let saved = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
            return saved
        } ?? []
        defer { clipboard.clearContents(); if !savedClipboard.isEmpty { clipboard.writeObjects(savedClipboard) } }
        func query(_ term: String) { clipboard.clearContents(); clipboard.setString(term, forType: .string) }
        let capacity = ResponseReader.Window.capacity
        let start = "café 📨\n"
        let padding = capacity - 5 - start.utf8.count
        let fixtureText = start + String(repeating: "x\n", count: padding / 2) + String(repeating: "x", count: padding % 2) + "CROSS-BOUNDARY\n" + String(repeating: "ordinary line 📨 café\n", count: 40_000) + "TAIL-MARKER\n"
        let fixture = controller.store.responses.appendingPathComponent("native-find.txt")
        try fixtureText.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixtureText as NSString
        let document = try ResponseSearchDocument(file: fixture)
        memory("small file index")
        precondition(document.length == source.length && document.chunks.count > 2)
        for term in ["café", "📨", "CROSS-BOUNDARY", "TAIL-MARKER"] {
            let range = source.range(of: term)
            let byte = document.byteOffset(at: range.location)
            precondition(document.characterOffset(at: byte) == range.location, "Unicode UTF-16/UTF-8 positions round-trip")
            precondition(byte == UInt64(source.substring(to: range.location).utf8.count))
        }
        let reader = controller.responseReader
        controller.current!.response = HTTPResult(file: fixture, status: 200, headers: [:], bytes: Int64(fixtureText.utf8.count), duration: 0.1, url: "http://localhost", contentType: "text/plain")
        controller.renderResponse()
        wait("File index and initial viewport load") { reader.findClient.document != nil && reader.window != nil }
        let client = reader.findClient, finder = client.finder
        precondition(!finder.validateAction(.replace) && !finder.validateAction(.replaceAll) && !finder.validateAction(.showReplaceInterface), "Response Find is read-only")
        finder.performAction(.showFindInterface); pump()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let fields = descendants(controller.response.scroll.findBarView!).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        func find(_ term: String, action: NSTextFinder.Action = .nextMatch) {
            query(term); let field = fields.first!; field.stringValue = term; if let action = field.action { field.sendAction(action, to: field.target) }; pump(); finder.performAction(action)
            let expected = source.range(of: term)
            wait("Native finder reveals \(term) at its full-file offset") {
                client.firstSelectedRange == expected && controller.response.text.selectedRange().length == expected.length && (controller.response.text.string as NSString).substring(with: controller.response.text.selectedRange()) == term
            }
            precondition(controller.response.text.string.utf8.count <= capacity, "Native search keeps the display bounded")
        }
        find("CROSS-BOUNDARY")
        find("TAIL-MARKER")
        // Exercise backward navigation and wraparound with a unique term.
        let field = fields.first!; field.stringValue = "CROSS-BOUNDARY"; if let action = field.action { field.sendAction(action, to: field.target) }; pump(); finder.performAction(.previousMatch)
        wait("Previous navigates across chunks") { client.firstSelectedRange == source.range(of: "CROSS-BOUNDARY") }
        wait("Native incremental matches cover the complete logical response") { finder.incrementalMatchRanges.contains { $0.rangeValue == source.range(of: "CROSS-BOUNDARY") } }
        finder.performAction(.previousMatch)
        wait("Previous wraps around the full document") { client.firstSelectedRange == source.range(of: "CROSS-BOUNDARY") }
        controller.showResponseFind(); pump()
        precondition(controller.response.scroll.isFindBarVisible && controller.response.scroll.findBarView != nil, "Response displays the native Find bar")
        finder.performAction(.hideFindInterface); pump()
        precondition(!controller.response.scroll.isFindBarVisible)
        memory("small native searches")
        let request = controller.body
        request.set("{\"message\":\"native café 📨\",\"other\":\"native\"}")
        window.makeFirstResponder(request.text)
        query("native")
        let item = NSMenuItem(title: "Find", action: nil, keyEquivalent: ""); item.tag = NSTextFinder.Action.showFindInterface.rawValue
        request.text.performTextFinderAction(item); pump()
        precondition(request.scroll.isFindBarVisible && request.text.isIncrementalSearchingEnabled && request.text.isEditable, "Request uses the same native Find bar with editing enabled")
        item.tag = NSTextFinder.Action.showReplaceInterface.rawValue; request.text.performTextFinderAction(item); pump()
        let requestFields = descendants(request.scroll.findBarView!).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        precondition(requestFields.count >= 2)
        requestFields[0].stringValue = "native"
        requestFields[0].sendAction(requestFields[0].action!, to: requestFields[0].target)
        requestFields[1].stringValue = "changed"
        item.tag = NSTextFinder.Action.replaceAll.rawValue; request.text.performTextFinderAction(item); pump()
        precondition(request.text.string == "{\"message\":\"changed café 📨\",\"other\":\"changed\"}", "Native request Replace All edits the body")
        item.tag = NSTextFinder.Action.hideFindInterface.rawValue; request.text.performTextFinderAction(item)
        // A large fixture is written in bounded buffers; search begins before its
        // asynchronous index is ready, then must update without another keystroke.
        let large = controller.store.responses.appendingPathComponent("native-find-large.txt")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: large) }
        let output = try FileHandle(forWritingTo: large)
        let block = Data(String(repeating: "line value\n", count: 47_662).utf8)
        for _ in 0..<256 { try output.write(contentsOf: block) }
        try output.write(contentsOf: Data("LARGE-TAIL".utf8)); try output.close()
        let bytes = ResponseFile.size(large)
        precondition(bytes > 128_000_000)
        controller.current!.response = HTTPResult(file: large, status: 200, headers: [:], bytes: bytes, duration: 0.1, url: "http://localhost", contentType: "text/plain")
        memory("128 MB fixture write")
        client.ready = { memory("128 MB file index") }
        controller.renderResponse()
        finder.performAction(.showFindInterface); pump()
        let largeField = descendants(controller.response.scroll.findBarView!).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        largeField.stringValue = "LARGE-TAIL"; largeField.sendAction(largeField.action!, to: largeField.target)
        wait("Large response indexing completes") { client.document != nil }
        wait("Query refreshes when the file index becomes ready") { client.firstSelectedRange.location == client.document!.length - 10 }
        finder.performAction(.nextMatch)
        wait("Native Find reaches beyond 128 MB") { controller.response.text.selectedRange().length == 10 && controller.response.text.string.hasSuffix("LARGE-TAIL") }
        precondition(controller.response.text.string.utf8.count <= capacity && client.document!.chunks.count < 300, "Large response text and index remain bounded")
        memory("128 MB native search")
        reader.clear()
        precondition(client.document == nil && client.stringLength() == 0, "Tab and file switches invalidate the old search document")
        print("Passed native Find bars, full-file next/previous and wraparound, cross-chunk matches, Unicode mapping, bounded display, read-only response validation, native request replacement, and 128 MB incremental search")
    }
}
