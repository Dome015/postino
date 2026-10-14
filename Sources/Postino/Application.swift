import AppKit
import RelayCore

/// Quit with terminateLater runs AppKit's modal loop. Continuations must run in
/// that mode as well as the normal event loop, including disk-save completions.
func afterAppKitEvent(_ work: @escaping () -> Void) {
    RunLoop.main.perform(inModes: [.common, .modalPanel], block: work)
    CFRunLoopWakeUp(CFRunLoopGetMain())
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainWindow(); makeMenu(); controller?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        if !CommandLine.arguments.contains("--demo") { controller?.updateController.startAutomaticChecks() }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !CommandLine.arguments.contains("--demo") { controller?.updateController.checkAutomaticallyIfDue() }
    }
    // The workspace window requests termination after closing, even when an
    // auxiliary environment/About window remains. Avoid a second automatic Quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private var terminationPending = false
    private var preparedUpdate: PreparedAppUpdate?
    func restartAfterUpdate(_ update: PreparedAppUpdate) {
        guard !terminationPending, let controller, !controller.confirmingClose else { update.discard(); return }
        preparedUpdate = update
        NSApp.terminate(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        // A close confirmation already in progress owns its sheet. Do not start
        // another shutdown request that could invalidate its eventual answer.
        guard !controller.confirmingClose else { return .terminateCancel }
        terminationPending = true
        // Reply only after this delegate call has returned terminateLater.
        afterAppKitEvent {
            controller.confirmCloseAll { approved in
                guard approved else {
                    self.terminationPending = false
                    self.preparedUpdate?.discard(); self.preparedUpdate = nil
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                controller.stopWork()
                controller.environmentWindow?.makeFirstResponder(nil)
                controller.window?.orderOut(nil)
                controller.environmentWindow?.orderOut(nil)
                controller.store.save {
                    if let update = self.preparedUpdate {
                        do { try update.launchHelper() }
                        catch {
                            update.discard(); self.preparedUpdate = nil; self.terminationPending = false
                            controller.closingApproved = false
                            sender.reply(toApplicationShouldTerminate: false)
                            controller.showWindow(nil)
                            controller.showError("Could not restart to install the update. \(error.localizedDescription)")
                            return
                        }
                    }
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        return .terminateLater
    }
    func makeMenu() {
        let menu = NSMenu(); NSApp.mainMenu = menu
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; menu.addItem(appItem)
        app.addItem(withTitle: "About Postino", action: #selector(about), keyEquivalent: "").target = self
        app.addItem(withTitle: "Check for updates…", action: #selector(MainWindow.checkForUpdates), keyEquivalent: "").target = controller
        app.addItem(.separator()); app.addItem(withTitle: "Hide Postino", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); app.addItem(withTitle: "Quit Postino", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File"); let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); fileItem.submenu = file; menu.addItem(fileItem)
        func action(_ title: String, _ selector: Selector, _ key: String, shift: Bool = false) { let i = file.addItem(withTitle: title, action: selector, keyEquivalent: key); i.target = controller; if shift { i.keyEquivalentModifierMask = [.command, .shift] } }
        action("New Request", #selector(MainWindow.newRequest), "n"); action("New Collection…", #selector(MainWindow.newCollection), "n", shift: true); action("Save Request", #selector(MainWindow.saveRequest), "s"); action("Copy as cURL", #selector(MainWindow.copyRequestAsCurl), "c", shift: true); action("Close Request", #selector(MainWindow.closeCurrentTab), "w"); file.addItem(.separator()); action("Import Postman JSON…", #selector(MainWindow.importFiles), "i"); action("Export Collection…", #selector(MainWindow.exportCollection), "e", shift: true); action("Save Response…", #selector(MainWindow.exportResponse), "s", shift: true); file.addItem(.separator()); action("Manage Environments…", #selector(MainWindow.editEnvironments), "e"); file.items.last?.keyEquivalentModifierMask = [.command, .option]
        let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        edit.addItem(.separator())
        edit.addItem(withTitle: "Duplicate", action: #selector(CollectionOutlineView.duplicate(_:)), keyEquivalent: "d")
        edit.addItem(withTitle: "Delete", action: #selector(CollectionOutlineView.deleteSelection(_:)), keyEquivalent: "\u{8}")
        func findItem(_ title: String, _ action: NSTextFinder.Action, _ key: String, shift: Bool = false) {
            let item = edit.addItem(withTitle: title, action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: key)
            item.tag = action.rawValue; item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command
        }
        edit.addItem(.separator())
        findItem("Find…", .showFindInterface, "f")
        findItem("Find and Replace…", .showReplaceInterface, "f"); edit.items.last?.keyEquivalentModifierMask = [.command, .option]
        findItem("Find Next", .nextMatch, "g")
        findItem("Find Previous", .previousMatch, "g", shift: true)
        findItem("Use Selection for Find", .setSearchString, "e")
        let window = NSMenu(title: "Window"); let wi = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); wi.submenu = window; menu.addItem(wi); window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"); window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""); NSApp.windowsMenu = window
    }
    var applicationLogo: NSImage? { Bundle.main.url(forResource: "PostinoFace", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } }
    @objc func about() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "Postino", .applicationVersion: "1.0", .credits: NSAttributedString(string: "A fast, native HTTP workspace.\nBuilt with Swift and AppKit.")]
        if let logo = applicationLogo { options[.applicationIcon] = logo }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
