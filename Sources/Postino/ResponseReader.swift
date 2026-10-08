import AppKit
import RelayCore

/// Keeps a sliding UTF-8 window in the native text view; the full response stays on disk.
final class ResponseReader {
    struct Window {
        let start: UInt64
        let end: UInt64
        let text: String
        static let capacity = 512 * 1024
        static func read(_ file: URL, start: UInt64) throws -> Window {
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: capacity + 4) ?? Data()
            var skipped = 0
            if start > 0 { while skipped < min(4, data.count) && data[skipped] & 0xC0 == 0x80 { skipped += 1 } }
            if skipped > 0 { data = Data(data.dropFirst(skipped)) }
            let count = min(capacity, data.count)
            var end = count
            if count < data.count { while end > 0 && data[end] & 0xC0 == 0x80 { end -= 1 } }
            let body = data.prefix(end)
            return Window(start: start + UInt64(skipped), end: start + UInt64(skipped + end), text: String(decoding: body, as: UTF8.self))
        }
    }
    /// Sparse lexical checkpoints avoid rescanning the file for every viewport.
    private final class JSONContext {
        struct State { var string = false; var escaped = false }
        let file: URL
        var checkpoints: [UInt64: State] = [0: State()]
        init(_ file: URL) { self.file = file }
        func state(at offset: UInt64, cancelled: () -> Bool) throws -> State {
            var position = checkpoints.keys.filter { $0 <= offset }.max() ?? 0
            var state = checkpoints[position]!
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            try handle.seek(toOffset: position)
            while position < offset {
                if cancelled() { throw CocoaError(.userCancelled) }
                let boundary = ((position / 65536) + 1) * 65536
                let count = Int(min(offset, boundary) - position)
                let data = try handle.read(upToCount: count) ?? Data()
                if data.isEmpty { break }
                for byte in data {
                    if state.string {
                        if state.escaped { state.escaped = false }
                        else if byte == 92 { state.escaped = true }
                        else if byte == 34 { state.string = false }
                    } else if byte == 34 { state.string = true }
                }
                position += UInt64(data.count)
                if position % 65536 == 0 { checkpoints[position] = state }
            }
            return state
        }
    }
    private var context: JSONContext?
    private let editor: CodeEditor
    private let queue = DispatchQueue(label: "postauomo.response-window", qos: .userInitiated)
    private var generation = UUID()
    private var job = WorkCancellation()
    private(set) var file: URL?
    private(set) var window: Window?
    private var size: UInt64 = 0
    private var loading = false
    private var applying = false
    private var highlight = false
    var windowChanged: (() -> Void)?
    var isApplyingWindow: Bool { applying || loading }
    lazy var findClient = ResponseFindClient(editor: editor, reader: self)
    var failed: ((String) -> Void)?
    init(_ editor: CodeEditor) {
        self.editor = editor
        editor.viewportChanged = { [weak self] in self?.viewportChanged() }
        editor.text.jumpToBoundary = { [weak self] end in self?.jump(end: end) }
    }
    private func resetWindow() { job.cancel(); generation = UUID(); file = nil; window = nil; loading = false; context = nil }
    func clear() { resetWindow(); findClient.open(nil) }
    func open(_ file: URL, highlight: Bool) {
        guard self.file != file else { return }
        resetWindow(); self.file = file; self.highlight = highlight; context = highlight ? JSONContext(file) : nil; size = UInt64(max(0, ResponseFile.size(file)))
        findClient.failed = { [weak self] in self?.failed?($0) }; findClient.open(file)
        load(start: 0)
    }
    func seek(_ offset: UInt64, term: String) {
        seek(offset, length: (term as NSString).length)
    }
    func seek(_ offset: UInt64, length: Int) {
        load(start: offset > 64 * 1024 ? offset - 64 * 1024 : 0, match: (offset, length))
    }
    private func jump(end: Bool) {
        guard file != nil else { return }
        load(start: end && size > UInt64(Window.capacity) ? size - UInt64(Window.capacity) : 0, end: end)
    }
    private func viewportChanged() {
        guard !loading, !applying, let window, let layout = editor.text.layoutManager, let container = editor.text.textContainer else { return }
        let bounds = editor.scroll.contentView.bounds
        let rect = bounds.offsetBy(dx: -editor.text.textContainerInset.width, dy: -editor.text.textContainerInset.height)
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = (window.text as NSString).length
        guard chars.location != NSNotFound, length > 0 else { return }
        let nearEnd = NSMaxRange(chars) > length - min(8192, length / 8)
        let nearStart = chars.location < min(8192, length / 8)
        guard (nearEnd && window.end < size) || (nearStart && window.start > 0) else { return }
        let index = min(chars.location, length)
        let anchor = window.start + UInt64((window.text as NSString).substring(to: index).utf8.count)
        let glyph = layout.glyphIndexForCharacter(at: index)
        let y = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: min(1, layout.numberOfGlyphs - glyph)), in: container).minY + editor.text.textContainerInset.height
        let delta = bounds.minY - y
        let start: UInt64
        if nearEnd { start = anchor > 64 * 1024 ? anchor - 64 * 1024 : 0 }
        else { start = anchor > UInt64(Window.capacity - 64 * 1024) ? anchor - UInt64(Window.capacity - 64 * 1024) : 0 }
        load(start: start, anchor: (anchor, delta))
    }
    private func load(start: UInt64, anchor: (UInt64, CGFloat)? = nil, match: (UInt64, Int)? = nil, end: Bool = false) {
        guard let file else { return }
        job.cancel(); let cancellation = WorkCancellation(); job = cancellation
        generation = UUID(); let id = generation; loading = true; let context = self.context
        queue.async { [weak self] in
            let result = Result { () throws -> (Window, JSONContext.State) in
                let value = try Window.read(file, start: start)
                return (value, try context?.state(at: value.start, cancelled: { cancellation.isCancelled }) ?? JSONContext.State())
            }
            DispatchQueue.main.async {
                guard let self, self.generation == id, self.file == file else { return }
                self.loading = false; self.applying = true
                defer { self.applying = false; self.windowChanged?() }
                switch result {
                case .failure(let error): self.failed?(error.localizedDescription)
                case .success(let loaded):
                    let (value, state) = loaded
                    self.window = value; self.editor.set(value.text, highlight: self.highlight, initiallyInString: state.string, initiallyEscaped: state.escaped)
                    let text = self.editor.text
                    func character(_ byte: UInt64) -> Int {
                        let count = Int(min(UInt64(value.text.utf8.count), byte > value.start ? byte - value.start : 0))
                        return (String(decoding: value.text.utf8.prefix(count), as: UTF8.self) as NSString).length
                    }
                    if let match {
                        let range = NSRange(location: character(match.0), length: match.1)
                        if NSMaxRange(range) <= (value.text as NSString).length { text.setSelectedRange(range); text.scrollRangeToVisible(range) }
                    } else if let anchor, let layout = text.layoutManager, let container = text.textContainer {
                        let index = character(anchor.0)
                        layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(index + 1, (value.text as NSString).length)))
                        let glyph = layout.glyphIndexForCharacter(at: index)
                        let y = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: min(1, layout.numberOfGlyphs - glyph)), in: container).minY + text.textContainerInset.height
                        self.editor.scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y + anchor.1)))
                        self.editor.scroll.reflectScrolledClipView(self.editor.scroll.contentView)
                    } else if end { text.scrollRangeToVisible(NSRange(location: (value.text as NSString).length, length: 0)) }
                }
            }
        }
    }
}
