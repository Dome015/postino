import AppKit

/// Wheel and trackpad gestures move the tab strip along its single scrollable axis.
final class RequestTabScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = RequestTabClipView()
        hasHorizontalScroller = true; hasVerticalScroller = false; autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none; verticalScrollElasticity = .none
        drawsBackground = true; backgroundColor = bandDarkColor
        contentView.drawsBackground = true; contentView.backgroundColor = bandDarkColor
    }
    required init?(coder: NSCoder) { fatalError() }
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        // Use the dominant axis so diagonal trackpad gestures don't double the speed.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : horizontalLineScroll
        let maxX = max(0, documentView.frame.width - contentView.bounds.width)
        let x = min(maxX, max(0, contentView.bounds.origin.x - delta * scale))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

/// Also prevent programmatic visibility changes and scrollbar actions from moving vertically.
private final class RequestTabClipView: NSClipView {
    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: newOrigin.x, y: 0))
    }
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.y = 0
        return bounds
    }
}
