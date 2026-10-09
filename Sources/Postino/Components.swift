import AppKit
import RelayCore
let accent = NSColor(srgbRed: 0, green: 183.0 / 255, blue: 115.0 / 255, alpha: 1)
let accentInk = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? accent : NSColor(srgbRed: 0, green: 0.40, blue: 0.25, alpha: 1) }
let primaryInk = NSColor(srgbRed: 0.02, green: 0.12, blue: 0.08, alpha: 1)
func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField { let l = NSTextField(labelWithString: text); l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; l.lineBreakMode = .byTruncatingTail; return l }
func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView { let s = NSStackView(views: views); s.orientation = vertical ? .vertical : .horizontal; s.alignment = vertical ? .leading : .centerY; s.spacing = spacing; s.distribution = .fill; if vertical { for v in views { v.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: s.leadingAnchor), v.trailingAnchor.constraint(equalTo: s.trailingAnchor)]) } }; return s }
enum ButtonStyle { case secondary, primary, plain, tab }
/// Native buttons keep AppKit interaction and focus with a deliberately flat bezel.
final class FlatButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard let button = controlView as? RelayButton, button.isBordered else { return }
        var fill = button.style == .primary ? accent : controlFillColor
        if isHighlighted { fill = fill.blended(withFraction: 0.14, of: .black) ?? fill }
        if !isEnabled { fill = fill.blended(withFraction: 0.45, of: bandLightColor) ?? fill }
        fill.setFill(); NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14).fill()
    }
}

final class RelayButton: NSButton {
    var style: ButtonStyle = .secondary { didSet { applyStyle() } }
    override var allowsVibrancy: Bool { false }
    override var title: String { didSet { updateTitleInk() } }
    override var font: NSFont? { didSet { updateTitleInk() } }
    private func updateTitleInk() {
        if style == .primary {
            attributedTitle = NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        }
    }
    var selected = false { didSet { state = selected ? .on : .off } }
    override init(frame: NSRect) {
        super.init(frame: frame); cell = FlatButtonCell(textCell: ""); font = .systemFont(ofSize: 12, weight: .medium); controlSize = .small
        setButtonType(.momentaryPushIn); focusRingType = .default; applyStyle()
        setContentHuggingPriority(.required, for: .horizontal); setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical); setContentCompressionResistancePriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError() }
    private func applyStyle() {
        isBordered = style != .plain && style != .tab
        bezelStyle = .rounded
        bezelColor = style == .primary ? accent : nil
        contentTintColor = style == .primary ? .white : .labelColor
        updateTitleInk()
        invalidateIntrinsicContentSize(); needsDisplay = true
    }
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override var intrinsicContentSize: NSSize {
        let measured = super.intrinsicContentSize
        let text = ceil((title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width)
        return NSSize(width: max(title.isEmpty ? 28 : text + 24, measured.width), height: 28)
    }
}
func button(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector) -> RelayButton { let b = RelayButton(frame: .zero); b.title = title; b.target = target; b.action = action; if title.isEmpty, let symbol = symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); b.imagePosition = .imageLeading }; return b }
let bandLightColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1) }
let bandDarkColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.91, alpha: 1) }
let controlFillColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.21, alpha: 1) : NSColor(white: 0.85, alpha: 1) }
let selectedTabColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.05, green: 0.27, blue: 0.20, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.90, blue: 0.83, alpha: 1) }
let canvasColor = bandLightColor
let inputBackgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.98, alpha: 1) }
let editorColor = inputBackgroundColor
let sidebarColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.105, alpha: 1) : NSColor(white: 0.965, alpha: 1) }
class Surface: NSView { let color: NSColor; init(_ color: NSColor) { self.color = color; super.init(frame: .zero) }; required init?(coder: NSCoder) { fatalError() }; override func draw(_ dirtyRect: NSRect) { color.setFill(); NSIntersectionRect(bounds, dirtyRect).fill() }; override func viewDidChangeEffectiveAppearance() { needsDisplay = true } }
func band(_ content: NSView, color: NSColor, name: String) -> Surface { let view = Surface(color); view.identifier = .init(name); pin(content, in: view); return view }
func compact(_ control: NSControl, height: CGFloat = 28) { control.controlSize = control is RelaySegments ? .large : .small; control.font = .systemFont(ofSize: 12); control.heightAnchor.constraint(equalToConstant: height).isActive = true }
func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.init(1), for: .horizontal); return v }
func pin(_ child: NSView, in parent: NSView, inset: CGFloat = 0, verticalInset: CGFloat? = nil) { child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child); let vertical = verticalInset ?? inset; NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: vertical), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -vertical)]) }
func rule() -> NSView { let v = NSBox(); v.boxType = .separator; return v }
func padded(_ view: NSView, x: CGFloat = 10, y: CGFloat = 8) -> NSView { padded(view, x: x, top: y, bottom: y) }
func padded(_ view: NSView, x: CGFloat = 10, top: CGFloat, bottom: CGFloat) -> NSView { let host = NSView(); view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view); NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: x), view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -x), view.topAnchor.constraint(equalTo: host.topAnchor, constant: top), view.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -bottom)]); return host }
func methodColor(_ method: String) -> NSColor { switch method { case "GET": return .systemGreen; case "POST": return .systemOrange; case "DELETE": return .systemRed; case "PUT", "PATCH": return .systemBlue; default: return .secondaryLabelColor } }
/// Native segmented controls keep selection, keyboard navigation, and accessibility consistent.
final class RelaySegments: NSSegmentedControl {
    init(labels: [String], trackingMode: NSSegmentedControl.SwitchTracking, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero); segmentCount = labels.count; self.trackingMode = trackingMode; self.target = target; self.action = action
        font = .systemFont(ofSize: 12); controlSize = .large; segmentStyle = .rounded; selectedSegmentBezelColor = accent
        if #available(macOS 26.0, *) { borderShape = .capsule }
        for (index, label) in labels.enumerated() { setLabel(label, forSegment: index); setWidth(ceil((label as NSString).size(withAttributes: [.font: font!]).width) + 24, forSegment: index) }
        selectedSegment = 0
        setContentHuggingPriority(.required, for: .horizontal); setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
}
private final class FlatPopupCell: NSPopUpButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {}
    override func drawInterior(withFrame frame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: frame, in: controlView)
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold).applying(.init(paletteColors: [.labelColor]))
        let arrow = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        arrow?.draw(in: NSRect(x: frame.maxX - 20, y: frame.midY - 6, width: 9, height: 12), from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true, hints: nil)
    }
}
/// Native popup menus and focus, with the same flat surface as inputs and tabs.
final class RelayPopup: NSPopUpButton {
    private var chrome: ControlChrome?
    var controlSurface: ControlSurface? { chrome?.surface }
    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        cell = FlatPopupCell(textCell: "", pullsDown: pullsDown)
        font = .systemFont(ofSize: 12); controlSize = .small; isBordered = true; bezelStyle = .rounded
        chrome = ControlChrome(self)
    }
    convenience init() { self.init(frame: .zero, pullsDown: false) }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { false }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); chrome?.attach() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill() }
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override var intrinsicContentSize: NSSize {
        let longest = itemTitles.map { ($0 as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width }.max() ?? 0
        return NSSize(width: max(super.intrinsicContentSize.width, ceil(longest) + 36), height: 28)
    }
}
final class WorkCancellation {
    private let lock = NSLock(); private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

/// One bounded hit target and its close control share a single tab surface.
final class RequestTabView: NSView {
    private let select = TabHitButton(frame: .zero)
    private let close: RelayButton
    private let methodLabel: NSTextField
    private let titleLabel: NSTextField
    private let dirty: Bool
    private let active: Bool
    private let content = NSView()
    private let dirtyDot = NSView()
    init(request: RequestItem, dirty: Bool, active: Bool, index: Int, target: MainWindow) {
        self.dirty = dirty; self.active = active
        methodLabel = label(request.method, size: 10, weight: .semibold, color: methodColor(request.method))
        methodLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold); methodLabel.lineBreakMode = .byClipping; methodLabel.cell?.isScrollable = false
        titleLabel = label(request.name, size: 12, weight: active ? .medium : .regular)
        close = button("", symbol: "xmark", target: target, action: #selector(MainWindow.closeTab(_:)))
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        setAccessibilityElement(false)
        select.title = request.name; select.isBordered = false; select.target = target; select.action = #selector(MainWindow.selectTab(_:)); select.tag = index
        select.setAccessibilityRole(.radioButton); select.setAccessibilityLabel("\(request.method) \(request.name)\(dirty ? ", unsaved changes" : "")"); select.setAccessibilityValue(active ? 1 : 0)
        close.style = .plain; close.tag = index; close.toolTip = "Close \(request.name)"; close.setAccessibilityLabel("Close \(request.name)")
        toolTip = request.url + (dirty ? " — Unsaved changes" : "")
        pin(ControlSurface(content: content, fill: active ? selectedTabColor : controlFillColor), in: self)
        content.addSubview(select); content.addSubview(methodLabel); content.addSubview(titleLabel); content.addSubview(close)
        dirtyDot.wantsLayer = true; dirtyDot.layer?.backgroundColor = accent.cgColor; dirtyDot.layer?.cornerRadius = 3; dirtyDot.isHidden = !dirty
        content.addSubview(dirtyDot)
        setAccessibilityChildren([select, close])
    }
    required init?(coder: NSCoder) { fatalError() }
    static func methodWidth(_ method: String) -> CGFloat {
        ceil((method as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)]).width) + 4
    }
    override func layout() {
        super.layout()
        let verbWidth = Self.methodWidth(methodLabel.stringValue)
        select.frame = bounds.insetBy(dx: 0, dy: 0); select.frame.size.width -= 32
        methodLabel.frame = NSRect(x: 10, y: floor((bounds.height - 14) / 2), width: verbWidth, height: 14)
        titleLabel.frame = NSRect(x: 10 + verbWidth + 6, y: floor((bounds.height - 16) / 2), width: max(0, bounds.width - verbWidth - 64), height: 16)
        dirtyDot.frame = NSRect(x: bounds.width - 38, y: (bounds.height - 6) / 2, width: 6, height: 6)
        close.frame = NSRect(x: bounds.width - 28, y: (bounds.height - 24) / 2, width: 24, height: 24)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        let local = convert(point, from: superview)
        return close.frame.contains(local) ? close : select
    }

}
private final class TabHitButton: NSButton { override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }; override func draw(_ dirtyRect: NSRect) {} }

final class AccentRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        accent.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 4, yRadius: 4).fill()
    }
}
