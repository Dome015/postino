import AppKit
import RelayCore

@main
struct VariableChecks {
    static func main() throws {
        _ = NSApplication.shared
        let controller = MainWindow(), window = controller.window!
        controller.open(controller.store.collections[0].allRequests[0])
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.acceptsMouseMovedEvents = true
        func settle(_ duration: TimeInterval = 0.1) {
            window.contentView!.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
            window.contentView!.layoutSubtreeIfNeeded()
        }
        func waitFor(_ test: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 8)
            while !test() && Date() < deadline { settle(0.02) }
            precondition(test(), "Asynchronous variable save completes")
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func capture(_ view: NSView, _ name: String) throws {
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/\(name).png"))
        }
        let longValue = String(repeating: "a-long-token-without-spaces-", count: 60) + "\ncafé 📨\nLAST-LINE"
        let development = try Environment(json: ["name": "Development", "values": [
            ["key": "host", "value": "https://example.test", "type": "secret", "metadata": "preserve"],
            ["key": "empty", "value": ""], ["key": "disabled", "value": "hidden", "enabled": false],
            ["key": "long", "value": longValue]
        ]])
        let staging = try Environment(json: ["name": "Staging", "values": [["key": "host", "value": "https://staging.example.test"]]])
        controller.store.environments = [development, staging]; controller.store.selectedEnvironment = 0; controller.refreshEnvironments()
        controller.url.stringValue = "{{host}}{{missing}}/{{disabled}}/{{empty}}/{{long}}"
        controller.body.set("{\n  \"url\": \"{{host}}\",\n  \"missing\": \"{{missing}}\"\n}", highlight: true)
        settle()
        let field = controller.url, highlighter = field.variableHighlighter!
        precondition(highlighter.references.map(\.name) == ["host", "missing", "disabled", "empty", "long"])
        let source = field.stringValue
        func hover(_ helper: VariableReferenceHighlighter, _ owner: NSView, name: String) {
            helper.refresh()
            let reference = helper.references.first { $0.name == name }!, box = helper.rect(for: reference)!
            let point = owner.convert(NSPoint(x: box.midX, y: box.midY), to: nil)
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            NSApp.sendEvent(event)
            precondition(helper.popover?.isShown == true, "Native mouse events open the preview immediately, including over the shared field editor")
            precondition(helper.previewController?.nameLabel.stringValue == "{{\(name)}}", "Hovering another variable immediately updates the preview")
        }
        for focused in [false, true] {
            if focused { window.makeFirstResponder(field) } else { window.makeFirstResponder(nil) }
            settle()
            let responder = window.firstResponder
            if let native = field.currentEditor() as? NSTextView { native.setSelectedRange(NSRange(location: 3, length: 2)) }
            hover(highlighter, field, name: "host")
            precondition(window.firstResponder === responder, "Hover does not steal source input focus (focused=\(focused)): \(String(describing: responder)) → \(String(describing: window.firstResponder))")
            precondition(highlighter.previewController?.valueEditor.text.string == "https://example.test")
            precondition(highlighter.previewController!.saveButton.isHiddenOrHasHiddenAncestor, "Save stays hidden before editing")
            if let native = field.currentEditor() as? NSTextView { precondition(native.selectedRange() == NSRange(location: 3, length: 2) && native.string == source) }
            let textOrigin = field.cell!.drawingRect(forBounds: field.bounds).minX
            precondition(highlighter.rect(for: highlighter.references[0])!.minX == textOrigin, "Focus does not shift the text or highlight horizontally")
            hover(highlighter, field, name: "missing"); hover(highlighter, field, name: "host")
            try capture(field, "variables-field-\(focused ? "focused" : "unfocused")")
            // Clicking the source reference to focus it must not dismiss the preview.
            let box = highlighter.rect(for: highlighter.references[0])!, point = field.convert(NSPoint(x: box.midX, y: box.midY), to: nil)
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
            highlighter.handle(click); window.makeFirstResponder(field); settle()
            precondition(highlighter.popover?.isShown == true, "Focusing the source retains its preview")
            highlighter.closePreview()
        }
        hover(highlighter, field, name: "host")
        let popup = highlighter.previewController!.view.window!
        let inside = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: popup.contentView!.bounds.midX, y: popup.contentView!.bounds.midY), modifierFlags: [], timestamp: 0, windowNumber: popup.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        highlighter.handle(inside)
        precondition(highlighter.popover?.isShown == true, "Moving onto the tooltip retains it")
        let refBox = highlighter.rect(for: highlighter.references[0])!
        let outsidePoint = field.convert(NSPoint(x: field.bounds.maxX - 2, y: refBox.midY), to: nil)
        let outside = NSEvent.mouseEvent(with: .mouseMoved, location: outsidePoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        highlighter.handle(outside)
        precondition(highlighter.popover == nil, "Leaving both the reference and tooltip closes immediately without a timer")
        hover(highlighter, field, name: "host")
        let belowPoint = field.convert(NSPoint(x: field.bounds.maxX - 2, y: -15), to: nil)
        let below = NSEvent.mouseEvent(with: .mouseMoved, location: belowPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        highlighter.handle(below)
        precondition(highlighter.popover == nil, "Moving below and away from the tooltip dismisses immediately")
        hover(highlighter, field, name: "host")
        let dirty = highlighter.previewController!
        dirty.view.window!.makeKey(); dirty.view.window!.makeFirstResponder(dirty.valueEditor.text)
        dirty.valueEditor.text.insertText("unsaved", replacementRange: NSRange(location: 0, length: (dirty.valueEditor.text.string as NSString).length))
        highlighter.handle(outside)
        precondition(highlighter.popover == nil && development.variables["host"] == "https://example.test", "Leaving both regions immediately discards an unsaved tooltip edit")
        window.makeKeyAndOrderFront(nil)
        // Compare the drawn/hit rectangles to AppKit's own glyph geometry,
        // including prefix text and a horizontally scrolled field editor.
        field.stringValue = String(repeating: "prefix/", count: 30) + "{{host}}/suffix"
        window.makeFirstResponder(field); settle()
        let geometryEditor = field.currentEditor() as! NSTextView
        geometryEditor.scrollRangeToVisible(highlighter.references[0].range); settle()
        highlighter.refresh()
        let manager = geometryEditor.layoutManager!, container = geometryEditor.textContainer!, reference = highlighter.references[0]
        let glyphs = manager.glyphRange(forCharacterRange: reference.range, actualCharacterRange: nil)
        let nativeBox = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let origin = geometryEditor.textContainerOrigin
        let viewport = field.convert(geometryEditor.visibleRect, from: geometryEditor).intersection(field.visibleRect)
        let expected = field.convert(nativeBox.offsetBy(dx: origin.x, dy: origin.y), from: geometryEditor).intersection(viewport)
        precondition(highlighter.rect(for: reference) == expected, "Focused highlight edges match native glyph bounds exactly, including horizontal scrolling")
        if let clip = geometryEditor.enclosingScrollView?.contentView ?? geometryEditor.superview as? NSClipView {
            geometryEditor.setSelectedRange(NSRange(location: 0, length: 0))
            clip.scroll(to: NSPoint(x: nativeBox.midX + origin.x, y: 0)); settle()
            let partial = highlighter.rect(for: reference)!
            let visible = field.convert(geometryEditor.visibleRect, from: geometryEditor).intersection(field.visibleRect)
            precondition(abs(partial.minX - visible.minX) < 0.01, "Partially scrolled references clip at the native text viewport and cannot bleed into input padding")
            try capture(field, "variables-field-partial-scroll")
        }
        window.makeFirstResponder(nil); field.stringValue = source; settle()
        let cellRect = field.cell!.drawingRect(forBounds: field.bounds)
        let unfocusedBox = highlighter.rect(for: highlighter.references[0])!
        precondition(unfocusedBox.minX == cellRect.minX, "Unfocused glyphs and highlights use the same cell origin")
        // Reproduce the adjacent-reference screenshot with proportional and monospaced fonts.
        for (font, suffix) in [(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), "mono"), (.systemFont(ofSize: 13), "proportional")] {
            field.font = font; field.stringValue = "{{host}}{{missing}}"; settle()
            for focused in [false, true] {
                if focused { window.makeFirstResponder(field); (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0)) } else { window.makeFirstResponder(nil) }; settle()
                highlighter.refresh()
                let first = highlighter.rect(for: highlighter.references[0])!, second = highlighter.rect(for: highlighter.references[1])!
                precondition(abs(first.maxX - second.minX) < 0.01, "Adjacent highlights share the exact glyph-run boundary without accumulated substring rounding")
                try capture(field, "variables-adjacent-\(suffix)-\(focused ? "focused" : "unfocused")")
            }
        }
        window.makeFirstResponder(nil); field.font = .monospacedSystemFont(ofSize: 13, weight: .regular); field.stringValue = source; settle()
        // A hover must also preserve an in-progress field editor's native Undo.
        window.makeFirstResponder(field); settle()
        let input = field.currentEditor() as! NSTextView, inputUndo = (field.currentEditor() as! NSTextView).undoManager!
        inputUndo.removeAllActions(); inputUndo.groupsByEvent = false; inputUndo.beginUndoGrouping()
        input.insertText("/edited", replacementRange: NSRange(location: (input.string as NSString).length, length: 0))
        inputUndo.endUndoGrouping()
        precondition(inputUndo.canUndo, "Typing in the source registers native Undo")
        hover(highlighter, field, name: "host"); highlighter.closePreview()
        precondition(inputUndo.canUndo, "Opening a value editor retains the source Undo stack")
        inputUndo.undo(); inputUndo.groupsByEvent = true
        precondition((field.currentEditor() as? NSTextView)?.string == source, "Hover preserves source-field Undo across the shared editor handoff: \(String(describing: (field.currentEditor() as? NSTextView)?.string)) expected \(source)")
        window.makeFirstResponder(nil); settle()
        let bodyHelper = controller.body.variableHighlighter!
        hover(bodyHelper, controller.body.text, name: "host"); bodyHelper.closePreview()
        window.makeFirstResponder(controller.body.text)
        hover(bodyHelper, controller.body.text, name: "missing"); bodyHelper.closePreview()
        let undo = controller.body.text.undoManager!, originalBody = controller.body.text.string
        undo.removeAllActions(); undo.groupsByEvent = false; undo.beginUndoGrouping()
        controller.body.text.insertText("text", replacementRange: NSRange(location: 0, length: 0)); undo.endUndoGrouping()
        bodyHelper.refresh(); undo.undo()
        precondition(controller.body.text.string == originalBody, "Rounded decorations preserve native undo")
        undo.groupsByEvent = true
        window.makeFirstResponder(nil); settle()
        highlighter.showPreview(for: highlighter.references.first { $0.name == "long" }!); settle()
        let longEditor = highlighter.previewController!.valueEditor
        precondition(longEditor.text.string == longValue && longEditor.text.textContainer?.maximumNumberOfLines == 0, "Full multiline/unbroken values are retained without truncation")
        longEditor.text.scrollRangeToVisible(NSRange(location: (longValue as NSString).length - 9, length: 9)); settle()
        precondition(longEditor.text.visibleRect.maxY >= longEditor.text.layoutManager!.usedRect(for: longEditor.text.textContainer!).maxY - 20, "The end of a long value is reachable by scrolling")
        highlighter.closePreview()
        // Save existing, missing, disabled and intentionally empty values through the editor.
        for (name, value) in [("host", "https://edited.example.test\ncafé 📨"), ("missing", "new value"), ("disabled", "enabled value"), ("newEmpty", "")] {
            if name == "newEmpty" { field.stringValue += "/{{newEmpty}}"; settle() }
            hover(highlighter, field, name: name)
            let preview = highlighter.previewController!, editor = preview.valueEditor.text
            preview.view.window!.makeKey(); preview.view.window!.makeFirstResponder(editor)
            editor.insertText(value.isEmpty ? "x" : value, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            if value.isEmpty { editor.insertText("", replacementRange: NSRange(location: 0, length: 1)) }
            settle()
            precondition(!preview.saveButton.isHiddenOrHasHiddenAncestor && preview.hasUnsavedChanges, "Save appears after editing a defined or missing variable")
            for item in [preview.nameLabel, preview.environmentLabel, preview.valueEditor, preview.saveButton] as [NSView] {
                precondition(preview.view.bounds.contains(item.convert(item.bounds, to: preview.view)), "Growing the editor to show Save keeps all content inside the popover")
                let root = preview.view.window!.contentView!
                precondition(root.bounds.contains(item.convert(item.bounds, to: root)), "Popover window does not clip its editor: root=\(root.bounds), view=\(preview.view.frame), item=\(item.convert(item.bounds, to: root)), preferred=\(preview.preferredContentSize), size=\(highlighter.popover!.contentSize)")
                let frame = root.superview!
                precondition(frame.bounds.contains(item.convert(item.bounds, to: frame)), "Popover frame does not clip content after resizing: frame=\(frame.bounds), item=\(item.convert(item.bounds, to: frame))")
            }
            if name == "host" { try capture(preview.view.window!.contentView!.superview!, "variables-preview-editing") }
            let inputBox = preview.valueEditor.convert(preview.valueEditor.bounds, to: preview.view)
            let buttonBox = preview.saveButton.convert(preview.saveButton.bounds, to: preview.view)
            precondition(buttonBox.minX >= inputBox.maxX + 7 && abs(buttonBox.midY - inputBox.midY) < 1, "Save sits to the right of the input, centered vertically")
            if name == "missing" {
                precondition(preview.valueEditor.frame.height == 28, "A single-line value uses the compact 28-point input")
                let text = preview.valueEditor.text, box = text.layoutManager!.usedRect(for: text.textContainer!).offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
                precondition(abs(box.midY - text.visibleRect.midY) < 1, "Single-line text is vertically centered in the input")
                try capture(preview.view.window!.contentView!.superview!, "variables-preview-single-line-editing")
                let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: preview.view.window!.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                NSApp.sendEvent(enter)
            } else { preview.saveButton.performClick(nil) }
            waitFor { highlighter.popover == nil }
            precondition(development.variables[name] == value, "Inline Save updates/enables the value in the active environment")
            let json = try Postman.read(Data(contentsOf: controller.store.directory.appendingPathComponent("workspace.json")))
            let saved = try Environment(json: (json["environments"] as! [JSON])[0])
            precondition(saved.variables[name] == value, "Save persists the value before closing the preview")
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil); settle()
        }
        precondition(development.values.first!.extra["metadata"] as? String == "preserve" && development.values.first!.extra["type"] as? String == "secret", "Editing preserves original variable metadata")
        precondition(staging.variables["host"] == "https://staging.example.test", "Inline Save cannot change another environment")
        // An environment switch closes a pending edit instead of applying it to another environment.
        hover(highlighter, field, name: "host")
        let stale = highlighter.previewController!
        stale.valueEditor.text.insertText("unsaved", replacementRange: NSRange(location: 0, length: (stale.valueEditor.text.string as NSString).length))
        controller.store.selectedEnvironment = 1; controller.refreshEnvironments(); settle()
        precondition(highlighter.popover == nil, "Switching environments dismisses the stale draft")
        stale.saveButton.performClick(nil); settle()
        precondition(staging.variables["host"] == "https://staging.example.test", "A stale Save is rejected")
        controller.store.selectedEnvironment = 0; controller.refreshEnvironments(); settle()
        for width: CGFloat in [980, 1200] {
            window.setContentSize(NSSize(width: width, height: 700)); settle()
            field.stringValue = "{{host}}/{{absent}}/{{empty}}"; settle()
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                window.appearance = NSAppearance(named: appearance); settle()
                try capture(window.contentView!.superview!, "variables-window-\(Int(width))-\(suffix)")
                hover(highlighter, field, name: "host"); settle()
                try capture(window.contentView!.superview!, "variables-window-hover-\(Int(width))-\(suffix)")
                try capture(highlighter.previewController!.view.window!.contentView!.superview!, "variables-preview-\(Int(width))-\(suffix)")
                highlighter.closePreview()
            }
        }
        controller.store.selectedEnvironment = -1; controller.refreshEnvironments()
        hover(highlighter, field, name: "host"); settle()
        precondition(highlighter.previewController?.valueEditor.text.isEditable == false && highlighter.previewController!.saveButton.isHiddenOrHasHiddenAncestor, "No environment does not silently write into an arbitrary environment")
        highlighter.closePreview()
        for editor in [controller.params, controller.headers, controller.form, controller.authFields] { precondition(editor.variableContext === controller.variableContext) }
        print("Passed adjacent-reference rendering, native hover/immediate dismissal, source focus/undo, compact centered values, right-side Save and Enter, full long values, persistence/metadata, and stale-environment protection")
    }
}
