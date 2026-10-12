import AppKit
import RelayCore

/// Exercise the real application run loop and termination delegate in separate
/// processes: a synchronous controller-only test misses AppKit close re-entry.
private final class LifecycleDelegate: NSObject, NSApplicationDelegate {
    let application = AppDelegate()
    let scenario = CommandLine.arguments.last!
    var timer: Timer?
    var started = Date()
    var answered = 0
    var cancelled = false
    var expectingTermination = false
    var savedName = "Original"
    var originalID = ""
    var clipboardContents: [NSPasteboardItem]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindow(); application.controller = controller; application.makeMenu()
        let collection = try! Collection(json: ["info": ["name": "Close checks"], "item": [["name": "Original", "request": ["method": "GET", "url": "http://127.0.0.1:18765/check"]]]])
        controller.store.collections = [collection]; controller.store.history = []
        controller.tabs = []; controller.current = nil; controller.selectedCollection = collection
        controller.open(collection.allRequests[0]); originalID = collection.allRequests[0].id
        if !["clean-window", "large-window", "environment-window", "tree-shortcuts"].contains(scenario) { controller.current!.request.name = "Changed" }
        if scenario == "multiple-save" || scenario == "multiple-cancel" {
            let request = RequestItem(item: ["name": "Other", "request": ["url": "http://127.0.0.1:18765/other"]])
            let node = CollectionNode(json: request.exported()); collection.nodes.append(node)
            controller.open(node.request!); controller.current!.request.name = "Other changed"
        }
        if scenario == "large-window" {
            let large = CollectionNode(json: ["name": "Large unopened request", "request": ["url": "http://127.0.0.1:18765/large", "body": ["mode": "raw", "raw": String(repeating: "large saved payload 📨 ", count: 500_000)]]])
            collection.nodes.append(large)
            controller.store.save()
        }
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        if scenario == "environment-window" { controller.editEnvironments() }
        timer = Timer(timeInterval: 0.05, repeats: true) { [self] _ in tick() }
        RunLoop.main.add(timer!, forMode: .common); RunLoop.main.add(timer!, forMode: .modalPanel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.scenario == "tree-shortcuts" { self.checkKeyboardRouting() }
            self.closeOrQuit()
        }
    }
    func checkKeyboardRouting() {
        let controller = application.controller!, window = controller.window!
        let clipboard = NSPasteboard.general
        clipboardContents = clipboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        let collection = controller.store.collections[0], node = collection.nodes[0]
        controller.reloadSidebar(selecting: node); window.makeFirstResponder(controller.outline); controller.sidebarSelected()
        precondition(window.firstResponder === controller.outline, "Clicking a request keeps tree focus")
        precondition(NSApp.target(forAction: #selector(CollectionOutlineView.copy(_:))) as? CollectionOutlineView === controller.outline, "Native Edit menu routes Copy to the focused tree")
        precondition(NSApp.sendAction(#selector(CollectionOutlineView.copy(_:)), to: nil, from: nil))
        precondition(NSApp.sendAction(#selector(CollectionOutlineView.paste(_:)), to: nil, from: nil))
        precondition(collection.nodes.count == 2 && collection.nodes[1].request!.id != originalID, "Responder-chain paste creates a fresh sibling")
        precondition(NSApp.sendAction(#selector(CollectionOutlineView.duplicate(_:)), to: nil, from: nil))
        precondition(collection.nodes.count == 3, "Duplicate can follow Paste without refocusing")
        window.makeFirstResponder(controller.url)
        precondition(NSApp.target(forAction: #selector(CollectionOutlineView.copy(_:))) as? CollectionOutlineView == nil, "Text-field Copy does not copy a tree item")
    }
    func closeOrQuit() {
        started = Date()
        if scenario.contains("quit") { NSApp.terminate(nil) }
        else { application.controller!.window!.performClose(nil) }
        // NSApplication.terminate intentionally runs a modal loop until its
        // reply. Measure window-close dispatch, excluding user sheet interaction.
        if !scenario.contains("quit") {
            precondition(Date().timeIntervalSince(started) < 0.35, "Window close must return to the event loop without blocking on disk persistence")
        }
    }
    func tick() {
        precondition(Date().timeIntervalSince(started) < 25, "The app must finish the close or quit after answering its sheet: \(scenario)")
        guard let controller = application.controller, let window = controller.window else { return }
        if let sheet = window.attachedSheet {
            guard sheet.isVisible else { return }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let buttons = descendants(sheet.contentView!).compactMap { $0 as? NSButton }
            let choice: String
            if cancelled { choice = "Discard" }
            else if scenario.contains("cancel") && (scenario != "multiple-cancel" || answered == 1) { choice = "Cancel" }
            else if scenario.contains("save") || scenario == "multiple-cancel" { choice = "Save" }
            else { choice = "Discard" }
            guard let button = buttons.first(where: { $0.title == choice }), button.isEnabled else { return }
            // Stop polling until AppKit removes this sheet to avoid clicking twice.
            if sheet.identifier?.rawValue == "answered" { return }
            sheet.identifier = .init("answered"); answered += 1
            if choice == "Save", answered == 1 { savedName = "Changed" }
            if choice == "Cancel" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    precondition(window.isVisible && !controller.closingApproved && !controller.confirmingClose, "Cancel keeps the app open and resets close state")
                    self.cancelled = true; self.closeOrQuit()
                }
            } else { expectingTermination = true }
            button.performClick(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        application.applicationShouldTerminateAfterLastWindowClosed(sender)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        application.applicationShouldTerminate(sender)
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        let controller = application.controller!
        precondition(["clean-window", "large-window", "environment-window", "tree-shortcuts"].contains(scenario) || expectingTermination, "Termination follows an approved close")
        if scenario.contains("cancel") { precondition(cancelled, "Cancel was actually exercised") }
        let data = try! Data(contentsOf: controller.store.directory.appendingPathComponent("workspace.json"))
        let json = try! Postman.read(data)
        let collections = (json["collections"] as! [JSON]).map { try! Collection(json: $0) }
        let request = collections.flatMap(\.allRequests).first { $0.id == originalID }!
        precondition(request.name == savedName, "Approved saves are persisted before the process exits; discarded drafts do not leak")
        if scenario == "multiple-save" { precondition(collections[0].allRequests[1].name == "Other changed") }
        if scenario == "multiple-cancel" { precondition(collections[0].allRequests[1].name == "Other") }
        if let clipboardContents {
            NSPasteboard.general.clearContents()
            if !clipboardContents.isEmpty { NSPasteboard.general.writeObjects(clipboardContents) }
        }
        print("Passed \(scenario): \(answered) sheet answers; shutdown completed in \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
        fflush(stdout)
    }
}

@main
struct LifecycleChecks {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = LifecycleDelegate(); app.delegate = delegate; app.run()
    }
}
