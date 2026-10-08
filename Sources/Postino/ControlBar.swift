import AppKit

/// Each toolbar is a background band; individual controls keep their own flat fill.
final class ControlBar: Surface {
    init(_ controls: [NSView], color: NSColor = bandLightColor) {
        super.init(color)
        pin(padded(stack(controls, spacing: 6), x: 10, y: 8), in: self)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A flat, opaque capsule shared by inputs, dropdowns and request tabs.
final class ControlSurface: NSView {
    let fill: NSColor
    let radius: CGFloat
    init(content: NSView = NSView(), radius: CGFloat = 14, fill: NSColor = controlFillColor) {
        self.fill = fill; self.radius = radius; super.init(frame: .zero)
        setAccessibilityElement(false); pin(content, in: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keeps native control interaction above an independent, consistently shaped flat surface.
final class ControlChrome {
    weak var control: NSView?
    let surface: ControlSurface
    init(_ control: NSView, fill: NSColor? = nil) { self.control = control; surface = ControlSurface(fill: fill ?? controlFillColor) }
    func attach() {
        surface.removeFromSuperview()
        guard let control, let parent = control.superview else { return }
        surface.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(surface, positioned: .below, relativeTo: control)
        NSLayoutConstraint.activate([surface.leadingAnchor.constraint(equalTo: control.leadingAnchor), surface.trailingAnchor.constraint(equalTo: control.trailingAnchor), surface.topAnchor.constraint(equalTo: control.topAnchor), surface.bottomAnchor.constraint(equalTo: control.bottomAnchor)])
    }
    deinit { surface.removeFromSuperview() }
}

/// Outline cell content always uses the row's vertical center, including folder labels.
final class TreeCellView: NSTableCellView {
    let content: NSView
    init(_ content: NSView) {
        self.content = content; super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor), content.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A visible resize affordance, matching the sidebar's thin black divider.
final class ResizeSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) { NSColor.black.setFill(); rect.fill() }
}
