import AppKit
import RelayCore

@main
struct EditorChecks {
    static func main() {
        _ = NSApplication.shared
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
            let checkboxHost = editor.table.view(atColumn: 0, row: 1, makeIfNecessary: true)!
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
        }
        print("Passed all five table configurations: resizing, focus, explicit add, checkbox stability, inline deletion, and form metadata")
    }
}
