import AppKit
import RelayCore

private final class TestDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { (draggingSource as? NSView)?.window }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(source: NSOutlineView) { draggingSource = source; super.init() }
    deinit { draggingPasteboard.releaseGlobally() }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination destination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
struct SidebarChecks {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let controller = MainWindow()
        precondition(controller.tabs.isEmpty && controller.current == nil && !controller.emptyWorkspace.isHidden, "Startup has no open requests")
        precondition(controller.outline.numberOfRows == controller.store.collections.count && controller.store.collections.allSatisfy { !controller.outline.isItemExpanded($0) }, "Startup collections and folders are collapsed")
        try checkHistoryAndFirstSave(controller)
        controller.tabs = []; controller.current = nil; controller.store.history = []; controller.expandedFolders = []; controller.search.stringValue = ""; controller.sidebarMode = 0
        let first = try Collection(json: ["info": ["name": "First"], "item": [["name": "Folder", "item": [["name": "Keep", "request": ["url": "https://example.com"]], ["name": "Hidden", "request": ["url": "https://example.com"]], ["name": "Keep last", "request": ["url": "https://example.com"]]]]]])
        let second = try Collection(json: ["info": ["name": "Second"], "auth": ["type": "bearer"], "variable": [["key": "host", "value": "second"]], "item": [JSON]()])
        controller.tabs = []; controller.current = nil; controller.store.collections = [first, second]; controller.selectedCollection = first
        controller.reloadSidebar()
        let folder = first.nodes[0], target = CollectionContainer(collection: second)
        let action = NSMenuItem(); action.representedObject = target
        controller.addRequestToContainer(action)
        precondition(first.allRequests.count == 3 && second.allRequests.count == 1, "Context action creates inside its captured target, regardless of previous selection")
        let created = second.nodes[0]
        precondition(controller.current?.draft.source === created.request && created.request?.variables["host"] == "second", "New request is open and inherits its destination settings")
        precondition(controller.outline.item(atRow: controller.outline.selectedRow) as? CollectionNode === created, "New request is revealed and selected")
        controller.current!.request.name = "Edited in new location"; controller.commitFields()
        precondition(controller.current!.draft.isDirty, "Naming the new request edits an independent draft")
        precondition(CollectionTree.move(created, to: CollectionContainer(collection: first, folder: folder), at: 0, in: controller.store.collections), "Move the open request into another folder")
        controller.synchronizeDraftInheritance(); controller.saveTab(controller.current!)
        precondition(folder.children[0].request?.name == "Edited in new location" && second.nodes.isEmpty, "Saving after a move updates the new location, without recreating the old entry")
        controller.search.stringValue = "Keep"; controller.reloadSidebar()
        let filteredStart = controller.dropTarget(item: folder, childIndex: 0)!
        let filteredBetween = controller.dropTarget(item: folder, childIndex: 1)!
        let filteredEnd = controller.dropTarget(item: folder, childIndex: 2)!
        precondition(filteredStart.1 == 1 && filteredBetween.1 == 3 && filteredEnd.1 == 4, "Filtered drop indices map to persisted sibling positions")
        precondition(controller.dropTarget(item: nil, childIndex: 0) == nil, "Requests cannot be dropped outside a collection")
        precondition(controller.dropTarget(item: folder.children[1], childIndex: NSOutlineViewDropOnItemIndex)?.1 == 2, "Dropping on a request resolves to its sibling insertion position")
        controller.revealTreeItem(folder.children[0])
        precondition(controller.search.stringValue.isEmpty && controller.outline.selectedRow >= 0, "Creation reveals the item even if a previous filter would hide it")
        controller.outline.selectRowIndexes(IndexSet(integer: controller.outline.row(forItem: folder)), byExtendingSelection: false)
        controller.newRequest(); let unsaved = controller.current!
        controller.outline.selectRowIndexes(IndexSet(integer: controller.outline.row(forItem: second)), byExtendingSelection: false)
        controller.current!.request.name = "Saved at root"; controller.commitFields(); controller.saveTab(unsaved)
        precondition(first.nodes.last?.request?.name == "Saved at root" && second.nodes.isEmpty, "Toolbar requests save at the first expanded collection root, regardless of folder selection")
        let moving = folder.children[0]
        controller.open(moving.request!); controller.current!.request.name = "Unsaved during drag"; controller.commitFields()
        let drag = TestDrag(source: controller.outline)
        let writer = controller.outlineView(controller.outline, pasteboardWriterForItem: moving)!
        drag.draggingPasteboard.writeObjects([writer])
        precondition(controller.outlineView(controller.outline, validateDrop: drag, proposedItem: second, proposedChildIndex: NSOutlineViewDropOnItemIndex) == .move, "Native drag validation accepts another collection")
        precondition(controller.outlineView(controller.outline, acceptDrop: drag, item: second, childIndex: NSOutlineViewDropOnItemIndex), "Native drop handler moves into the destination")
        precondition(second.nodes[0] === moving && controller.current!.draft.isDirty && controller.current!.request.name == "Unsaved during drag", "Native drop preserves the open unsaved draft")
        precondition(controller.current!.request.variables["host"] == "second", "Native drop refreshes inherited settings on open drafts")
        controller.saveTab(controller.current!)
        precondition(second.nodes[0].request?.name == "Unsaved during drag", "Save after native drop updates the destination")
        drag.draggingSource = NSOutlineView()
        precondition(controller.outlineView(controller.outline, validateDrop: drag, proposedItem: first, proposedChildIndex: NSOutlineViewDropOnItemIndex).isEmpty, "Foreign drag sources are rejected")
        controller.store.save(now: true)
        let reloaded = Workspace()
        precondition(reloaded.collections[0].nodes.last?.request?.name == "Saved at root", "Tree edits persist to the workspace")
        let clipboard = NSPasteboard.general
        let savedClipboard = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let saved = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
            return saved
        } ?? []
        defer { clipboard.clearContents(); if !savedClipboard.isEmpty { clipboard.writeObjects(savedClipboard) } }
        func select(_ item: Any) {
            controller.search.stringValue = ""; controller.reloadSidebar(selecting: item)
            precondition(controller.outline.selectedRow >= 0)
        }
        select(moving)
        controller.outline.copy(nil)
        let clipboardJSON = try Postman.read(Data(clipboard.string(forType: .string)!.utf8))
        precondition(clipboardJSON["name"] as? String == moving.name, "Copy also provides interoperable JSON text")
        let copiedIDs = Set(first.allRequests.map(\.id) + second.allRequests.map(\.id))
        select(folder); controller.outline.paste(nil)
        let pasted = folder.children.last!
        precondition(pasted !== moving && pasted.request?.name == moving.request?.name && !copiedIDs.contains(pasted.request!.id), "Copy/paste preserves content with fresh request identity")
        select(pasted); controller.open(pasted.request!); controller.current!.request.name = "Draft survives cut"
        controller.outline.cut(nil)
        precondition(folder.children.contains { $0 === pasted }, "Cut does not remove data until paste succeeds")
        select(second); controller.outline.paste(nil)
        precondition(second.nodes.last === pasted && !folder.children.contains { $0 === pasted }, "Cut/paste moves the existing request")
        precondition(controller.window!.firstResponder === controller.outline, "Paste keeps keyboard focus in the tree for subsequent shortcuts")
        precondition(controller.current!.draft.source === pasted.request && controller.current!.draft.isDirty && controller.current!.request.variables["host"] == "second", "Cut/paste retains the dirty open draft and refreshes inheritance")
        select(first); controller.outline.copy(nil); controller.outline.paste(nil)
        let copiedCollection = controller.selectedCollection!
        precondition(copiedCollection !== first && copiedCollection.allRequests.count == first.allRequests.count, "Entire collections can be copied")
        precondition(Set(copiedCollection.allRequests.map(\.id)).isDisjoint(with: Set(first.allRequests.map(\.id))), "Copied collection requests have fresh identities")
        select(folder); controller.outline.cut(nil); select(folder)
        precondition(!controller.canPasteTreeItem, "A cut folder cannot be pasted into itself")
        clipboard.clearContents(); clipboard.setString("ordinary text", forType: .string)
        select(second)
        precondition(!controller.canPasteTreeItem, "Unrelated clipboard contents do not move a previously cut item")
        select(moving); let beforeDuplicate = second.nodes.count
        controller.outline.duplicate(nil)
        precondition(second.nodes.count == beforeDuplicate + 1 && second.nodes[1].name.hasSuffix(" copy"), "Duplicate inserts a fresh sibling without using the clipboard")
        precondition(controller.window!.firstResponder === controller.outline, "Duplicate keeps keyboard focus in the tree")
        controller.removeTreeItem(pasted)
        precondition(!controller.tabs.contains { $0.draft.source === pasted.request }, "Deleting a request closes its draft, preventing accidental resurrection on Save")
        controller.sidebarMode = 1
        let copyItem = NSMenuItem(title: "Copy", action: #selector(CollectionOutlineView.copy(_:)), keyEquivalent: "c")
        precondition(!controller.outline.validateUserInterfaceItem(copyItem), "History does not expose collection editing actions")
        controller.sidebarMode = 0; controller.reloadSidebar(); select(moving)
        let application = AppDelegate(); application.controller = controller; application.makeMenu()
        controller.showWindow(nil); controller.window!.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        controller.window!.makeFirstResponder(controller.outline)
        controller.sidebarSelected()
        precondition(controller.window!.firstResponder === controller.outline, "Opening a selected request keeps keyboard focus in the tree")
        controller.window!.makeFirstResponder(controller.url)
        precondition(controller.window!.firstResponder !== controller.outline, "Text input takes editing focus away from the tree")
        let edit = NSApp.mainMenu!.items.first { $0.title == "Edit" }!.submenu!
        precondition(edit.items.first { $0.title == "Delete" }?.keyEquivalent == "\u{8}", "Delete is bound to Command-Backspace")
        let deleteEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        precondition(!controller.outline.performKeyEquivalent(with: deleteEvent) && controller.window!.attachedSheet == nil, "Command-Delete in a text input never deletes a tree item")
        controller.window!.makeFirstResponder(controller.outline)
        precondition(controller.outline.performKeyEquivalent(with: deleteEvent) && controller.window!.attachedSheet != nil, "The physical Delete key opens a confirmation when the tree has focus")
        controller.window!.endSheet(controller.window!.attachedSheet!, returnCode: .alertSecondButtonReturn)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        print("Passed history, first-save placement, collapsed defaults, sidebar creation, selection, drag/drop, persistence, copy/cut/paste, duplication, and deletion checks")
    }
    static func checkHistoryAndFirstSave(_ controller: MainWindow) throws {
        let first = try Collection(json: ["info": ["name": "First"], "item": [["name": "Folder", "item": [["name": "Original", "request": ["url": "{{host}}/original"]]]]]])
        let second = try Collection(json: ["info": ["name": "Second"], "variable": [["key": "host", "value": "second"]], "item": [["name": "Other", "request": ["url": "https://example.com/other"]]]])
        controller.tabs = []; controller.current = nil; controller.store.collections = [first, second]; controller.expandedFolders = []
        controller.reloadSidebar()
        let folder = first.nodes[0]
        precondition(controller.outline.numberOfRows == 2, "Newly loaded collections start collapsed")
        controller.outline.expandItem(first)
        precondition(!controller.outline.isItemExpanded(folder), "Expanding a collection leaves its folders collapsed")
        controller.outline.expandItem(folder); controller.reloadSidebar()
        precondition(controller.outline.isItemExpanded(first) && controller.outline.isItemExpanded(folder), "User expansions survive sidebar reloads")
        controller.outline.collapseItem(first); controller.reloadSidebar()
        precondition(!controller.outline.isItemExpanded(first), "User collapse survives sidebar reloads")
        controller.search.stringValue = "Original"; controller.reloadSidebar()
        precondition(controller.outline.row(forItem: folder.children[0]) >= 0, "Filtering temporarily reveals matching nested requests")
        controller.search.stringValue = ""; controller.reloadSidebar()
        precondition(!controller.outline.isItemExpanded(first), "Clearing search restores the user's collapsed collection")
        func saveNew(_ name: String) -> RequestTab {
            controller.newRequest(); let tab = controller.current!
            tab.request.name = name; controller.commitFields(); controller.saveTab(tab)
            let node = controller.outline.selectedTreeItem as! CollectionNode
            precondition(node.request === tab.draft.source && controller.outline.isItemExpanded(CollectionTree.location(of: node, in: controller.store.collections)!.container.collection), "First save selects and reveals the stored request")
            return tab
        }
        controller.selectedCollection = second
        _ = saveNew("No expanded collections")
        precondition(first.nodes.last?.request?.name == "No expanded collections", "No expanded collections chooses the first collection regardless of selection")
        controller.outline.collapseItem(first); controller.outline.expandItem(second)
        controller.newRequest(); let delayed = controller.current!
        controller.outline.collapseItem(second); controller.outline.expandItem(first)
        delayed.request.name = "Chosen at save"; controller.commitFields(); controller.saveTab(delayed)
        precondition(first.nodes.last?.request?.name == "Chosen at save", "The destination is chosen when saving, after expansion changes")
        controller.outline.collapseItem(first); controller.outline.expandItem(second)
        _ = saveNew("One expanded collection")
        precondition(second.nodes.last?.request?.name == "One expanded collection", "One expanded collection receives a top-level request")
        controller.outline.expandItem(first)
        _ = saveNew("Multiple expanded collections")
        precondition(first.nodes.last?.request?.name == "Multiple expanded collections", "Multiple expanded collections chooses the first in tree order")
        let imported = try Collection(json: first.exported())
        controller.search.stringValue = "Original"; controller.reloadSidebar()
        controller.applyImport(collections: [imported], environments: [])
        precondition(controller.search.stringValue.isEmpty && !controller.outline.isItemExpanded(imported) && !controller.outline.isItemExpanded(imported.nodes[0]) && controller.outline.isItemExpanded(first), "Imported collection and folders start collapsed, preserving existing expansions")
        let original = folder.children[0].request!
        let history: JSON = ["name": original.name, "method": original.method, "url": original.url, "snapshot": original.exported(), "sourceRequestID": original.id]
        controller.store.history = [history]; controller.store.save(now: true)
        let reloaded = Workspace()
        precondition(reloaded.history[0]["sourceRequestID"] as? String == reloaded.collections[0].allRequests[0].id, "History origin identity survives workspace persistence")
        controller.sidebarMode = 1; controller.sidebarSegment.selectedSegment = 1; controller.reloadSidebar()
        controller.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); controller.sidebarSelected()
        let ephemeral = controller.current!
        precondition(ephemeral.draft.isEphemeral && ephemeral.draft.source == nil && !ephemeral.draft.isDirty && controller.save.isEnabled && !controller.window!.isDocumentEdited, "Opening history enables explicit Save without a dirty indicator")
        precondition(ephemeral.request.id != original.id, "History copies have independent identities")
        ephemeral.request.body = "Edited snapshot"; controller.body.set(ephemeral.request.body); controller.draftChanged()
        var approved = false
        controller.confirmDiscard(ephemeral) { approved = $0 }
        precondition(approved && controller.window!.attachedSheet == nil && !ephemeral.draft.isDirty, "Ephemeral edits can close without an unsaved warning")
        precondition(original.body.isEmpty, "Ephemeral edits never mutate the original saved request")
        // The original may have moved since this snapshot was opened.
        precondition(CollectionTree.move(folder.children[0], to: CollectionContainer(collection: second), at: 0, in: controller.store.collections))
        controller.outline.collapseItem(second); controller.selectedCollection = first
        controller.saveRequest()
        precondition(second.nodes.last?.request === ephemeral.draft.source && first.nodes.last?.request?.name == "Multiple expanded collections", "Explicit history Save follows the original request's collection, including moves")
        precondition(!ephemeral.draft.isEphemeral && !ephemeral.draft.isDirty && !controller.save.isEnabled && controller.sidebarMode == 0 && controller.sidebarSegment.selectedSegment == 0, "Saved history becomes a normal stored tab and reveals Collections")
        precondition(ephemeral.request.variables["host"] == "second" && original.body.isEmpty, "History Save inherits its new collection without overwriting the original")
        let count = second.nodes.count
        ephemeral.request.body = "Normal saved draft"; controller.draftChanged()
        precondition(ephemeral.draft.isDirty && controller.save.isEnabled && controller.window!.isDocumentEdited, "Subsequent edits use normal saved-request dirty state")
        controller.saveRequest()
        precondition(second.nodes.count == count && second.nodes.last?.request?.body == "Normal saved draft", "Subsequent Save updates the same stored history copy")
        var legacy = history; legacy.removeValue(forKey: "sourceRequestID")
        controller.openHistory(HistoryEntry(legacy))
        precondition(controller.current!.historySourceRequestID == nil, "Legacy history never guesses between matching saved copies")
        original.name = "Renamed original"; legacy["snapshot"] = original.exported()
        controller.openHistory(HistoryEntry(legacy))
        precondition(controller.current!.historySourceRequestID == original.id, "Legacy history resolves an unambiguous original request")
        controller.store.collections = []; controller.expandedFolders = []; controller.reloadSidebar()
        _ = saveNew("First ever request")
        precondition(controller.store.collections.count == 1 && controller.store.collections[0].name == "My requests" && controller.store.collections[0].nodes.count == 1, "Saving without collections creates My requests and reveals the request")
        let saved = controller.current!
        controller.tabs = [saved]; controller.removeTreeItem(controller.store.collections[0])
        precondition(controller.tabs.isEmpty && controller.current == nil && !controller.emptyWorkspace.isHidden && controller.editorWorkspace.isHidden, "Deleting the last open request returns to the empty workspace")
    }

}
