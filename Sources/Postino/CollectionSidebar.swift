import AppKit
import RelayCore

private let collectionDragType = NSPasteboard.PasteboardType("app.postauomo.collection-node")
private let collectionClipboardType = NSPasteboard.PasteboardType("app.postino.collection-clipboard")

/// Edit menu actions follow the responder chain, so typing in an input never
/// copies or deletes a tree item just because that item is still selected.
final class CollectionOutlineView: NSOutlineView {
    weak var controller: MainWindow?
    var selectedTreeItem: Any? { selectedRow >= 0 ? item(atRow: selectedRow) : nil }
    @objc func copy(_ sender: Any?) { controller?.copyTreeItem(selectedTreeItem, cut: false) }
    @objc func cut(_ sender: Any?) { controller?.copyTreeItem(selectedTreeItem, cut: true) }
    @objc func paste(_ sender: Any?) { controller?.pasteTreeItem() }
    @objc func deleteSelection(_ sender: Any?) { controller?.deleteTreeItem(selectedTreeItem) }
    @objc func duplicate(_ sender: Any?) { controller?.duplicateTreeItem(selectedTreeItem) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        if window?.firstResponder === self, modifiers == .command, [51, 117].contains(event.keyCode),
           controller?.sidebarMode == 0, selectedTreeItem != nil {
            deleteSelection(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty && (event.keyCode == 36 || event.keyCode == 76) {
            if controller?.sidebarMode == 0 { controller?.renameTreeItem(selectedTreeItem) }
            return
        }
        super.keyDown(with: event)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let edits: [Selector] = [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)), #selector(deleteSelection(_:)), #selector(duplicate(_:))]
        guard let action = item.action, edits.contains(action) else { return super.validateUserInterfaceItem(item) }
        guard let controller, controller.sidebarMode == 0 else { return false }
        if item.action == #selector(paste(_:)) { return controller.canPasteTreeItem }
        return selectedTreeItem is Collection || selectedTreeItem is CollectionNode
    }
}

extension MainWindow {
    func configureCollectionTree() {
        outline.controller = self
        let menu = NSMenu(); menu.delegate = self; outline.menu = menu
        outline.registerForDraggedTypes([collectionDragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
    }
    func insertionContainer(for item: Any?) -> CollectionContainer? {
        if let collection = item as? Collection { return CollectionContainer(collection: collection) }
        guard let node = item as? CollectionNode, let location = CollectionTree.location(of: node, in: store.collections) else { return nil }
        return node.request == nil ? CollectionContainer(collection: location.container.collection, folder: node) : location.container
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Capture the clicked object, rather than depending on a selection changed by another action.
        let item = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) : nil
        func add(_ title: String, _ action: Selector, object: Any? = nil) {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); entry.target = self; entry.representedObject = object
        }
        guard sidebarMode == 0 else { return }
        let isContainer = item is Collection || (item as? CollectionNode).map { $0.request == nil } == true
        if isContainer, let target = insertionContainer(for: item) {
            add("Add request", #selector(addRequestToContainer(_:)), object: target)
            add("Add folder…", #selector(addFolderToContainer(_:)), object: target)
            menu.addItem(.separator())
        }
        if item is Collection || item is CollectionNode {
            add("Copy", #selector(copyContextTreeItem(_:)), object: item)
            add("Cut", #selector(cutContextTreeItem(_:)), object: item)
            add("Duplicate", #selector(duplicateContextTreeItem(_:)), object: item)
            if canPasteTreeItem { add("Paste", #selector(pasteContextTreeItem(_:)), object: item) }
            menu.addItem(.separator())
            add("Export collection…", #selector(exportCollection))
            menu.addItem(.separator())
            add("Rename…", #selector(renameNode))
            add("Delete…", #selector(deleteNode))
        } else {
            add("New collection…", #selector(newCollection))
        }
    }
    var treeClipboard: NSPasteboard { .general }
    private func clipboardData(for item: Any?) -> JSON? {
        if let collection = item as? Collection { return ["kind": "collection", "data": collection.exported()] }
        if let node = item as? CollectionNode { return ["kind": "node", "data": node.exported()] }
        return nil
    }
    private var treeClipboardData: JSON? {
        guard let string = treeClipboard.string(forType: collectionClipboardType),
              let data = string.data(using: .utf8), let json = try? Postman.read(data),
              json["data"] is JSON, ["collection", "node"].contains(json["kind"] as? String ?? "") else { return nil }
        return json
    }
    var canPasteTreeItem: Bool {
        guard sidebarMode == 0, let json = treeClipboardData else { return false }
        if json["kind"] as? String == "collection" { return true }
        guard let target = insertionContainer(for: outline.selectedTreeItem) else { return false }
        if sidebarCutChangeCount == treeClipboard.changeCount, let node = sidebarCutItem as? CollectionNode,
           CollectionTree.location(of: node, in: store.collections) != nil {
            return CollectionTree.canMove(node, to: target, in: store.collections)
        }
        return true
    }
    @objc func copyContextTreeItem(_ sender: NSMenuItem) { copyTreeItem(sender.representedObject, cut: false) }
    @objc func cutContextTreeItem(_ sender: NSMenuItem) { copyTreeItem(sender.representedObject, cut: true) }
    @objc func duplicateContextTreeItem(_ sender: NSMenuItem) { duplicateTreeItem(sender.representedObject) }
    @objc func pasteContextTreeItem(_ sender: NSMenuItem) {
        let row = outline.row(forItem: sender.representedObject)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        pasteTreeItem()
    }
    func copyTreeItem(_ item: Any?, cut: Bool) {
        guard sidebarMode == 0, let json = clipboardData(for: item),
              let data = try? Postman.encode(json), let string = String(data: data, encoding: .utf8),
              let exported = json["data"] as? JSON, let plain = try? Postman.encode(exported) else { return }
        let entry = NSPasteboardItem(); entry.setString(string, forType: collectionClipboardType)
        entry.setString(String(decoding: plain, as: UTF8.self), forType: .string)
        treeClipboard.clearContents()
        guard treeClipboard.writeObjects([entry]) else { return }
        sidebarCutItem = cut ? item as AnyObject? : nil
        sidebarCutChangeCount = cut ? treeClipboard.changeCount : nil
    }
    func pasteTreeItem() {
        guard canPasteTreeItem, let json = treeClipboardData, let data = json["data"] as? JSON else { return }
        commitFields()
        defer { window?.makeFirstResponder(outline) }
        let cut = sidebarCutChangeCount == treeClipboard.changeCount ? sidebarCutItem : nil
        if json["kind"] as? String == "collection" {
            let collection: Collection
            if let existing = cut as? Collection, store.collections.contains(where: { $0 === existing }) {
                collection = existing
                if outline.selectedTreeItem as? Collection === existing { return }
                store.collections.removeAll { $0 === existing }
            } else {
                guard let copy = try? Collection(json: data) else { return }; collection = copy
                var info = collection.original["info"] as? JSON ?? [:]; info["_postman_id"] = UUID().uuidString; collection.original["info"] = info
            }
            let selected = (outline.selectedTreeItem as? Collection) ?? insertionContainer(for: outline.selectedTreeItem)?.collection
            let insertion = selected.flatMap { selected in store.collections.firstIndex { $0 === selected }.map { $0 + 1 } } ?? store.collections.count
            store.collections.insert(collection, at: insertion); selectedCollection = collection
            expandedFolders.insert(ObjectIdentifier(collection)); reloadSidebar(selecting: collection)
        } else {
            guard let target = insertionContainer(for: outline.selectedTreeItem) else { return }
            let selection = outline.selectedTreeItem as? CollectionNode
            let insertion = selection.flatMap { $0.request != nil ? CollectionTree.location(of: $0, in: store.collections).map { $0.index + 1 } : nil } ?? target.nodes.count
            let node: CollectionNode
            if let existing = cut as? CollectionNode, CollectionTree.location(of: existing, in: store.collections) != nil {
                guard CollectionTree.move(existing, to: target, at: insertion, in: store.collections) else { return }; node = existing
            } else {
                node = CollectionNode(json: data); target.nodes.insert(node, at: insertion); CollectionTree.refreshInheritance(in: target.collection)
            }
            selectedCollection = target.collection; synchronizeDraftInheritance(); revealTreeItem(node)
        }
        sidebarCutItem = nil; sidebarCutChangeCount = nil
        store.save(); requestSectionChanged()
    }
    func duplicateTreeItem(_ item: Any?) {
        guard sidebarMode == 0 else { return }
        commitFields()
        defer { window?.makeFirstResponder(outline) }
        if let collection = item as? Collection, let index = store.collections.firstIndex(where: { $0 === collection }),
           let copy = try? Collection(json: collection.exported()) {
            copy.name += " copy"; var info = copy.original["info"] as? JSON ?? [:]; info["_postman_id"] = UUID().uuidString; copy.original["info"] = info
            store.collections.insert(copy, at: index + 1); selectedCollection = copy; reloadSidebar(selecting: copy)
        } else if let node = item as? CollectionNode, let location = CollectionTree.location(of: node, in: store.collections) {
            let copy = CollectionNode(json: node.exported()); copy.name += " copy"; copy.request?.name = copy.name
            location.container.nodes.insert(copy, at: location.index + 1); CollectionTree.refreshInheritance(in: location.container.collection); revealTreeItem(copy)
        } else { return }
        store.save()
    }
    func deleteTreeItem(_ item: Any?) {
        guard sidebarMode == 0, let item, item is Collection || item is CollectionNode else { return }
        commitFields()
        window?.makeFirstResponder(outline)
        let requests = (item as? Collection)?.allRequests ?? (item as? CollectionNode)?.allRequests ?? []
        let affected = tabs.filter { tab in requests.contains { $0 === tab.draft.source } }
        let alert = NSAlert(); alert.messageText = "Delete this \(item is Collection ? "collection" : "item")?"
        alert.informativeText = affected.contains { $0.draft.isDirty }
            ? "This removes it from your local workspace and closes its open requests, discarding their unsaved changes."
            : "This removes it from your local workspace and closes its open requests."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window!) { [weak self] result in
            guard let self else { return }
            if result == .alertFirstButtonReturn { self.removeTreeItem(item) }
            self.window?.makeFirstResponder(self.outline)
        }
    }
    func removeTreeItem(_ item: Any) {
        let requests = (item as? Collection)?.allRequests ?? (item as? CollectionNode)?.allRequests ?? []
        let affected = tabs.filter { tab in requests.contains { $0 === tab.draft.source } }
        if let collection = item as? Collection {
            store.collections.removeAll { $0 === collection }; if selectedCollection === collection { selectedCollection = nil }
        } else if let node = item as? CollectionNode, let location = CollectionTree.location(of: node, in: store.collections) {
            location.container.nodes.remove(at: location.index)
        } else { return }
        for tab in affected {
            tab.transfer?.cancel(); tab.resetWork()
            let files = [tab.response?.file, tab.prettyFile].compactMap { $0 }
            worker.async { for file in files { try? FileManager.default.removeItem(at: file) } }
        }
        tabs.removeAll { tab in affected.contains { $0 === tab } }
        if let current, affected.contains(where: { $0 === current }) {
            self.current = tabs.first
            displayCurrent()
        }
        store.save(); reloadSidebar(); refreshTabBar()
    }
    @objc func addRequestToContainer(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? CollectionContainer, target.isValid(in: store.collections) else { return }
        commitFields()
        let node = CollectionNode(json: ["name": "Untitled request", "request": ["method": "GET", "url": ""]])
        target.nodes.append(node); CollectionTree.refreshInheritance(in: target.collection)
        selectedCollection = target.collection; store.save(); revealTreeItem(node)
        if let request = node.request { open(request); window?.makeFirstResponder(url) }
    }
    @objc func addFolderToContainer(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? CollectionContainer, target.isValid(in: store.collections) else { return }
        commitFields()
        prompt("New folder", value: "New folder") { [weak self] title in
            guard let self, target.isValid(in: self.store.collections) else { return }
            let node = CollectionNode(json: ["name": title, "item": [JSON]()])
            target.nodes.append(node); self.selectedCollection = target.collection; self.store.save(); self.revealTreeItem(node)
        }
    }
    func revealTreeItem(_ node: CollectionNode) {
        guard let location = CollectionTree.location(of: node, in: store.collections) else { return }
        expandedFolders.insert(ObjectIdentifier(location.container.collection))
        var folder = location.container.folder
        while let parent = folder {
            expandedFolders.insert(ObjectIdentifier(parent))
            folder = CollectionTree.location(of: parent, in: store.collections)?.container.folder
        }
        sidebarMode = 0; sidebarSegment.selectedSegment = 0
        reloadSidebar(selecting: node)
        if outline.row(forItem: node) < 0, !search.stringValue.isEmpty { search.stringValue = ""; reloadSidebar(selecting: node) }
        let row = outline.row(forItem: node); if row >= 0 { outline.scrollRowToVisible(row) }
    }
    func synchronizeDraftInheritance() {
        for tab in tabs { if let source = tab.draft.source { tab.request.variables = source.variables; tab.request.inheritedAuth = source.inheritedAuth } }
    }
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard sidebarMode == 0, let node = item as? CollectionNode else { return nil }
        let token = UUID().uuidString; sidebarDragNode = node; sidebarDragToken = token
        let writer = NSPasteboardItem(); writer.setString(token, forType: collectionDragType); return writer
    }
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        sidebarDragNode = nil; sidebarDragToken = nil
    }
    private func draggedNode(_ info: NSDraggingInfo) -> CollectionNode? {
        guard sidebarMode == 0, let source = info.draggingSource as? NSOutlineView, source === outline,
              let token = sidebarDragToken, info.draggingPasteboard.string(forType: collectionDragType) == token else { return nil }
        return sidebarDragNode
    }
    func dropTarget(item: Any?, childIndex: Int) -> (CollectionContainer, Int)? {
        guard let target = insertionContainer(for: item) else { return nil }
        if let node = item as? CollectionNode, node.request != nil {
            guard childIndex == NSOutlineViewDropOnItemIndex,
                  let location = CollectionTree.location(of: node, in: store.collections) else { return nil }
            return (location.container, location.index + 1)
        }
        if childIndex == NSOutlineViewDropOnItemIndex { return (target, target.nodes.count) }
        let visible = children(item).compactMap { $0 as? CollectionNode }
        guard (0...visible.count).contains(childIndex) else { return nil }
        // Convert filtered insertion positions to the persisted sibling order.
        if childIndex < visible.count, let index = target.nodes.firstIndex(where: { $0 === visible[childIndex] }) { return (target, index) }
        if let last = visible.last, let index = target.nodes.firstIndex(where: { $0 === last }) { return (target, index + 1) }
        return (target, target.nodes.count)
    }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let node = draggedNode(info), let (target, _) = dropTarget(item: item, childIndex: index),
              CollectionTree.canMove(node, to: target, in: store.collections) else { return [] }
        if let requestNode = item as? CollectionNode, requestNode.request != nil {
            guard requestNode !== node else { return [] }
            let parent: Any = target.folder.map { $0 as Any } ?? target.collection
            let visible = children(parent).compactMap { $0 as? CollectionNode }
            if let position = visible.firstIndex(where: { $0 === requestNode }) { outlineView.setDropItem(parent, dropChildIndex: position + 1) }
        }
        return .move
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let node = draggedNode(info), let (target, insertion) = dropTarget(item: item, childIndex: index) else { return false }
        commitFields()
        guard CollectionTree.move(node, to: target, at: insertion, in: store.collections) else { return false }
        selectedCollection = target.collection; synchronizeDraftInheritance(); store.save(); revealTreeItem(node); requestSectionChanged()
        return true
    }
}
