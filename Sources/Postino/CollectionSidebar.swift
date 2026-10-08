import AppKit
import RelayCore

private let collectionDragType = NSPasteboard.PasteboardType("app.postauomo.collection-node")

extension MainWindow {
    func configureCollectionTree() {
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
            add("Export collection…", #selector(exportCollection))
            menu.addItem(.separator())
            add("Rename…", #selector(renameNode))
            add("Delete…", #selector(deleteNode))
        } else {
            add("New collection…", #selector(newCollection))
        }
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
        collapsedFolders.remove(ObjectIdentifier(location.container.collection))
        var folder = location.container.folder
        while let parent = folder {
            collapsedFolders.remove(ObjectIdentifier(parent))
            folder = CollectionTree.location(of: parent, in: store.collections)?.container.folder
        }
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
