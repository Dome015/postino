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
        let controller = MainWindow()
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
        controller.current!.request.name = "Captured folder"; controller.commitFields(); controller.saveTab(unsaved)
        precondition(folder.children.last?.request?.name == "Captured folder" && second.nodes.isEmpty, "Toolbar request creation retains its original folder until Save")
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
        precondition(reloaded.collections[0].nodes[0].children.last?.request?.name == "Captured folder", "Tree edits persist to the workspace")
        print("Passed sidebar creation, selection, filtered drop, moved draft save, and workspace persistence checks")
    }
}
