import AppKit
import RelayCore

private let pairRowsType = NSPasteboard.PasteboardType("app.postino.pair-rows")
private let pairDragType = NSPasteboard.PasteboardType("app.postino.pair-drag")

/// The editable pair table owns its columns, row actions, sizing, and focus behavior.
/// Callers supply labels and a background; row changes flow back through `changed`.
struct PairTableConfiguration {
    var keyTitle = "Key"
    var valueTitle = "Value"
    var rowName = "row"
    var showsType = false
    var keyWidth: CGFloat = 210
    var backgroundColor: NSColor = bandDarkColor

    static let headers = PairTableConfiguration(rowName: "header")
    static let parameters = PairTableConfiguration(rowName: "parameter")
    static let form = PairTableConfiguration(rowName: "field", showsType: true)
    static let credentials = PairTableConfiguration(keyTitle: "Credential", rowName: "credential")
    static let environment = PairTableConfiguration(keyTitle: "Variable", rowName: "variable", backgroundColor: canvasColor)
}

/// Keep AppKit's column resizing and accessibility, while drawing titles without
/// the native header's vertical separators. The last column holds the add action.
private final class PairHeaderView: NSTableHeaderView {
    let addButton: RelayButton
    init(addButton: RelayButton) {
        self.addButton = addButton
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 36))
        addSubview(addButton)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        guard let table = tableView else { return }
        let column = table.column(withIdentifier: .init("delete"))
        let rect = headerRect(ofColumn: column)
        addButton.frame = NSRect(x: rect.midX - 14, y: bounds.midY - 14, width: 28, height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableView else { return }
        table.backgroundColor.setFill(); NSIntersectionRect(bounds, dirtyRect).fill()
        for (index, column) in table.tableColumns.enumerated() where !column.title.isEmpty {
            let rect = headerRect(ofColumn: index)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
            let size = (column.title as NSString).size(withAttributes: attributes)
            (column.title as NSString).draw(in: NSRect(x: rect.minX + 15, y: rect.midY - size.height / 2, width: max(0, rect.width - 18), height: size.height), withAttributes: attributes)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + [addButton]
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// The input fills its row's hit target, including the space above/below the text.
private final class PairInputCell: NSTableCellView {
    weak var input: NSTextField?
    var focus: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        focus?()
        if let input { window?.makeFirstResponder(input); input.mouseDown(with: event) }
    }
}
final class PairTableView: NSTableView {
    weak var editor: PairEditor?
    @objc func copy(_ sender: Any?) { editor?.copyRows(cut: false) }
    @objc func cut(_ sender: Any?) { editor?.copyRows(cut: true) }
    @objc func paste(_ sender: Any?) { editor?.pasteRows() }
    @objc func deleteSelection(_ sender: Any?) {
        guard !(window?.firstResponder is NSTextView) else { return }
        editor?.deleteSelectedRows()
    }
    override func deleteBackward(_ sender: Any?) { deleteSelection(sender) }
    override func deleteForward(_ sender: Any?) { deleteSelection(sender) }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function).isEmpty {
            if [51, 117].contains(event.keyCode) { deleteSelection(nil); return }
            if [36, 76].contains(event.keyCode), let editor, selectedRow >= 0 { editor.focusInput(row: selectedRow); return }
        }
        super.keyDown(with: event)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(deleteSelection(_:)): return !(window?.firstResponder is NSTextView) && editor?.canRemoveRow == true
        case #selector(paste(_:)): return editor?.canPasteRows == true
        default: return super.validateUserInterfaceItem(item)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        window?.makeFirstResponder(self)
        return super.menu(for: event)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        if row >= 0, column >= 0,
           let host = view(atColumn: column, row: row, makeIfNecessary: true) as? PairInputCell,
           let input = host.input {
            // NSTableView otherwise consumes the first click on a borderless field.
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window?.makeFirstResponder(input); input.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}
private final class PairScrollView: NSScrollView {
    var viewportChanged: (() -> Void)?
    override func tile() { super.tile(); viewportChanged?() }
}
final class PairEditor: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var items: [Pair] = []
    private let dragOwner = UUID().uuidString
    private var revision = UUID().uuidString
    var rows: [Pair] {
        get { items }
        set { items = newValue; revision = UUID().uuidString; table.reloadData(); table.deselectAll(nil); updateSelection() }
    }
    var changed: (([Pair]) -> Void)?
    var selectionChanged: (() -> Void)?
    var canRemoveRow: Bool { items.indices.contains(table.selectedRow) }
    var secret = false
    var variableContext: VariablePreviewContext? {
        didSet {
            func update(_ view: NSView) {
                (view as? InputField)?.variableContext = variableContext
                (view as? SecureInputField)?.variableContext = variableContext
                view.subviews.forEach(update)
            }
            update(table)
        }
    }
    let table = PairTableView()
    private let scroll = PairScrollView()
    private let hasTypes: Bool
    private let placeholder: String
    private let keyPlaceholder: String
    let configuration: PairTableConfiguration
    let addButton: RelayButton

    init(configuration: PairTableConfiguration = .headers) {
        self.configuration = configuration
        hasTypes = configuration.showsType; placeholder = configuration.valueTitle; keyPlaceholder = configuration.keyTitle
        addButton = button("", symbol: "plus", target: nil, action: #selector(addRow))
        super.init(frame: .zero)
        addButton.target = self; addButton.style = .plain
        addButton.toolTip = "Add \(configuration.rowName)"
        addButton.setAccessibilityLabel("Add \(configuration.rowName)")
        func column(_ id: String, _ title: String, _ width: CGFloat, fixed: Bool = false) {
            let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = width
            c.minWidth = fixed ? width : 100; c.maxWidth = fixed ? width : .greatestFiniteMagnitude
            c.resizingMask = fixed ? [] : [.autoresizingMask, .userResizingMask]
            table.addTableColumn(c)
        }
        column("drag", "", 20, fixed: true)
        column("enabled", "", 32, fixed: true)
        if hasTypes { column("type", "Type", 80, fixed: true) }
        column("key", configuration.keyTitle, configuration.keyWidth); column("value", configuration.valueTitle, 500)
        column("delete", "", 36, fixed: true)
        table.headerView = PairHeaderView(addButton: addButton)
        table.style = .plain; table.delegate = self; table.dataSource = self; table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 6, height: 0); table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = configuration.backgroundColor; table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = .separatorColor; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsEmptySelection = true; table.allowsMultipleSelection = true; table.editor = self
        table.registerForDraggedTypes([pairDragType]); table.setDraggingSourceOperationMask(.move, forLocal: true); table.setDraggingSourceOperationMask([], forLocal: false)
        let menu = NSMenu()
        for (title, action) in [("Copy rows", #selector(PairTableView.copy(_:))), ("Cut rows", #selector(PairTableView.cut(_:))), ("Paste rows", #selector(PairTableView.paste(_:))), ("Delete rows", #selector(PairTableView.deleteSelection(_:)))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = table
        }
        table.menu = menu
        scroll.viewportChanged = { [weak self] in self?.fitColumns() }
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.backgroundColor = table.backgroundColor; scroll.drawsBackground = true
        pin(padded(scroll, x: 6, y: 0), in: self)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        table.setAccessibilityLabel("\(configuration.rowName.capitalized) entries")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        fitColumns()
    }
    private func fitColumns() {
        // Reserve the inline action column even when the window is narrowed.
        // Only the value column absorbs spare width; fixed controls never leave the viewport.
        let width = scroll.contentView.bounds.width
        guard width > 0, let valueColumn = table.tableColumn(withIdentifier: .init("value")) else { return }
        if let keyColumn = table.tableColumn(withIdentifier: .init("key")) {
            let fixed = table.tableColumns.filter { $0 !== keyColumn && $0 !== valueColumn }.reduce(CGFloat(0)) { $0 + $1.width }
            keyColumn.maxWidth = max(keyColumn.minWidth, width - fixed - valueColumn.minWidth - CGFloat(table.tableColumns.count) * table.intercellSpacing.width)
            keyColumn.width = min(keyColumn.width, keyColumn.maxWidth)
        }
        let occupied = table.tableColumns.filter { $0 !== valueColumn }.reduce(CGFloat(0)) { $0 + $1.width }
        valueColumn.width = max(valueColumn.minWidth, width - occupied - CGFloat(table.tableColumns.count) * table.intercellSpacing.width)
        table.setFrameSize(NSSize(width: width, height: table.frame.height))
        table.headerView?.needsLayout = true
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { AccentRowView() }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    func tableViewColumnDidResize(_ notification: Notification) { needsLayout = true }
    private func updateSelection() { selectionChanged?() }
    private func notifyChanged() { revision = UUID().uuidString; changed?(items) }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = column?.identifier.rawValue else { return nil }
        guard items.indices.contains(row) else { return nil }
        let p = items[row]
        if identifier == "drag" {
            let handle = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder row")!)
            handle.contentTintColor = .tertiaryLabelColor; handle.toolTip = "Drag to reorder. Select rows to copy, cut, paste or delete."
            return cell(handle)
        }
        if identifier == "delete" {
            let b = button("", symbol: "trash", target: self, action: #selector(deleteInline(_:)))
            b.style = .plain; b.tag = row; b.toolTip = "Delete \(configuration.rowName)"; b.setAccessibilityLabel("Delete \(configuration.rowName) \(row + 1)")
            return cell(b)
        }
        if identifier == "type" {
            let popup = RelayPopup(); popup.addItems(withTitles: ["Text", "File"])
            popup.selectItem(at: p.extra["type"] as? String == "file" ? 1 : 0)
            popup.tag = row; popup.target = self; popup.action = #selector(typeChanged(_:)); return cell(popup)
        }
        if identifier == "enabled" {
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            b.contentTintColor = accent; b.controlSize = .small; b.state = p.enabled ? .on : .off
            b.tag = row; b.toolTip = "Include this \(configuration.rowName)"; b.setAccessibilityLabel("Enable \(configuration.rowName) \(row + 1)"); return cell(b)
        }
        let value = identifier == "key" ? p.key : (p.extra["type"] as? String == "file" ? (p.extra["src"] as? String ?? p.value) : p.value)
        let references = VariableReference.matches(in: value)
        let referenceOnly = references.count == 1 && references[0].range == NSRange(location: 0, length: (value as NSString).length)
        let text: NSTextField = secret && identifier == "value" && ["token", "password", "value"].contains(p.key) && !referenceOnly ? SecureInputField() : InputField()
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.stringValue = value
        (text as? InputField)?.variableContext = variableContext
        (text as? SecureInputField)?.variableContext = variableContext
        text.placeholderString = identifier == "key" ? keyPlaceholder : placeholder
        text.tag = row * 2 + (identifier == "key" ? 0 : 1); text.delegate = self
        text.setAccessibilityLabel("\(identifier) row \(row + 1)")
        let host = PairInputCell(); host.input = text
        host.focus = { [weak self] in self?.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        embed(text, in: host)
        return host
    }
    private func embed(_ child: NSView, in host: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 3), child.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -3), child.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
    }
    private func cell(_ child: NSView) -> NSView { let host = NSTableCellView(); embed(child, in: host); return host }
    private func record(_ field: NSTextField) {
        let row = field.tag / 2; guard items.indices.contains(row) else { return }
        if field.tag % 2 == 0 { items[row].key = field.stringValue }
        else if hasTypes && items[row].extra["type"] as? String == "file" { items[row].extra["src"] = field.stringValue; items[row].value = "" }
        else { items[row].value = field.stringValue }
        notifyChanged(); updateSelection()
    }
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        table.selectRowIndexes(IndexSet(integer: field.tag / 2), byExtendingSelection: false)
    }
    func controlTextDidChange(_ obj: Notification) { if let field = obj.object as? NSTextField { record(field) } }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        record(field)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }
        if command == #selector(NSResponder.cancelOperation(_:)) { window?.makeFirstResponder(table); return true }
        let backwards = command == #selector(NSResponder.insertBacktab(_:))
        guard backwards || command == #selector(NSResponder.insertTab(_:)) else { return false }
        let next = field.tag + (backwards ? -1 : 1)
        guard next >= 0, next / 2 < numberOfRows(in: table) else { return false }
        focusInput(row: next / 2, value: next % 2 == 1); return true
    }
    fileprivate func focusInput(row: Int, value: Bool = false) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
        let column = table.column(withIdentifier: .init(value ? "value" : "key"))
        guard let host = table.view(atColumn: column, row: row, makeIfNecessary: true) as? PairInputCell, let field = host.input else { return }
        window?.makeFirstResponder(field); field.currentEditor()?.selectAll(nil)
    }
    @objc private func typeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag; guard items.indices.contains(row) else { return }
        items[row].extra["type"] = sender.indexOfSelectedItem == 1 ? "file" : "text"; notifyChanged()
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: table.column(withIdentifier: .init("value"))))
    }
    @objc private func toggleRow(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        table.selectRowIndexes(IndexSet(integer: sender.tag), byExtendingSelection: false)
        items[sender.tag].enabled = sender.state == .on; notifyChanged(); updateSelection()
    }
    @objc func addRow() {
        window?.makeFirstResponder(nil); items.append(Pair()); table.reloadData(); notifyChanged()
        focusInput(row: items.count - 1)
    }
    @objc private func deleteInline(_ sender: NSButton) { deleteRow(at: sender.tag) }
    @objc func removeRow() { deleteRow(at: table.selectedRow) }
    private func deleteRow(at index: Int) {
        guard items.indices.contains(index) else { return }
        // Commit the field editor before changing row tags or removing its view.
        window?.makeFirstResponder(nil); items.remove(at: index); table.reloadData(); notifyChanged()
        if items.isEmpty { table.deselectAll(nil) }
        else { table.selectRowIndexes(IndexSet(integer: min(index, items.count - 1)), byExtendingSelection: false) }
        updateSelection()
    }

    var canPasteRows: Bool { !clipboardRows().isEmpty }
    private func clipboardRows() -> [Pair] {
        let clipboard = NSPasteboard.general
        if let data = clipboard.data(forType: pairRowsType), let json = try? Postman.read(data),
           json["version"] as? Int == 1, let rows = json["rows"] as? [JSON] { return rows.map(Pair.init) }
        guard let text = clipboard.string(forType: .string), !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }.map {
            let fields = $0.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return Pair(String(fields[0]), fields.count > 1 ? String(fields[1]) : "")
        }
    }
    func copyRows(cut: Bool) {
        window?.makeFirstResponder(table)
        let selected = table.selectedRowIndexes.filter { items.indices.contains($0) }.map { items[$0] }
        guard !selected.isEmpty, let data = try? Postman.encode(["version": 1, "rows": selected.map(\.json)]) else { return }
        let entry = NSPasteboardItem(); entry.setData(data, forType: pairRowsType)
        entry.setString(selected.map { $0.key + "\t" + ($0.extra["type"] as? String == "file" ? ($0.extra["src"] as? String ?? $0.value) : $0.value) }.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([entry]) else { return }
        if cut { deleteSelectedRows() }
    }
    func pasteRows() {
        window?.makeFirstResponder(table)
        let copied = clipboardRows(); guard !copied.isEmpty else { return }
        let index = table.selectedRowIndexes.last.map { $0 + 1 } ?? items.count
        items.insert(contentsOf: copied, at: min(index, items.count))
        finishRowChange(selection: IndexSet(integersIn: index..<(index + copied.count)))
    }
    func deleteSelectedRows() {
        window?.makeFirstResponder(table)
        let selected = table.selectedRowIndexes.intersection(IndexSet(items.indices)); guard let first = selected.first else { return }
        for row in selected.reversed() { items.remove(at: row) }
        finishRowChange(selection: items.isEmpty ? [] : IndexSet(integer: min(first, items.count - 1)))
    }
    private func finishRowChange(selection: IndexSet) {
        revision = UUID().uuidString; table.reloadData(); table.selectRowIndexes(selection, byExtendingSelection: false)
        if let first = selection.first { table.scrollRowToVisible(first) }
        notifyChanged(); updateSelection(); window?.makeFirstResponder(table)
    }
    @discardableResult func moveRows(_ indexes: IndexSet, to destination: Int) -> Bool {
        window?.makeFirstResponder(table)
        guard !indexes.isEmpty, indexes.isSubset(of: IndexSet(items.indices)), (0...items.count).contains(destination) else { return false }
        let remaining = items.indices.filter { !indexes.contains($0) }
        let insertion = destination - indexes.filter { $0 < destination }.count
        var order = remaining; order.insert(contentsOf: indexes, at: insertion)
        guard order != Array(items.indices) else { return false }
        items = order.map { items[$0] }
        finishRowChange(selection: IndexSet(integersIn: insertion..<(insertion + indexes.count))); return true
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        window?.makeFirstResponder(table)
        guard items.indices.contains(row), let data = try? Postman.encode(["owner": dragOwner, "revision": revision, "row": row]) else { return nil }
        let entry = NSPasteboardItem(); entry.setData(data, forType: pairDragType); return entry
    }
    private func draggedRows(_ info: NSDraggingInfo) -> IndexSet? {
        guard info.draggingSource as? NSTableView === table else { return nil }
        var result = IndexSet()
        for entry in info.draggingPasteboard.pasteboardItems ?? [] {
            guard let data = entry.data(forType: pairDragType), let json = try? Postman.read(data),
                  json["owner"] as? String == dragOwner, json["revision"] as? String == revision,
                  let row = json["row"] as? Int, items.indices.contains(row) else { return nil }
            result.insert(row)
        }
        return result.isEmpty ? nil : result
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard draggedRows(info) != nil, (0...items.count).contains(row) else { return [] }
        table.setDropRow(row, dropOperation: .above); return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard let indexes = draggedRows(info) else { return false }
        return moveRows(indexes, to: row)
    }
}
