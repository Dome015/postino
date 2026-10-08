import AppKit

/// Lexes UTF-16 in small buffers, retaining tokens only for the requested viewport.
/// Scanning the prefix keeps escaped quotes and strings spanning the viewport correct.
enum JSONSyntax {
    enum Kind { case key, string, number, literal }
    struct Token { let range: NSRange; let kind: Kind }
    static func tokens(in source: NSString, range: NSRange, initiallyInString: Bool = false, initiallyEscaped: Bool = false, cancelled: () -> Bool = { false }) -> [Token] {
        let visible = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
        guard visible.length > 0 else { return [] }
        let limit = NSMaxRange(visible)
        var buffer = [unichar](repeating: 0, count: 8192), cached = NSRange(location: NSNotFound, length: 0)
        func char(_ index: Int) -> unichar {
            guard index < source.length else { return 0 }
            if !NSLocationInRange(index, cached) {
                cached = NSRange(location: index, length: min(buffer.count, source.length - index))
                source.getCharacters(&buffer, range: cached)
            }
            return buffer[index - cached.location]
        }
        func whitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func digit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
        var result: [Token] = [], i = 0
        func emit(_ start: Int, _ end: Int, _ kind: Kind) {
            let clipped = NSIntersectionRange(NSRange(location: start, length: end - start), visible)
            if clipped.length > 0 { result.append(Token(range: clipped, kind: kind)) }
        }
        while i < limit {
            if i % 4096 == 0 && cancelled() { return [] }
            let c = char(i), start = i
            if c == 34 || (i == 0 && initiallyInString) {
                let continuing = i == 0 && initiallyInString
                if !continuing { i += 1 }; var escaped = continuing && initiallyEscaped, closed = false
                while i < limit {
                    if i % 4096 == 0 && cancelled() { return [] }
                    let next = char(i); i += 1
                    if escaped { escaped = false }
                    else if next == 92 { escaped = true }
                    else if next == 34 { closed = true; break }
                }
                var next = i
                if closed { while next < source.length && whitespace(char(next)) { if next % 4096 == 0 && cancelled() { return [] }; next += 1 } }
                emit(start, i, closed && char(next) == 58 ? .key : .string)
            } else if digit(c) || c == 45 {
                i += 1
                while i < limit && digit(char(i)) { if i % 4096 == 0 && cancelled() { return [] }; i += 1 }
                if i < limit && char(i) == 46 { i += 1; while i < limit && digit(char(i)) { if i % 4096 == 0 && cancelled() { return [] }; i += 1 } }
                if i < limit && (char(i) == 101 || char(i) == 69) {
                    i += 1; if i < limit && (char(i) == 43 || char(i) == 45) { i += 1 }
                    while i < limit && digit(char(i)) { if i % 4096 == 0 && cancelled() { return [] }; i += 1 }
                }
                emit(start, i, .number)
            } else if c >= 97 && c <= 122 {
                i += 1; while i < limit && char(i) >= 97 && char(i) <= 122 { if i % 4096 == 0 && cancelled() { return [] }; i += 1 }
                if i - start <= 5, ["true", "false", "null"].contains(source.substring(with: NSRange(location: start, length: i - start))) { emit(start, i, .literal) }
            } else { i += 1 }
        }
        return cancelled() ? [] : result
    }
}

final class EditorTextView: NSTextView {
    var responseFinder: NSTextFinder?
    var drawFindHighlights: (() -> Void)?
    override func performFindPanelAction(_ sender: Any?) {
        guard let finder = responseFinder, let item = sender as? NSValidatedUserInterfaceItem, let action = NSTextFinder.Action(rawValue: item.tag) else { super.performFindPanelAction(sender); return }
        finder.performAction(action)
    }
    override func performTextFinderAction(_ sender: Any?) {
        if responseFinder != nil { performFindPanelAction(sender) } else { super.performTextFinderAction(sender) }
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let finder = responseFinder, item.action == #selector(performFindPanelAction(_:)) || item.action == #selector(performTextFinderAction(_:)), let action = NSTextFinder.Action(rawValue: item.tag) { return finder.validateAction(action) }
        return super.validateUserInterfaceItem(item)
    }
    override func drawBackground(in rect: NSRect) { super.drawBackground(in: rect); if !isDrawingFindIndicator { drawFindHighlights?() } }
    var jumpToBoundary: ((Bool) -> Void)?
    override func moveToEndOfDocument(_ sender: Any?) { if let jumpToBoundary { jumpToBoundary(true) } else { super.moveToEndOfDocument(sender) } }
    override func moveToBeginningOfDocument(_ sender: Any?) { if let jumpToBoundary { jumpToBoundary(false) } else { super.moveToBeginningOfDocument(sender) } }
    override func scrollToEndOfDocument(_ sender: Any?) { if let jumpToBoundary { jumpToBoundary(true) } else { super.scrollToEndOfDocument(sender) } }
    override func scrollToBeginningOfDocument(_ sender: Any?) { if let jumpToBoundary { jumpToBoundary(false) } else { super.scrollToBeginningOfDocument(sender) } }
}

final class CodeEditor: NSView, NSTextViewDelegate {
    let text = EditorTextView(); let scroll = NSScrollView()
    var selectionChanged: (() -> Void)?
    var viewportChanged: (() -> Void)?
    var changed: ((String) -> Void)?; var applying = false
    var syntaxHighlighting = false { didSet { if oldValue != syntaxHighlighting { scheduleHighlight() } } }
    private let syntaxQueue = DispatchQueue(label: "postauomo.json-syntax", qos: .userInitiated)
    private var syntaxJob = WorkCancellation()
    private var generation = UUID()
    private var pending: DispatchWorkItem?
    private var initialString = false, initialEscape = false
    private var painted = NSRange(location: 0, length: 0)
    private var viewportObserver: NSObjectProtocol?

    init(editable: Bool) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.masksToBounds = true
        text.isEditable = editable; text.isRichText = false; text.allowsUndo = editable
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticSpellingCorrectionEnabled = false; text.isContinuousSpellCheckingEnabled = false; text.isGrammarCheckingEnabled = false
        text.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular); text.textColor = .labelColor; text.backgroundColor = editorColor
        text.textContainerInset = NSSize(width: 10, height: 8); text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.layoutManager?.allowsNonContiguousLayout = true
        text.minSize = .zero; text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude); text.usesFindBar = true; text.isIncrementalSearchingEnabled = true; text.delegate = self
        text.setAccessibilityLabel(editable ? "Request body" : "Response body")
        scroll.backgroundColor = editorColor; scroll.drawsBackground = true; scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.contentView.postsBoundsChangedNotifications = true
        viewportObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.scheduleHighlight(); self?.viewportChanged?() }
        pin(scroll, in: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { syntaxJob.cancel(); pending?.cancel(); if let viewportObserver { NotificationCenter.default.removeObserver(viewportObserver) } }
    override func layout() {
        super.layout(); let size = scroll.contentSize
        text.minSize = NSSize(width: size.width, height: size.height); text.setFrameSize(NSSize(width: size.width, height: max(text.frame.height, size.height)))
        scheduleHighlight()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); scheduleHighlight() }
    func set(_ string: String, highlight: Bool = false, initiallyInString: Bool = false, initiallyEscaped: Bool = false) {
        initialString = initiallyInString; initialEscape = initiallyEscaped
        applying = true; clearHighlight(); text.string = string; text.setSelectedRange(NSRange(location: 0, length: 0)); scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        syntaxHighlighting = highlight; applying = false; scheduleHighlight()
    }
    func textViewDidChangeSelection(_ notification: Notification) { selectionChanged?() }
    func textDidChange(_ notification: Notification) {
        guard !applying else { return }
        // Editing shifts temporary attribute ranges; clear the bounded token set before repainting.
        text.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (text.string as NSString).length))
        painted = NSRange(location: 0, length: 0)
        changed?(text.string); scheduleHighlight()
    }
    private func clearHighlight() {
        if let manager = text.layoutManager {
            let valid = NSIntersectionRange(painted, NSRange(location: 0, length: (text.string as NSString).length))
            if valid.length > 0 { manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: valid) }
        }
        painted = NSRange(location: 0, length: 0)
    }
    private func scheduleHighlight() {
        pending?.cancel(); syntaxJob.cancel(); generation = UUID()
        guard syntaxHighlighting else { clearHighlight(); return }
        let task = DispatchWorkItem { [weak self] in self?.highlightViewport() }
        pending = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: task)
    }
    private func highlightViewport() {
        guard syntaxHighlighting, let manager = text.layoutManager, let container = text.textContainer else { return }
        let source = text.string as NSString, length = source.length
        guard length > 0 else { clearHighlight(); return }
        let rect = scroll.contentView.bounds.offsetBy(dx: -text.textContainerInset.width, dy: -text.textContainerInset.height)
        let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
        let visible = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let start = max(0, visible.location - 4096), end = min(length, NSMaxRange(visible) + 4096)
        let range = NSRange(location: start, length: max(0, end - start)), id = generation, cancellation = WorkCancellation()
        syntaxJob = cancellation
        let initialString = self.initialString, initialEscape = self.initialEscape
        syntaxQueue.async { [weak self] in
            let tokens = JSONSyntax.tokens(in: source, range: range, initiallyInString: initialString, initiallyEscaped: initialEscape, cancelled: { cancellation.isCancelled })
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == id, !cancellation.isCancelled else { return }
                self.clearHighlight()
                for token in tokens {
                    let color: NSColor
                    switch token.kind { case .key: color = .systemBlue; case .string: color = .systemGreen; case .number: color = .systemOrange; case .literal: color = .systemPurple }
                    manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
                }
                self.painted = range
            }
        }
    }
}
