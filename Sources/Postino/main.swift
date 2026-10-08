import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainWindow(); makeMenu(); controller?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, !controller.closingApproved else { return .terminateNow }
        controller.commitFields()
        if !controller.tabs.contains(where: { $0.draft.isDirty }) { controller.closingApproved = true; return .terminateNow }
        controller.confirmCloseAll { sender.reply(toApplicationShouldTerminate: $0) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { controller?.commitFields(); controller?.store.save(now: true) }
    func makeMenu() {
        let menu = NSMenu(); NSApp.mainMenu = menu
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; menu.addItem(appItem)
        app.addItem(withTitle: "About Postino", action: #selector(about), keyEquivalent: "").target = self; app.addItem(.separator()); app.addItem(withTitle: "Hide Postino", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); app.addItem(withTitle: "Quit Postino", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File"); let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); fileItem.submenu = file; menu.addItem(fileItem)
        func action(_ title: String, _ selector: Selector, _ key: String, shift: Bool = false) { let i = file.addItem(withTitle: title, action: selector, keyEquivalent: key); i.target = controller; if shift { i.keyEquivalentModifierMask = [.command, .shift] } }
        action("New Request", #selector(MainWindow.newRequest), "n"); action("New Collection…", #selector(MainWindow.newCollection), "n", shift: true); action("Save Request", #selector(MainWindow.saveRequest), "s"); action("Close Request", #selector(MainWindow.closeCurrentTab), "w"); file.addItem(.separator()); action("Import Postman JSON…", #selector(MainWindow.importFiles), "i"); action("Export Collection…", #selector(MainWindow.exportCollection), "e", shift: true); action("Save Response…", #selector(MainWindow.exportResponse), "s", shift: true); file.addItem(.separator()); action("Manage Environments…", #selector(MainWindow.editEnvironments), "e"); file.items.last?.keyEquivalentModifierMask = [.command, .option]
        let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
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
let app = NSApplication.shared; app.setActivationPolicy(.regular); let delegate = AppDelegate(); app.delegate = delegate; app.run()
