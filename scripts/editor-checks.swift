import AppKit
import RelayCore

private final class TestPairDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { (draggingSource as? NSView)?.window }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(source: NSTableView) { draggingSource = source; super.init() }
    deinit { draggingPasteboard.releaseGlobally() }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination destination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
struct EditorChecks {
    enum Failure: Error { case check(String) }
    static func require(_ value: Bool, _ message: String) throws { if !value { throw Failure.check(message) } }
    static func checkRowActions(_ editor: PairEditor, window: NSWindow) throws {
        let clipboard = NSPasteboard.general
        let saved = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer { clipboard.clearContents(); if !saved.isEmpty { clipboard.writeObjects(saved) } }
        window.makeFirstResponder(nil)
        editor.rows = [Pair("A", "one", extra: ["enabled": false, "metadata": ["keep": true]]), Pair("B", "two"), Pair("C", "", enabled: false, extra: ["type": "file", "src": "/tmp/file.json", "contentType": "application/json"]), Pair("D", "four")]
        try require(editor.moveRows(IndexSet([0, 2]), to: 4) && editor.rows.map(\.key) == ["B", "D", "A", "C"], "Noncontiguous row moves preserve relative order")
        let drag = TestPairDrag(source: editor.table)
        let writers = [2, 3].compactMap { editor.tableView(editor.table, pasteboardWriterForRow: $0) }
        drag.draggingPasteboard.writeObjects(writers)
        try require(editor.tableView(editor.table, validateDrop: drag, proposedRow: 0, proposedDropOperation: .above) == .move, "Native table drag data validates locally")
        try require(editor.tableView(editor.table, acceptDrop: drag, row: 0, dropOperation: .above) && editor.rows.map(\.key) == ["A", "C", "B", "D"], "Native table drop moves selected rows")
        try require(!editor.moveRows(IndexSet([0, 1]), to: 2), "Dropping within the original selection is a no-op")
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(editor.table)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        editor.table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        // WindowServer can deny foreground activation for a test process. Start
        // at the window's actual first responder, as the Edit menu does when key.
        try require(window.firstResponder === editor.table && window.firstResponder!.tryToPerform(#selector(NSText.copy(_:)), with: nil), "Row selection receives native Copy")
        let other = PairEditor(configuration: .environment); other.pasteRows()
        try require(other.rows.map(\.key) == ["A", "C"] && other.rows[0].enabled && !other.rows[1].enabled && other.rows[1].extra["src"] as? String == "/tmp/file.json", "Cross-table clipboard preserves current enabled/file metadata")
        try require((other.rows[0].extra["metadata"] as? [String: Bool])?["keep"] == true, "Clipboard preserves unknown nested metadata")
        window.firstResponder?.tryToPerform(#selector(NSText.cut(_:)), with: nil)
        try require(editor.rows.map(\.key) == ["B", "D"], "Cut removes only selected rows")
        editor.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: nil)
        try require(editor.rows.map(\.key) == ["B", "A", "C", "D"], "Paste inserts after the selected row")
        editor.table.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        editor.table.keyDown(with: event)
        try require(editor.rows.map(\.key) == ["B", "D"], "Delete key removes selected rows")
        try require(editor.tableView(editor.table, validateDrop: drag, proposedRow: 0, proposedDropOperation: .above).isEmpty, "Stale drag data is rejected after rows change")
        editor.table.selectAll(nil); editor.table.deleteSelection(nil)
        clipboard.clearContents(); clipboard.setString("X-One\t1\nX-Two\t2\n", forType: .string); editor.pasteRows()
        try require(editor.rows.map(\.key) == ["X-One", "X-Two"] && editor.rows.map(\.value) == ["1", "2"], "External tab-separated rows paste into an empty table")
        let column = editor.table.column(withIdentifier: .init("key"))
        let field = editor.table.view(atColumn: column, row: 0, makeIfNecessary: true)!.subviews.compactMap { $0 as? NSTextField }.first!
        window.makeFirstResponder(field)
        try require(window.firstResponder is NSTextView && !(window.firstResponder is PairTableView), "Editing a cell retains text clipboard shortcuts")
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(PairTableView.deleteSelection(_:)), keyEquivalent: "")
        try require(!editor.table.validateUserInterfaceItem(deleteItem), "Row deletion does not override a cell editor's text shortcuts")
        editor.table.deleteSelection(nil)
        try require(editor.rows.count == 2, "A row Delete action cannot delete while a cell is being edited")
        window.makeFirstResponder(nil)
    }
    static func checkCodeEditing(_ window: NSWindow) throws {
        window.makeFirstResponder(nil)
        window.contentView!.subviews.forEach { $0.removeFromSuperview() }
        let editor = CodeEditor(editable: true); pin(editor, in: window.contentView!)
        window.contentView!.layoutSubtreeIfNeeded(); window.makeFirstResponder(editor.text)
        let undo = editor.text.undoManager!
        undo.groupsByEvent = false
        func set(_ string: String, _ selection: NSRange? = nil) {
            editor.set(string, highlight: true); editor.text.undoManager?.removeAllActions()
            editor.text.setSelectedRange(selection ?? NSRange(location: (string as NSString).length, length: 0))
        }
        func event(_ action: () -> Void) {
            undo.beginUndoGrouping(); action(); editor.text.breakUndoCoalescing(); undo.endUndoGrouping()
        }
        func type(_ value: String) { event { editor.text.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0)) } }
        set(""); type("{")
        try require(editor.text.string == "{}" && editor.text.selectedRange().location == 1, "Opening braces auto-close with the caret between")
        event { editor.text.insertNewline(nil) }
        try require(editor.text.string == "{\n  \n}" && editor.text.selectedRange().location == 4, "Newlines expand bracket pairs and indent the inner line")
        editor.text.undoManager?.undo()
        try require(editor.text.string == "{}", "Auto-indentation is a single native undo operation: \(editor.text.string.debugDescription)")
        editor.text.undoManager?.redo()
        try require(editor.text.string == "{\n  \n}", "Native redo restores auto-indentation")
        set("[]", NSRange(location: 1, length: 0)); type("]")
        try require(editor.text.string == "[]" && editor.text.selectedRange().location == 2, "Typing a closing delimiter skips an existing closer")
        set(""); type("\""); event { editor.text.deleteBackward(nil) }
        try require(editor.text.string.isEmpty, "Backspace removes an empty auto-paired quote")
        set("alpha", NSRange(location: 0, length: 5)); type("[")
        try require(editor.text.string == "[alpha]" && editor.text.selectedRange() == NSRange(location: 1, length: 5), "Opening delimiters wrap a selection")
        set("\"name\"", NSRange(location: 3, length: 0)); type("[")
        try require(editor.text.string == "\"na[me\"", "Brackets inside strings remain literal")
        set("{\n    \"a\": 1,"); event { editor.text.insertNewline(nil) }
        try require(editor.text.string.hasSuffix("\n    "), "Newlines preserve an existing four-space indentation style")
        set("one\ntwo", NSRange(location: 0, length: 7)); event { editor.text.insertTab(nil) }
        try require(editor.text.string == "  one\n  two", "Tab indents selected lines")
        event { editor.text.insertBacktab(nil) }
        try require(editor.text.string == "one\ntwo", "Shift-Tab outdents selected lines")
        set("{\n  "); type("}")
        try require(editor.text.string == "{\n}", "Closing braces outdent whitespace-only lines")
        set("{\"key\":\"value\"}")
        func color(_ index: Int) -> Any? { editor.text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) }
        let deadline = Date(timeIntervalSinceNow: 3)
        while color(3) == nil && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
        try require(color(3) != nil, "JSON highlighting is ready before typing")
        type(" ")
        try require(color(3) != nil, "Typing retains existing colors without an uncolored frame")
        editor.text.setSelectedRange(NSRange(location: 0, length: 0)); type("  ")
        try require(color(5) != nil, "Highlight ranges track inserted prefixes")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        try require(color(5) != nil && editor.text.string.hasPrefix("  {"), "Replacement highlighting preserves content after range shifts")
        let response = CodeEditor(editable: false)
        try require(!response.text.editingAidsEnabled && !response.text.isEditable, "Response editors stay read-only and have no insertion aids")
    }
    static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 500), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        func layout() {
            window.contentView!.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            window.contentView!.layoutSubtreeIfNeeded()
        }
        for configuration in [PairTableConfiguration.headers, .parameters, .environment, .form, .credentials] {
            window.contentView!.subviews.forEach { $0.removeFromSuperview() }
            let editor = PairEditor(configuration: configuration)
            pin(editor, in: window.contentView!)
            editor.rows = [Pair(json: ["key": "Accept", "value": "application/json", "metadata": "preserve"]), Pair(json: ["key": "X-Test", "value": "test"])]
            var saved = editor.rows
            editor.changed = { saved = $0 }
            for width: CGFloat in [980, 740, 1100, 640] {
                window.setContentSize(NSSize(width: width, height: 500)); layout()
                let table = editor.table
                let clip = table.enclosingScrollView!.contentView
                for name in ["value", "delete"] {
                    let col = table.column(withIdentifier: .init(name))
                    let view = table.view(atColumn: col, row: 0, makeIfNecessary: true)!
                    view.layoutSubtreeIfNeeded()
                    let rect = table.convert(view.bounds, from: view)
                    precondition(rect.maxX <= clip.bounds.maxX + 0.5 && rect.minX >= clip.bounds.minX, "Inputs and row actions must fit after resizing")
                }
                let addRect = editor.addButton.convert(editor.addButton.bounds, to: editor.table.headerView!)
                precondition(addRect.maxX <= editor.table.headerView!.bounds.maxX && addRect.width == 28, "Add button must remain within the header")
            }
            let checkboxHost = editor.table.view(atColumn: editor.table.column(withIdentifier: .init("enabled")), row: 1, makeIfNecessary: true)!
            let checkbox = checkboxHost.subviews.first as! NSButton
            checkbox.performClick(nil)
            precondition(editor.rows.count == 2 && saved.count == 2 && !saved[1].enabled, "Checkbox changes must not create rows")
            editor.addButton.performClick(nil); layout()
            precondition(saved.count == 3 && editor.table.numberOfRows == 3, "Plus adds exactly one row without an implicit placeholder")
            let keyColumn = editor.table.column(withIdentifier: .init("key"))
            let keyHost = editor.table.view(atColumn: keyColumn, row: 2, makeIfNecessary: true)!
            let keyField = keyHost.subviews.compactMap { $0 as? NSTextField }.first!
            precondition(window.firstResponder === keyField.currentEditor(), "Plus focuses the new key field")
            keyField.stringValue = "New entry"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: keyField))
            precondition(saved.count == 3 && saved[2].key == "New entry", "Typing edits the existing row")
            let deleteColumn = editor.table.column(withIdentifier: .init("delete"))
            func delete(_ row: Int) {
                let host = editor.table.view(atColumn: deleteColumn, row: row, makeIfNecessary: true)!
                (host.subviews.first as! NSButton).performClick(nil); layout()
            }
            delete(1)
            precondition(saved.map(\.key) == ["Accept", "New entry"] && saved[0].extra["metadata"] as? String == "preserve", "Inline delete targets its own row and preserves other entries")
            delete(1); delete(0)
            precondition(saved.isEmpty && editor.table.numberOfRows == 0 && !editor.canRemoveRow, "Every row can be deleted, including the last")
            editor.addButton.performClick(nil); layout()
            precondition(editor.rows.count == 1, "Empty tables remain addable")
            if configuration.showsType {
                let typeColumn = editor.table.column(withIdentifier: .init("type"))
                let host = editor.table.view(atColumn: typeColumn, row: 0, makeIfNecessary: true)!
                let popup = host.subviews.compactMap { $0 as? NSPopUpButton }.first!
                popup.selectItem(at: 1); NSApp.sendAction(popup.action!, to: popup.target, from: popup)
                let valueColumn = editor.table.column(withIdentifier: .init("value"))
                let valueHost = editor.table.view(atColumn: valueColumn, row: 0, makeIfNecessary: true)!
                let valueField = valueHost.subviews.compactMap { $0 as? NSTextField }.first!
                valueField.stringValue = "/tmp/fixture.json"
                editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: valueField))
                precondition(saved[0].extra["type"] as? String == "file" && saved[0].extra["src"] as? String == "/tmp/fixture.json", "Shared form controls retain file semantics")
            }
            try checkRowActions(editor, window: window)
        }
        try checkCodeEditing(window)
        print("Passed code editing and all five table configurations: resizing, focus, explicit add, checkbox stability, inline deletion, and form metadata")
    }
}
