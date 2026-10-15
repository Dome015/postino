import AppKit

struct VariableReference {
    let name: String
    let range: NSRange
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
    static func matches(in text: String, range: NSRange? = nil) -> [VariableReference] {
        let source = text as NSString
        return pattern.matches(in: text, range: range ?? NSRange(location: 0, length: source.length)).map {
            VariableReference(name: source.substring(with: $0.range(at: 1)), range: $0.range)
        }
    }
    static func background(defined: Bool, hovered: Bool = false) -> NSColor {
        (defined ? accent : NSColor.systemRed).withAlphaComponent(hovered ? 0.42 : 0.24)
    }
}

/// The identity binds edits to the environment that was active when the preview opened.
final class VariablePreviewContext {
    static let didChange = Notification.Name("PostinoVariablePreviewContextDidChange")
    private(set) var environmentID: ObjectIdentifier?
    private(set) var environmentName: String?
    private(set) var values: [String: String] = [:]
    var save: ((String, String, ObjectIdentifier, @escaping (Bool) -> Void) -> Void)?
    func update(id: ObjectIdentifier?, name: String?, values: [String: String]) {
        guard id != environmentID || name != environmentName || values != self.values else { return }
        environmentID = id; environmentName = name; self.values = values
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// A compact plain-text editor: Return saves, Shift-Return inserts a newline.
final class VariableValueTextView: NSTextView {
    private let valueUndoManager = UndoManager()
    override var undoManager: UndoManager? { valueUndoManager }
    var submit: (() -> Void)?
    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() || NSApp.currentEvent?.modifierFlags.contains(.shift) == true { super.insertNewline(sender) }
        else { submit?() }
    }
}

final class VariableValueEditor: NSView, NSTextViewDelegate {
    let text = VariableValueTextView(), scroll = NSScrollView()
    var changed: ((String) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.textColor = .labelColor
        text.isRichText = false; text.allowsUndo = true; text.delegate = self
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false; text.isAutomaticSpellingCorrectionEnabled = false
        text.drawsBackground = false; text.textContainerInset = NSSize(width: 12, height: 6)
        text.textContainer?.lineFragmentPadding = 0; text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.drawsBackground = false; scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        pin(scroll, in: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { inputBackgroundColor.setFill(); bounds.fill() }
    override func layout() {
        super.layout()
        let size = scroll.contentSize
        text.minSize = size; text.setFrameSize(NSSize(width: size.width, height: max(size.height, text.frame.height)))
        if let manager = text.layoutManager, let container = text.textContainer {
            manager.ensureLayout(for: container)
            let height = max(ceil(manager.usedRect(for: container).height), ceil(manager.defaultLineHeight(for: text.font!)))
            let inset = max(6, (size.height - height) / 2)
            text.textContainerInset = NSSize(width: 12, height: inset)
            text.setFrameSize(NSSize(width: size.width, height: max(size.height, height + inset * 2)))
        }
    }
    var fittingHeight: CGFloat {
        guard let manager = text.layoutManager, let container = text.textContainer else { return 28 }
        manager.ensureLayout(for: container)
        return max(28, ceil(manager.usedRect(for: container).height) + 12)
    }
    func set(_ value: String) { text.string = value; needsLayout = true }
    func textDidChange(_ notification: Notification) { needsLayout = true; changed?(text.string) }
}

final class VariablePreviewController: NSViewController {
    let nameLabel = label("", size: 13, weight: .semibold)
    let environmentLabel = label("", size: 11, color: .secondaryLabelColor)
    let hint = NSTextField(wrappingLabelWithString: "")
    let valueEditor = VariableValueEditor(frame: .zero)
    let saveButton = RelayButton(frame: .zero)
    private var editorHeight: NSLayoutConstraint!
    private var contentHeight: NSLayoutConstraint!
    private var originalValue = ""
    private var wasMissing = false, edited = false, saving = false
    private(set) var environmentID: ObjectIdentifier?
    var save: ((String, @escaping (Bool) -> Void) -> Void)?
    var saved: (() -> Void)?
    var resized: ((NSSize) -> Void)?
    var hasUnsavedChanges: Bool { valueEditor.text.string != originalValue || (wasMissing && edited) }
    init(name: String, context: VariablePreviewContext) {
        super.init(nibName: nil, bundle: nil)
        environmentID = context.environmentID
        nameLabel.stringValue = "{{\(name)}}"
        nameLabel.lineBreakMode = .byCharWrapping; nameLabel.maximumNumberOfLines = 0
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        valueEditor.text.setAccessibilityLabel("Value of \(name)")
        valueEditor.text.isAutomaticSpellingCorrectionEnabled = false
        valueEditor.changed = { [weak self] _ in self?.edited = true; self?.updateEditingState() }
        editorHeight = valueEditor.heightAnchor.constraint(equalToConstant: 28); editorHeight.isActive = true
        saveButton.title = "Save"; saveButton.style = .primary
        saveButton.target = self; saveButton.action = #selector(saveValue)
        valueEditor.text.submit = { [weak self] in self?.saveValue() }
        saveButton.isHidden = true
        valueEditor.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let content = stack([nameLabel, environmentLabel, hint, stack([valueEditor, saveButton])], vertical: true, spacing: 8)
        content.alignment = .width
        view = padded(content, x: 12, y: 12)
        view.widthAnchor.constraint(equalToConstant: 340).isActive = true
        contentHeight = view.heightAnchor.constraint(equalToConstant: 120); contentHeight.isActive = true
        update(name: name, context: context)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(name: String, context: VariablePreviewContext) {
        environmentLabel.stringValue = context.environmentName.map { "Environment: \($0)" } ?? "No environment selected"
        environmentLabel.lineBreakMode = .byCharWrapping; environmentLabel.maximumNumberOfLines = 0
        if !hasUnsavedChanges && !saving {
            originalValue = context.values[name] ?? ""; wasMissing = context.values[name] == nil; edited = false
            if valueEditor.text.string != originalValue { valueEditor.set(originalValue) }
        }
        valueEditor.text.isEditable = context.environmentID != nil
        hint.stringValue = context.environmentID == nil ? "Select an environment to save a value." : wasMissing ? "Not defined in this environment. Enter a value to add it." : ""
        hint.isHidden = hint.stringValue.isEmpty
        updateEditingState()
    }
    private func updateEditingState() {
        saveButton.isHidden = !hasUnsavedChanges
        saveButton.isEnabled = environmentID != nil && !saving
        resize()
    }
    private func resize() {
        // Wrap even unbroken tokens, and scroll very large values instead of truncating them.
        if view.window == nil { view.setFrameSize(NSSize(width: 340, height: contentHeight.constant)) }
        view.layoutSubtreeIfNeeded()
        let limit = min(CGFloat(240), ((view.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) * 0.4)
        editorHeight.constant = min(limit, valueEditor.fittingHeight)
        let labels = [nameLabel, environmentLabel, hint].filter { !$0.isHidden }
        let labelHeight = labels.reduce(CGFloat(0)) { height, label in
            height + ceil((label.stringValue as NSString).boundingRect(with: NSSize(width: 316, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: label.font!]).height) + 2
        }
        let gaps = CGFloat(labels.count) * 8
        preferredContentSize = NSSize(width: 340, height: 24 + labelHeight + editorHeight.constant + gaps)
        // Let NSPopover resize its window before changing the content frame;
        // pre-sizing the view makes AppKit see no size delta and clips the header.
        resized?(preferredContentSize)
        contentHeight.constant = preferredContentSize.height
        if view.window == nil { view.setFrameSize(preferredContentSize) }
        view.layoutSubtreeIfNeeded()
    }
    @objc private func saveValue() {
        guard hasUnsavedChanges, !saving, environmentID != nil, let save else { return }
        saving = true; saveButton.title = "Saving…"; updateEditingState()
        save(valueEditor.text.string) { [weak self] success in
            guard let self else { return }
            if success { self.saved?() }
            else { self.saving = false; self.saveButton.title = "Save"; self.hint.stringValue = "The environment changed. Reopen the variable to edit it."; self.hint.isHidden = false; self.updateEditingState() }
        }
    }
}

/// Draw behind native glyphs; decorations never alter text storage, selection or undo.
final class VariableReferenceHighlighter: NSObject {
    private weak var field: NSTextField?
    private weak var textView: NSTextView?
    private var owner: NSView? { field ?? textView }
    private var observers: [NSObjectProtocol] = []
    private var editorObserver: NSObjectProtocol?
    private weak var observedEditor: NSTextView?
    private var contextObserver: NSObjectProtocol?
    private var tracking: NSTrackingArea?
    private var eventMonitor: Any?
    private var refreshing = false
    private var presentedReference: VariableReference?
    private let fieldStorage = NSTextStorage()
    private let fieldLayout = NSLayoutManager()
    private let fieldContainer = NSTextContainer(size: .zero)
    private var fieldOrigin = NSPoint.zero
    private var fieldSource: NSAttributedString?
    private(set) var references: [VariableReference] = []
    private(set) var popover: NSPopover?
    private(set) var previewController: VariablePreviewController?
    var context: VariablePreviewContext? {
        didSet {
            if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
            contextObserver = context.map { context in
                NotificationCenter.default.addObserver(forName: VariablePreviewContext.didChange, object: context, queue: .main) { [weak self] _ in self?.refresh() }
            }
            refresh()
        }
    }
    init(field: NSTextField) {
        self.field = field; super.init()
        fieldContainer.lineFragmentPadding = 0
        fieldStorage.addLayoutManager(fieldLayout); fieldLayout.addTextContainer(fieldContainer)
        installEvents()
        for name in [NSControl.textDidBeginEditingNotification, NSControl.textDidChangeNotification, NSControl.textDidEndEditingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: field, queue: .main) { [weak self] _ in
                self?.refresh()
                if name == NSControl.textDidEndEditingNotification { DispatchQueue.main.async { [weak self] in self?.refresh() } }
            })
        }
    }
    init(textView: NSTextView) { self.textView = textView; super.init(); installEvents() }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let editorObserver { NotificationCenter.default.removeObserver(editorObserver) }
        if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let tracking { owner?.removeTrackingArea(tracking) }
        popover?.close()
    }
    private func installEvents() {
        guard let owner else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        owner.addTrackingArea(area); tracking = area
        // A focused NSTextField is covered by AppKit's shared field editor, so
        // its tracking area alone cannot receive hover events. Observe the window events too.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            self?.handle(event); return event
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.closePreview() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            if let window = note.object as? NSWindow, window === self?.owner?.window { self?.closePreview() }
        })
    }
    func handle(_ event: NSEvent) {
        guard let owner, let window = owner.window, !owner.isHiddenOrHasHiddenAncestor else { closePreview(); return }
        if event.type == .mouseMoved || event.type == .mouseEntered || event.type == .mouseExited {
            if overlapsPreview(event) { return }
            if event.window === window { mouseMoved(with: event) } else { closePreview() }
        } else if event.window === previewController?.view.window {
            if event.type == .keyDown && event.keyCode == 53 { closePreview() }
        } else if event.type == .leftMouseDown {
            let point = owner.convert(event.locationInWindow, from: nil)
            if event.window !== window || !rectsForPresentedReference().contains(where: { $0.contains(point) }) { closePreview() }
        } else if event.type == .scrollWheel, event.window === window { closePreview() }
        else if event.type == .keyDown && event.keyCode == 53 { closePreview() }
    }
    private func overlapsPreview(_ event: NSEvent) -> Bool {
        guard let preview = previewController?.view.window, let eventWindow = event.window else { return false }
        return preview.frame.contains(eventWindow.convertPoint(toScreen: event.locationInWindow))
    }
    func refresh() {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        let editor = textView ?? field?.currentEditor() as? NSTextView
        if field != nil, observedEditor !== editor {
            if let editorObserver { NotificationCenter.default.removeObserver(editorObserver) }; editorObserver = nil
            observedEditor = editor
            if let clip = editor?.enclosingScrollView?.contentView ?? editor?.superview as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                editorObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.invalidate() }
            }
        }
        guard editor?.hasMarkedText() != true else { return }
        let source = editor?.string ?? field?.stringValue ?? "", length = (source as NSString).length
        var range = NSRange(location: 0, length: length)
        if textView != nil, let editor, let manager = editor.layoutManager, let container = editor.textContainer {
            let visible = editor.visibleRect.offsetBy(dx: -editor.textContainerInset.width, dy: -editor.textContainerInset.height)
            let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
            let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            if chars.location != NSNotFound {
                let start = max(0, min(length, chars.location) - 2048), end = min(length, min(length, NSMaxRange(chars)) + 2048)
                range = NSRange(location: start, length: max(0, end - start))
            } else { range = NSRange(location: 0, length: min(length, 8192)) }
        }
        references = context == nil ? [] : VariableReference.matches(in: source, range: range)
        invalidate()
        if let reference = presentedReference, popover?.isShown == true {
            if let context, context.environmentID == previewController?.environmentID, references.contains(where: { $0.name == reference.name && $0.range == reference.range }) {
                previewController?.update(name: reference.name, context: context)
            } else { closePreview() }
        }
    }
    private func invalidate() {
        owner?.needsDisplay = true
        (field?.currentEditor() as? NSTextView)?.needsDisplay = true
    }
    private func prepareFieldLayout() -> Bool {
        guard let field, !(field is NSSecureTextField) else { return false }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byClipping
        let source = NSAttributedString(string: field.stringValue, attributes: [.font: field.font ?? .systemFont(ofSize: 13), .foregroundColor: field.textColor ?? .labelColor, .paragraphStyle: style])
        if fieldSource?.isEqual(to: source) != true { fieldStorage.setAttributedString(source); fieldSource = source }
        let textRect = field.cell?.drawingRect(forBounds: field.bounds) ?? field.bounds
        fieldContainer.containerSize = NSSize(width: max(textRect.width, source.size().width + 1), height: CGFloat.greatestFiniteMagnitude)
        fieldLayout.ensureLayout(for: fieldContainer)
        let used = fieldLayout.usedRect(for: fieldContainer)
        fieldOrigin = NSPoint(x: textRect.minX, y: textRect.minY + (textRect.height - used.height) / 2)
        return true
    }
    private func glyphRects(_ reference: VariableReference, manager: NSLayoutManager, origin: NSPoint) -> [NSRect] {
        guard NSMaxRange(reference.range) <= (manager.textStorage?.length ?? 0) else { return [] }
        let glyphs = manager.glyphRange(forCharacterRange: reference.range, actualCharacterRange: nil)
        var boxes: [NSRect] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, container, lineGlyphs, _ in
            let box = manager.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, lineGlyphs), in: container)
            boxes.append(box.offsetBy(dx: origin.x, dy: origin.y))
        }
        return boxes
    }
    func rects(for reference: VariableReference) -> [NSRect] {
        guard let owner else { return [] }
        if let editor = textView ?? field?.currentEditor() as? NSTextView, let manager = editor.layoutManager,
           NSMaxRange(reference.range) <= (editor.string as NSString).length {
            let viewport = owner.convert(editor.visibleRect, from: editor).intersection(owner.visibleRect)
            return glyphRects(reference, manager: manager, origin: editor.textContainerOrigin).map { owner.convert($0, from: editor).intersection(viewport) }.filter { !$0.isEmpty }
        }
        guard prepareFieldLayout() else { return [] }
        let viewport = (field?.cell?.drawingRect(forBounds: owner.bounds) ?? owner.bounds).intersection(owner.visibleRect)
        return glyphRects(reference, manager: fieldLayout, origin: fieldOrigin).map { $0.intersection(viewport) }.filter { !$0.isEmpty }
    }
    /// Return true only when the shared TextKit layout drew the unfocused field.
    func drawField(in dirtyRect: NSRect) -> Bool {
        guard let field, !(field is NSSecureTextField) else { draw(in: dirtyRect); return false }
        if field.currentEditor() != nil { draw(in: dirtyRect); return false }
        guard !references.isEmpty, prepareFieldLayout() else { return false }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let textRect = field.cell?.drawingRect(forBounds: field.bounds) ?? field.bounds
        textRect.clip()
        paint(using: fieldLayout, origin: fieldOrigin)
        fieldLayout.drawGlyphs(forGlyphRange: fieldLayout.glyphRange(for: fieldContainer), at: fieldOrigin)
        return true
    }
    private func paint(using manager: NSLayoutManager, origin: NSPoint) {
        for reference in references {
            VariableReference.background(defined: context?.values[reference.name] != nil, hovered: popover?.isShown == true && presentedReference?.range == reference.range).setFill()
            for rect in glyphRects(reference, manager: manager, origin: origin) { NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill() }
        }
    }
    func rect(for reference: VariableReference) -> NSRect? { rects(for: reference).first }
    private func rectsForPresentedReference() -> [NSRect] { presentedReference.map { rects(for: $0) } ?? [] }
    func draw(in dirtyRect: NSRect) {
        guard let owner, let editor = textView ?? field?.currentEditor() as? NSTextView, let manager = editor.layoutManager else { return }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        // Clip the original rounded shape, rather than rounding a truncated
        // fragment again when a reference is partly outside the text viewport.
        owner.convert(editor.visibleRect, from: editor).intersection(owner.visibleRect).clip()
        for reference in references {
            let hovered = popover?.isShown == true && presentedReference?.range == reference.range
            VariableReference.background(defined: context?.values[reference.name] != nil, hovered: hovered).setFill()
            for box in glyphRects(reference, manager: manager, origin: editor.textContainerOrigin) {
                let rect = owner.convert(box, from: editor)
                guard rect.intersects(dirtyRect) else { continue }
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
        }
    }
    @objc(mouseMoved:) func mouseMoved(with event: NSEvent) {
        guard let owner else { return }
        if overlapsPreview(event) { return }
        let point = owner.convert(event.locationInWindow, from: nil)
        guard let reference = references.first(where: { rects(for: $0).contains(where: { $0.contains(point) }) }) else { closePreview(); return }
        if presentedReference?.range == reference.range && popover?.isShown == true { return }
        showPreview(for: reference)
    }
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { handle(event) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { handle(event) }
    func showPreview(for reference: VariableReference) {
        guard let context, let owner, let window = owner.window, !owner.isHiddenOrHasHiddenAncestor,
              references.contains(where: { $0.name == reference.name && $0.range == reference.range }),
              let rect = rect(for: reference), !rect.isEmpty else { return }
        closePreview(); presentedReference = reference
        let controller = VariablePreviewController(name: reference.name, context: context)
        let environmentID = context.environmentID
        controller.save = { [weak context] value, completion in
            guard let context, let environmentID, context.environmentID == environmentID, let save = context.save else { completion(false); return }
            save(reference.name, value, environmentID, completion)
        }
        controller.saved = { [weak self] in self?.closePreview() }
        controller.resized = { [weak self] size in self?.popover?.contentSize = size }
        let popover = NSPopover(); popover.behavior = .applicationDefined; popover.animates = false; popover.contentViewController = controller
        self.popover = popover; previewController = controller
        let responder = window.firstResponder
        let fieldEditor = responder as? NSTextView
        let focusedField = fieldEditor?.isFieldEditor == true ? ((fieldEditor?.delegate as? NSTextField) ?? (field?.currentEditor() === fieldEditor ? field : nil)) : nil
        let selection = fieldEditor?.selectedRange()
        popover.show(relativeTo: rect, of: owner, preferredEdge: .minY)
        let tooltipArea = controller.view.window?.contentView?.superview ?? controller.view
        tooltipArea.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        // Hover must not steal the source caret; clicking the value opts into editing.
        window.makeKey()
        if let focusedField {
            // Showing an editable popover detaches AppKit's shared field editor.
            // Refocus the control to reattach it, then restore the caret/selection.
            window.makeFirstResponder(focusedField)
            if let selection { (focusedField.currentEditor() as? NSTextView)?.setSelectedRange(selection) }
        } else if responder === window { window.makeFirstResponder(nil) }
        else if let responder { window.makeFirstResponder(responder) }
        invalidate()
    }
    func closePreview() {
        popover?.close(); popover = nil; previewController = nil; presentedReference = nil
        invalidate()
    }
}
