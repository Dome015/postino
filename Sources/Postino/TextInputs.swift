import AppKit

/// Shared geometry for single-line inputs, including the native field editor.
private enum InputStyle {
    private static let layoutManager = NSLayoutManager()
    static let height: CGFloat = 28
    static let radius: CGFloat = 14
    static func textRect(_ bounds: NSRect, font: NSFont?, inset: CGFloat = 12) -> NSRect {
        let font = font ?? .systemFont(ofSize: 13)
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        return NSRect(x: bounds.minX + inset, y: bounds.minY + floor((bounds.height - lineHeight) / 2), width: max(0, bounds.width - inset * 2), height: min(bounds.height, lineHeight))
    }
    static func configure(_ field: NSTextField) {
        field.isEditable = true; field.isSelectable = true
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false; field.backgroundColor = .clear; field.controlSize = .small
        field.font = .systemFont(ofSize: 13); field.focusRingType = .exterior
        field.cell?.usesSingleLineMode = true; field.cell?.wraps = false; field.cell?.isScrollable = true
        field.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

}
private final class InputCell: NSTextFieldCell {
    private var placingEditor = false
    override func drawingRect(forBounds rect: NSRect) -> NSRect { placingEditor ? rect : InputStyle.textRect(rect, font: font) }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        let textRect = drawingRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.select(withFrame: textRect, in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        let textRect = drawingRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.edit(withFrame: textRect, in: view, editor: editor, delegate: delegate, event: event)
    }
}
private final class SecureInputCell: NSSecureTextFieldCell {
    private var placingEditor = false
    override func drawingRect(forBounds rect: NSRect) -> NSRect { placingEditor ? rect : InputStyle.textRect(rect, font: font) }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        let textRect = drawingRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.select(withFrame: textRect, in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        let textRect = drawingRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.edit(withFrame: textRect, in: view, editor: editor, delegate: delegate, event: event)
    }
}
private final class InputSearchCell: NSSearchFieldCell {
    private var placingEditor = false
    override func drawingRect(forBounds rect: NSRect) -> NSRect { placingEditor ? rect : searchTextRect(forBounds: rect) }
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        if placingEditor { return rect }
        let native = super.searchTextRect(forBounds: rect)
        let centered = InputStyle.textRect(rect, font: font, inset: 0)
        return NSRect(x: native.minX, y: centered.minY, width: native.width, height: centered.height)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        let textRect = searchTextRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.select(withFrame: textRect, in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        let textRect = searchTextRect(forBounds: rect); placingEditor = true; defer { placingEditor = false }
        super.edit(withFrame: textRect, in: view, editor: editor, delegate: delegate, event: event)
    }
}
final class InputField: NSTextField {
    private var chrome: ControlChrome?
    override init(frame: NSRect) { super.init(frame: frame); cell = InputCell(textCell: ""); InputStyle.configure(self); chrome = ControlChrome(self, fill: inputBackgroundColor) }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { false }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); chrome?.attach() }
    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.drawsBackground = false
        return focused
    }
}
final class SecureInputField: NSSecureTextField {
    private var chrome: ControlChrome?
    override init(frame: NSRect) { super.init(frame: frame); cell = SecureInputCell(textCell: ""); InputStyle.configure(self); chrome = ControlChrome(self, fill: inputBackgroundColor) }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { false }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); chrome?.attach() }
    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.drawsBackground = false
        return focused
    }
}
final class InputSearchField: NSSearchField {
    private var chrome: ControlChrome?
    override init(frame: NSRect) { super.init(frame: frame); cell = InputSearchCell(textCell: ""); InputStyle.configure(self); chrome = ControlChrome(self, fill: inputBackgroundColor) }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { false }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); chrome?.attach() }
    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.drawsBackground = false
        return focused
    }
}
