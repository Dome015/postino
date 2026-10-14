import AppKit

/// Small native editing aids for request bodies. All replacements use NSTextView
/// so delegate notifications, Find, selection and the native undo stack survive.
class CodeEditingTextView: NSTextView {
    var editingAidsEnabled = false
    private let pairs: [String: String] = ["{": "}", "[": "]", "(": ")", "\"": "\"", "'": "'"]
    private var aidsActive: Bool { editingAidsEnabled && isEditable && !hasMarkedText() }
    private var source: NSString { string as NSString }
    private func replaceCode(_ replacement: String, range: NSRange, selection: NSRange) {
        breakUndoCoalescing()
        super.insertText(replacement, replacementRange: range)
        setSelectedRange(selection); scrollRangeToVisible(selection); breakUndoCoalescing()
    }
    private func character(at index: Int) -> String {
        guard index >= 0 && index < source.length else { return "" }
        return source.substring(with: NSRange(location: index, length: 1))
    }
    private func linePrefix(at location: Int) -> String {
        let start = max(0, location - 65_536)
        let prefix = source.substring(with: NSRange(location: start, length: location - start)) as NSString
        let newline = prefix.rangeOfCharacter(from: .newlines, options: .backwards)
        return newline.location == NSNotFound ? prefix as String : prefix.substring(from: NSMaxRange(newline))
    }
    private func indentation(_ prefix: String) -> String { String(prefix.prefix { $0 == " " || $0 == "\t" }) }
    private var indentUnit: String {
        let sample = source.substring(to: min(source.length, 8192))
        let indents = sample.components(separatedBy: .newlines).map(indentation).filter { !$0.isEmpty }
        if indents.contains(where: { $0.contains("\t") }) { return "\t" }
        return String(repeating: " ", count: indents.map(\.count).filter { $0 <= 8 }.min() ?? 2)
    }
    private func stringContext(at location: Int) -> (quote: String?, escaped: Bool) {
        // JSON strings cannot cross literal newlines. Avoid scanning huge raw
        // body prefixes on the UI thread just to complete a single keystroke.
        let prefix = linePrefix(at: location)
        guard prefix.utf16.count < 65_536 else { return ("\"", false) }
        var quote: Character?, escaped = false
        for character in prefix {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if let current = quote { if character == current { quote = nil } }
            else if character == "\"" || character == "'" { quote = character }
        }
        return (quote.map(String.init), escaped)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let value = (insertString as? NSAttributedString)?.string ?? (insertString as? String)
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        guard aidsActive, let value, value.utf16.count == 1,
              NSMaxRange(range) <= source.length else { super.insertText(insertString, replacementRange: replacementRange); return }
        let context = stringContext(at: range.location), next = character(at: range.location)
        if range.length == 0 && next == value && pairs.values.contains(value), !context.escaped,
           (context.quote == nil || context.quote == value) {
            setSelectedRange(NSRange(location: range.location + 1, length: 0)); return
        }
        if let closer = pairs[value], range.length > 0 || (context.quote == nil && !context.escaped && (next.isEmpty || next.first!.isWhitespace || ["}", "]", ")", ",", ":", ";"].contains(next))) {
            let selected = source.substring(with: range)
            replaceCode(value + selected + closer, range: range, selection: NSRange(location: range.location + 1, length: range.length)); return
        }
        if range.length == 0, ["}", "]", ")"].contains(value), context.quote == nil {
            let prefix = linePrefix(at: range.location), indent = indentation(prefix)
            if !indent.isEmpty && prefix == indent {
                let amount = indent.hasSuffix("\t") ? 1 : min(indent.count, indentUnit.count)
                let start = range.location - amount
                replaceCode(value, range: NSRange(location: start, length: amount), selection: NSRange(location: start + 1, length: 0)); return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func insertNewline(_ sender: Any?) {
        guard aidsActive else { super.insertNewline(sender); return }
        let range = selectedRange(), prefix = linePrefix(at: range.location)
        let indent = indentation(prefix), context = stringContext(at: range.location)
        let last = prefix.trimmingCharacters(in: .whitespaces).last.map(String.init) ?? ""
        let opens = context.quote == nil && ["{", "[", "("].contains(last)
        let inner = indent + (opens ? indentUnit : "")
        var replacement = "\n" + inner, replaced = range
        var next = NSMaxRange(range)
        while next - NSMaxRange(range) < 8192 && [" ", "\t"].contains(character(at: next)) { next += 1 }
        if opens && character(at: next) == pairs[last] {
            replacement += "\n" + indent; replaced.length = next - range.location
        }
        replaceCode(replacement, range: replaced, selection: NSRange(location: range.location + 1 + inner.utf16.count, length: 0))
    }
    override func insertTab(_ sender: Any?) {
        guard aidsActive else { super.insertTab(sender); return }
        if selectedRange().length > 0 { indentLines(outdent: false) }
        else {
            let range = selectedRange(), unit = indentUnit
            replaceCode(unit, range: range, selection: NSRange(location: range.location + unit.utf16.count, length: 0))
        }
    }
    override func insertBacktab(_ sender: Any?) {
        guard aidsActive else { super.insertBacktab(sender); return }
        indentLines(outdent: true)
    }
    private func indentLines(outdent: Bool) {
        let selection = selectedRange(), unit = indentUnit
        let included = NSRange(location: selection.location, length: max(0, selection.length - 1))
        let range = source.lineRange(for: included), original = source.substring(with: range)
        var lines = original.components(separatedBy: "\n"), firstDelta = 0
        for index in lines.indices {
            if index == lines.count - 1 && lines[index].isEmpty && original.hasSuffix("\n") { continue }
            if outdent {
                let indent = indentation(lines[index])
                let amount = indent.hasPrefix("\t") ? 1 : min(indent.count, unit.count)
                lines[index].removeFirst(amount); if index == 0 { firstDelta = -amount }
            } else { lines[index] = unit + lines[index]; if index == 0 { firstDelta = unit.utf16.count } }
        }
        let replacement = lines.joined(separator: "\n")
        let resultSelection = selection.length > 0 ? NSRange(location: range.location, length: (replacement as NSString).length) : NSRange(location: max(range.location, selection.location + firstDelta), length: 0)
        replaceCode(replacement, range: range, selection: resultSelection)
    }
    override func deleteBackward(_ sender: Any?) {
        guard aidsActive, selectedRange().length == 0, selectedRange().location > 0 else { super.deleteBackward(sender); return }
        let cursor = selectedRange().location, previous = character(at: cursor - 1), next = character(at: cursor)
        if pairs[previous] == next && !stringContext(at: cursor - 1).escaped {
            replaceCode("", range: NSRange(location: cursor - 1, length: 2), selection: NSRange(location: cursor - 1, length: 0)); return
        }
        let prefix = linePrefix(at: cursor)
        if !prefix.isEmpty && prefix == indentation(prefix) {
            let width = indentUnit.count, amount = prefix.hasSuffix("\t") ? 1 : ((prefix.count - 1) % width + 1)
            replaceCode("", range: NSRange(location: cursor - amount, length: amount), selection: NSRange(location: cursor - amount, length: 0)); return
        }
        super.deleteBackward(sender)
    }
}
