import AppKit
import RelayCore

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
private final class PairTableView: NSTableView {
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
    var rows: [Pair] {
        get { items }
        set { items = newValue; table.reloadData(); table.deselectAll(nil); updateSelection() }
    }
    var changed: (([Pair]) -> Void)?
    var selectionChanged: (() -> Void)?
    var canRemoveRow: Bool { items.indices.contains(table.selectedRow) }
    var secret = false
    let table: NSTableView = PairTableView()
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
        column("enabled", "", 32, fixed: true)
        if hasTypes { column("type", "Type", 80, fixed: true) }
        column("key", configuration.keyTitle, configuration.keyWidth); column("value", configuration.valueTitle, 500)
        column("delete", "", 36, fixed: true)
        table.headerView = PairHeaderView(addButton: addButton)
        table.style = .plain; table.delegate = self; table.dataSource = self; table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 6, height: 0); table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = configuration.backgroundColor; table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = .separatorColor; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsEmptySelection = true
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
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = column?.identifier.rawValue else { return nil }
        guard items.indices.contains(row) else { return nil }
        let p = items[row]
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
        let text: NSTextField = secret && identifier == "value" && ["token", "password", "value"].contains(p.key) ? SecureInputField() : InputField()
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.stringValue = identifier == "key" ? p.key : (p.extra["type"] as? String == "file" ? (p.extra["src"] as? String ?? p.value) : p.value)
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
        changed?(items); updateSelection()
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
        let backwards = command == #selector(NSResponder.insertBacktab(_:))
        guard backwards || command == #selector(NSResponder.insertTab(_:)) else { return false }
        let next = field.tag + (backwards ? -1 : 1)
        guard next >= 0, next / 2 < numberOfRows(in: table) else { return false }
        focusInput(row: next / 2, value: next % 2 == 1); return true
    }
    private func focusInput(row: Int, value: Bool = false) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
        let column = table.column(withIdentifier: .init(value ? "value" : "key"))
        guard let host = table.view(atColumn: column, row: row, makeIfNecessary: true) as? PairInputCell, let field = host.input else { return }
        window?.makeFirstResponder(field); field.currentEditor()?.selectAll(nil)
    }
    @objc private func typeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag; guard items.indices.contains(row) else { return }
        items[row].extra["type"] = sender.indexOfSelectedItem == 1 ? "file" : "text"; changed?(items)
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: table.column(withIdentifier: .init("value"))))
    }
    @objc private func toggleRow(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        table.selectRowIndexes(IndexSet(integer: sender.tag), byExtendingSelection: false)
        items[sender.tag].enabled = sender.state == .on; changed?(items); updateSelection()
    }
    @objc func addRow() {
        window?.makeFirstResponder(nil); items.append(Pair()); table.reloadData(); changed?(items)
        focusInput(row: items.count - 1)
    }
    @objc private func deleteInline(_ sender: NSButton) { deleteRow(at: sender.tag) }
    @objc func removeRow() { deleteRow(at: table.selectedRow) }
    private func deleteRow(at index: Int) {
        guard items.indices.contains(index) else { return }
        // Commit the field editor before changing row tags or removing its view.
        window?.makeFirstResponder(nil); items.remove(at: index); table.reloadData(); changed?(items)
        if items.isEmpty { table.deselectAll(nil) }
        else { table.selectRowIndexes(IndexSet(integer: min(index, items.count - 1)), byExtendingSelection: false) }
        updateSelection()
    }
}
