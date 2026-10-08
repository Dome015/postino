import AppKit
import RelayCore

/// Immutable UTF-8 file with a sparse UTF-16 index for NSTextFinder. Only two
/// chunks are cached, independent of response size. AppKit may read on a worker.
final class ResponseSearchDocument {
    struct Chunk { let bytes: Range<UInt64>; let characters: NSRange }
    let chunks: [Chunk]
    let length: Int
    private let handle: FileHandle
    private let lock = NSLock()
    private var cache: [(Int, NSString)] = []

    init(file: URL, cancelled: () -> Bool = { false }) throws {
        handle = try FileHandle(forReadingFrom: file)
        var entries: [Chunk] = [], offset: UInt64 = 0, length = 0
        do {
            while true {
                if cancelled() { throw CancellationError() }
                let value = try autoreleasepool { () throws -> (UInt64, UInt64, Int) in
                    let window = try ResponseReader.Window.read(file, start: offset)
                    return (window.start, window.end, (window.text as NSString).length)
                }
                if value.1 == offset { break }
                entries.append(Chunk(bytes: value.0..<value.1, characters: NSRange(location: length, length: value.2)))
                length += value.2; offset = value.1
            }
        } catch { try? handle.close(); throw error }
        self.chunks = entries; self.length = length
    }
    deinit { try? handle.close() }
    private func chunkIndex(character: Int) -> Int {
        var low = 0, high = chunks.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(chunks[mid].characters) <= character { low = mid + 1 } else { high = mid }
        }
        return min(low, max(0, chunks.count - 1))
    }
    private func chunkIndex(byte: UInt64) -> Int {
        var low = 0, high = chunks.count
        while low < high {
            let mid = (low + high) / 2
            if chunks[mid].bytes.upperBound <= byte { low = mid + 1 } else { high = mid }
        }
        return min(low, max(0, chunks.count - 1))
    }
    private func text(_ index: Int) -> NSString {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache.firstIndex(where: { $0.0 == index }) {
            let entry = cache.remove(at: hit); cache.append(entry); return entry.1
        }
        let chunk = chunks[index]
        // The open descriptor remains valid if an old response is unlinked while
        // AppKit finishes a cancelled search. Response files are immutable.
        do {
            let string: NSString = try autoreleasepool {
                try handle.seek(toOffset: chunk.bytes.lowerBound)
                let data = try handle.read(upToCount: Int(chunk.bytes.count)) ?? Data()
                return String(decoding: data, as: UTF8.self) as NSString
            }
            cache.append((index, string)); if cache.count > 2 { cache.removeFirst() }
            return string
        } catch { return "" }
    }
    func substring(at character: Int) -> (NSString, NSRange) {
        guard character >= 0, character < length, !chunks.isEmpty else { return ("", NSRange(location: length, length: 0)) }
        let index = chunkIndex(character: character)
        return (text(index), chunks[index].characters)
    }
    func byteOffset(at character: Int) -> UInt64 {
        guard !chunks.isEmpty else { return 0 }
        let index = chunkIndex(character: max(0, character)), chunk = chunks[index], string = text(index)
        let local = min(string.length, max(0, character - chunk.characters.location))
        return chunk.bytes.lowerBound + UInt64(string.substring(to: local).utf8.count)
    }
    func characterOffset(at byte: UInt64) -> Int {
        guard !chunks.isEmpty else { return 0 }
        let index = chunkIndex(byte: byte), chunk = chunks[index]
        let string = text(index) as String
        let prefix = string.utf8.prefix(Int(min(byte - chunk.bytes.lowerBound, UInt64(string.utf8.count))))
        return chunk.characters.location + (String(decoding: prefix, as: UTF8.self) as NSString).length
    }
}

/// Native read-only Find bar over the entire file, with ranges mapped into the
/// response's sliding text window only when AppKit needs to reveal a match.
final class ResponseFindClient: NSObject, NSTextFinderClient {
    let finder = NSTextFinder()
    private weak var editor: CodeEditor?
    private weak var reader: ResponseReader?
    private let queue = DispatchQueue(label: "postino.response-find-index", qos: .userInitiated)
    private var indexing = WorkCancellation()
    private var generation = UUID()
    private var selection = [NSValue(range: NSRange(location: 0, length: 0))]
    private var indexedWindowByte: UInt64?
    private var indexedWindowCharacter = 0
    private weak var windowDocument: ResponseSearchDocument?
    private var applyingSelection = false
    private var pendingReveal = false
    private var matchObservation: NSKeyValueObservation?
    private let documentLock = NSLock()
    private var indexedDocument: ResponseSearchDocument?
    var document: ResponseSearchDocument? {
        documentLock.lock(); defer { documentLock.unlock() }; return indexedDocument
    }
    private(set) var file: URL?
    var ready: (() -> Void)?
    var failed: ((String) -> Void)?

    init(editor: CodeEditor, reader: ResponseReader) {
        self.editor = editor; self.reader = reader
        super.init()
        finder.client = self; finder.findBarContainer = editor.scroll
        finder.isIncrementalSearchingEnabled = true
        // Native visible-match highlighting without dimming syntax colors.
        finder.incrementalSearchingShouldDimContentView = false
        matchObservation = finder.observe(\.incrementalMatchRanges, options: [.new]) { [weak editor] _, _ in editor?.text.needsDisplay = true }
        editor.selectionChanged = { [weak self] in self?.selectionChanged() }
        reader.windowChanged = { [weak self] in self?.windowChanged() }
    }
    deinit { indexing.cancel(); finder.client = nil; finder.findBarContainer = nil }
    func open(_ file: URL?) {
        guard self.file != file else { return }
        editor?.text.responseFinder = file == nil ? nil : finder
        editor?.text.drawFindHighlights = file == nil ? nil : { [weak self] in self?.drawHighlights() }
        if file == nil { finder.performAction(.hideFindInterface) }
        indexing.cancel(); generation = UUID(); self.file = file; pendingReveal = false
        finder.noteClientStringWillChange(); finder.cancelFindIndicator()
        documentLock.lock(); indexedDocument = nil; documentLock.unlock()
        selection = [NSValue(range: NSRange(location: 0, length: 0))]
        guard let file else { return }
        let id = generation, cancellation = WorkCancellation(); indexing = cancellation
        queue.async { [weak self] in
            let result = Result { try ResponseSearchDocument(file: file, cancelled: { cancellation.isCancelled }) }
            DispatchQueue.main.async {
                guard let self, self.generation == id, !cancellation.isCancelled else { return }
                switch result {
                case .success(let document):
                    self.finder.noteClientStringWillChange()
                    self.documentLock.lock(); self.indexedDocument = document; self.documentLock.unlock()
                    self.selectionChanged()
                    // A query entered while the index was being prepared must
                    // start searching the new document without another keypress.
                    self.ready?()
                    if self.editor?.scroll.isFindBarVisible == true { self.finder.performAction(.nextMatch) }
                case .failure(let error): self.failed?("Could not prepare response search: \(error.localizedDescription)")
                }
            }
        }
    }
    var isSelectable: Bool { true }
    var isEditable: Bool { false }
    var allowsMultipleSelection: Bool { false }
    func stringLength() -> Int { document?.length ?? 0 }
    var firstSelectedRange: NSRange { selection.first?.rangeValue ?? NSRange(location: 0, length: 0) }
    var selectedRanges: [NSValue] {
        get { selection }
        set {
            selection = newValue
            if let range = newValue.first?.rangeValue { reveal(range) }
        }
    }
    func scrollRangeToVisible(_ range: NSRange) { reveal(range) }
    private func reveal(_ range: NSRange) {
        guard let document, range.location != NSNotFound, NSMaxRange(range) <= document.length, let reader, let editor else { return }
        selection = [NSValue(range: range)]
        let visible = windowRange
        if NSLocationInRange(range.location, visible), NSMaxRange(range) <= NSMaxRange(visible) {
            applyingSelection = true
            let local = NSRange(location: range.location - visible.location, length: range.length)
            editor.text.setSelectedRange(local); editor.text.scrollRangeToVisible(local)
            applyingSelection = false
        } else {
            pendingReveal = true
            reader.seek(document.byteOffset(at: range.location), length: range.length)
        }
    }
    private var windowRange: NSRange {
        guard let document, let window = reader?.window else { return NSRange(location: 0, length: 0) }
        if indexedWindowByte != window.start || windowDocument !== document {
            indexedWindowByte = window.start; windowDocument = document
            indexedWindowCharacter = document.characterOffset(at: window.start)
        }
        return NSRange(location: indexedWindowCharacter, length: (window.text as NSString).length)
    }
    private func selectionChanged() {
        guard !applyingSelection, !pendingReveal, reader?.isApplyingWindow == false, let editor, document != nil else { return }
        let local = editor.text.selectedRange(), window = windowRange
        selection = [NSValue(range: NSRange(location: window.location + local.location, length: local.length))]
    }
    private func windowChanged() {
        let range = firstSelectedRange, window = windowRange
        if range.length > 0, range.location >= window.location, NSMaxRange(range) <= NSMaxRange(window), let editor {
            applyingSelection = true
            editor.text.setSelectedRange(NSRange(location: range.location - window.location, length: range.length))
            applyingSelection = false
        }
        if pendingReveal {
            pendingReveal = false
            if let editor { editor.text.showFindIndicator(for: editor.text.selectedRange()) }
        } else { selectionChanged() }
        finder.findIndicatorNeedsUpdate = true
        editor?.text.needsDisplay = true
    }
    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: stringLength())
        return editor?.text ?? NSView()
    }
    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let editor, let layout = editor.text.layoutManager, let container = editor.text.textContainer else { return [] }
        let window = windowRange
        guard range.location >= window.location, NSMaxRange(range) <= NSMaxRange(window) else { return [] }
        let local = NSRange(location: range.location - window.location, length: range.length)
        let glyphs = layout.glyphRange(forCharacterRange: local, actualCharacterRange: nil)
        var rects: [NSValue] = []
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            rects.append(NSValue(rect: rect.offsetBy(dx: editor.text.textContainerInset.width, dy: editor.text.textContainerInset.height)))
        }
        return rects
    }
    var visibleCharacterRanges: [NSValue] {
        // The text view is a virtual view of the whole file. Give AppKit the
        // logical range so incremental search and its count cover offscreen
        // chunks too; geometry and drawing stay clipped to the loaded window.
        [NSValue(range: NSRange(location: 0, length: stringLength()))]
    }
    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let editor, let layout = editor.text.layoutManager else { return }
        let window = windowRange
        guard range.location >= window.location, NSMaxRange(range) <= NSMaxRange(window) else { return }
        let local = NSRange(location: range.location - window.location, length: range.length)
        let glyphs = layout.glyphRange(forCharacterRange: local, actualCharacterRange: nil)
        layout.drawGlyphs(forGlyphRange: glyphs, at: editor.text.textContainerOrigin)
    }
    /// Paint only native match ranges intersecting the loaded text window.
    func drawHighlights() {
        guard let editor, editor.scroll.isFindBarVisible,
              let layout = editor.text.layoutManager, let container = editor.text.textContainer else { return }
        let bounds = editor.scroll.contentView.bounds.offsetBy(dx: -editor.text.textContainerInset.width, dy: -editor.text.textContainerInset.height)
        let glyphs = layout.glyphRange(forBoundingRect: bounds, in: container)
        let local = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let visible = NSRange(location: windowRange.location + local.location, length: local.length)
        for value in finder.incrementalMatchRanges {
            let clipped = NSIntersectionRange(value.rangeValue, visible)
            guard clipped.length > 0 else { continue }
            for rect in rects(forCharacterRange: clipped) ?? [] { NSTextFinder.drawIncrementalMatchHighlight(in: rect.rectValue) }
        }
    }
    func string(at characterIndex: Int, effectiveRange outRange: NSRangePointer, endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>) -> String {
        let value = document?.substring(at: characterIndex) ?? ("", NSRange(location: 0, length: 0))
        outRange.pointee = value.1; outFlag.pointee = false
        return value.0 as String
    }
}
