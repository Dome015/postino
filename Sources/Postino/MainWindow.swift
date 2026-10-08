import AppKit
import UniformTypeIdentifiers
import RelayCore

final class HistoryEntry: NSObject {
    let json: JSON
    init(_ json: JSON) { self.json = json }
}
final class RequestTab {
    let draft: RequestDraft; var request: RequestItem { draft.request }; var response: HTTPResult?; var transfer: HTTPTransfer?; var prettyFile: URL?; var error: String?; var generation = UUID(); var workCancellation = WorkCancellation(); var formatting = false; var destination: CollectionContainer?
    func resetWork() { workCancellation.cancel(); workCancellation = WorkCancellation(); generation = UUID(); formatting = false }
    init(_ request: RequestItem, saved: Bool = true) { draft = RequestDraft(request, saved: saved) }
}
final class MainWindow: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = Workspace(); var tabs: [RequestTab] = []; var current: RequestTab?; var sidebarMode = 0; var selectedCollection: Collection?
    let outline = NSOutlineView(); let search = InputSearchField(); let env = RelayPopup(); let method = RelayPopup(); let url = InputField(); let send = RelayButton(frame: .zero); let tabBar = NSView(); let tabScroll = NSScrollView(); let save = RelayButton(frame: .zero)
    let sidebarSplit = NSSplitViewController()
    let requestSegment = RelaySegments(labels: ["Body", "Params", "Headers", "Authorization"], trackingMode: .selectOne, target: nil, action: nil)
    let responseSegment = RelaySegments(labels: ["Body", "Headers"], trackingMode: .selectOne, target: nil, action: nil)
    let params = PairEditor(configuration: .parameters); let headers = PairEditor(configuration: .headers); let form = PairEditor(configuration: .form); let body = CodeEditor(editable: true); let response = CodeEditor(editable: false)
    let emptyResponse = Surface(bandLightColor); let emptyTitle = label("Send your first request", size: 15, weight: .semibold); let emptyMessage = label("The response will appear here.", size: 12, color: .secondaryLabelColor)
    let requestHost = Surface(bandDarkColor); let bodyHost = NSView(); let responseHost = NSView(); let bodyMode = RelayPopup(); let authMode = RelayPopup(); let authFields = PairEditor(configuration: .credentials)
    let status = label("Ready to send", weight: .medium, color: .secondaryLabelColor); let responseInfo = label("", size: 11, color: .secondaryLabelColor); let footer = label("", size: 11, color: .secondaryLabelColor)
    let chooseFile = RelayButton(frame: .zero); let pretty = RelayButton(frame: .zero); let saveResponse = RelayButton(frame: .zero); let copyResponse = RelayButton(frame: .zero); var copyingResponse = false; var copyFeedbackReset: DispatchWorkItem?; let responseFind = RelayButton(frame: .zero); let requestHint = label("", size: 11, color: .secondaryLabelColor)
    var sidebarDragNode: CollectionNode?; var sidebarDragToken: String?
    var collapsedFolders = Set<ObjectIdentifier>(); var restoringTree = false; var closingApproved = false; var confirmingClose = false
    var updating = false; var filtered: [Any] = []; var environmentWindow: NSWindow?; var environmentEditor: PairEditor?; var envName: NSTextField?; var environmentIndex = -1
    lazy var responseReader = ResponseReader(response)
    let worker = DispatchQueue(label: "relay.response", qos: .userInitiated, attributes: .concurrent)
    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Postino"; w.titlebarAppearsTransparent = true; w.minSize = NSSize(width: 980, height: 700); w.setFrameAutosaveName("PostauomoMain"); if let screen = NSScreen.main { var f = w.frame; f.size.width = min(f.width, screen.visibleFrame.width - 32); f.size.height = min(f.height, screen.visibleFrame.height - 32); w.setFrame(f, display: false) }; w.center()
        super.init(window: w); w.delegate = self
        build(); refreshEnvironments(); reloadSidebar()
        if let first = store.collections.first?.allRequests.first { open(first) } else { newRequest() }
    }
    required init?(coder: NSCoder) { fatalError() }
    func build() {
        guard let content = window?.contentView else { return }
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root); NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor), root.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        let split = NSSplitView(); sidebarSplit.splitView = split; sidebarSplit.view = split; split.isVertical = true; split.dividerStyle = .thin
        let sidebar = Surface(bandDarkColor); let main = Surface(canvasColor)
        let sidebarController = NSViewController(); sidebarController.view = sidebar
        let mainController = NSViewController(); mainController.view = main
        let sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.preferredThicknessFraction = 0.2; sidebarItem.minimumThickness = 190; sidebarItem.maximumThickness = 420; sidebarItem.canCollapse = false
        let mainItem = NSSplitViewItem(viewController: mainController); mainItem.minimumThickness = 620
        sidebarSplit.addSplitViewItem(sidebarItem); sidebarSplit.addSplitViewItem(mainItem)
        split.autosaveName = "PostauomoSidebarWidth"
        let logo = NSImageView(); logo.image = Bundle.main.url(forResource: "Logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }; logo.imageScaling = .scaleProportionallyUpOrDown; logo.setAccessibilityLabel("Postino logo"); logo.widthAnchor.constraint(equalToConstant: 40).isActive = true; logo.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let brand = stack([logo, label("Postino", size: 15, weight: .semibold), spacer()], spacing: 8)
        let brandBlock = padded(brand, x: 10, y: 8)
        brandBlock.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let sidebarSegment = RelaySegments(labels: ["Collections", "History"], trackingMode: .selectOne, target: self, action: #selector(sidebarSegmentChanged(_:))); sidebarSegment.selectedSegment = 0; compact(sidebarSegment); sidebarSegment.font = .systemFont(ofSize: 12)
        search.placeholderString = "Filter requests"; search.delegate = self; search.setAccessibilityLabel("Filter collections and requests")
        let column = NSTableColumn(identifier: .init("name")); column.width = 220; column.minWidth = 100; column.resizingMask = .autoresizingMask; outline.addTableColumn(column); outline.outlineTableColumn = column; outline.headerView = nil; outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; outline.rowHeight = 26; outline.delegate = self; outline.dataSource = self; outline.autoresizingMask = [.width]; outline.style = .sourceList; outline.indentationPerLevel = 14; outline.intercellSpacing = NSSize(width: 0, height: 0); outline.backgroundColor = bandDarkColor; outline.target = self; outline.action = #selector(sidebarSelected); outline.setAccessibilityLabel("Collections and requests")
        configureCollectionTree()
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = outline; sidebarScroll.hasVerticalScroller = true; sidebarScroll.autohidesScrollers = true; sidebarScroll.drawsBackground = false
        let filters = stack([stack([sidebarSegment, spacer()], spacing: 0), search], vertical: true, spacing: 8); filters.alignment = .width
        let topContent = stack([brandBlock, padded(filters, x: 10, top: 0, bottom: 8)], vertical: true, spacing: 0); topContent.alignment = .width
        let top = band(topContent, color: bandLightColor, name: "sidebarHeaderBand")
        let importButton = button("Import", symbol: "square.and.arrow.down", target: self, action: #selector(importFiles)); importButton.toolTip = "Import Postman collection or environment JSON (⌘I)"
        let exportButton = button("Export", symbol: "square.and.arrow.up", target: self, action: #selector(exportCollection)); exportButton.toolTip = "Export the selected collection as Postman v2.1 JSON (⇧⌘E)"
        let sideLayout = stack([top, sidebarScroll], vertical: true, spacing: 0); sideLayout.alignment = .width; pin(sideLayout, in: sidebar)
        let add = button("New request", symbol: "plus", target: self, action: #selector(newRequest)); let newCollectionButton = button("Collection", symbol: "folder.badge.plus", target: self, action: #selector(newCollection))
        env.target = self; env.action = #selector(environmentChanged); compact(env); env.widthAnchor.constraint(equalToConstant: 190).isActive = true; env.toolTip = "Active environment · variables override collection values"; env.setAccessibilityLabel("Active environment")
        let envEdit = button("", symbol: "slider.horizontal.3", target: self, action: #selector(editEnvironments)); envEdit.toolTip = "Manage environments"
        envEdit.style = .plain
        save.title = "Save"; save.target = self; save.action = #selector(saveRequest); save.toolTip = "Save request (⌘S)"
        let toolbar = ControlBar([add, newCollectionButton, save, spacer(), env, envEdit]); toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        tabScroll.documentView = tabBar; tabScroll.hasHorizontalScroller = true; tabScroll.autohidesScrollers = true; tabScroll.drawsBackground = true; tabScroll.backgroundColor = bandDarkColor; tabScroll.horizontalScrollElasticity = .none
        tabScroll.heightAnchor.constraint(equalToConstant: 44).isActive = true
        method.addItems(withTitles: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]); method.target = self; method.action = #selector(methodChanged); compact(method); method.font = .monospacedSystemFont(ofSize: 12, weight: .semibold); method.widthAnchor.constraint(equalToConstant: 90).isActive = true; method.setAccessibilityLabel("HTTP method")
        url.font = .monospacedSystemFont(ofSize: 13, weight: .regular); url.placeholderString = "https://api.example.com/v1/resource"; url.delegate = self; url.setAccessibilityLabel("Request URL");
        send.title = "Send"; send.target = self; send.action = #selector(sendRequest); send.style = .primary; send.keyEquivalent = "\r"; send.keyEquivalentModifierMask = .command; send.font = .systemFont(ofSize: 12, weight: .semibold); send.widthAnchor.constraint(equalToConstant: 80).isActive = true; send.toolTip = "Send request (⌘Return) · click again to cancel"
        let urlControls = stack([method, url, send], spacing: 8); urlControls.heightAnchor.constraint(equalToConstant: 28).isActive = true
        requestSegment.selectedSegment = 0; requestSegment.target = self; requestSegment.action = #selector(requestSectionChanged); compact(requestSegment); requestSegment.font = .systemFont(ofSize: 12)
        let segmentRow = stack([requestSegment, spacer(), requestHint]); segmentRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let requestControls = band(padded(stack([urlControls, segmentRow], vertical: true, spacing: 8), x: 10, y: 8), color: bandLightColor, name: "requestControlsBand")
        params.changed = { [weak self] rows in self?.current?.request.params = rows; self?.updateURLFromParams(); self?.draftChanged() }; headers.changed = { [weak self] rows in self?.current?.request.headers = rows; self?.draftChanged() }; form.changed = { [weak self] rows in self?.current?.request.form = rows; self?.draftChanged() }; body.changed = { [weak self] value in self?.current?.request.body = value; self?.draftChanged() }
        bodyMode.addItems(withTitles: ["JSON / raw text", "URL-encoded form", "Binary file", "Multipart form"]); compact(bodyMode); bodyMode.target = self; bodyMode.action = #selector(bodyModeChanged); bodyMode.setAccessibilityLabel("Request body format"); bodyMode.widthAnchor.constraint(greaterThanOrEqualToConstant: 184).isActive = true
        chooseFile.title = "Choose file…"; chooseFile.target = self; chooseFile.action = #selector(chooseBodyFile); let bodyToolbar = padded(stack([bodyMode, chooseFile, spacer()]), x: 10, top: 8, bottom: 0)
        let bodyLayout = stack([bodyToolbar, bodyHost], vertical: true, spacing: 0); bodyLayout.alignment = .width
        authMode.addItems(withTitles: ["Inherit from collection", "No authentication", "Bearer token", "Basic authentication", "API key", "Imported (preserved)"]); compact(authMode); authMode.target = self; authMode.action = #selector(authModeChanged); authFields.secret = true
        authFields.changed = { [weak self] rows in guard let self = self, let r = self.current?.request, let type = r.auth?["type"] as? String else { return }; r.auth?[type] = rows.map(\.json); self.draftChanged() }
        let authLayout = stack([padded(stack([authMode, spacer()]), x: 10, y: 8), authFields], vertical: true, spacing: 0); authLayout.alignment = .width
        for child in [bodyLayout, params, headers, authLayout] { pin(child, in: requestHost); child.isHidden = true }
        requestHost.identifier = .init("requestHost")
        let requestPanel = stack([requestControls, requestHost], vertical: true, spacing: 0); requestPanel.alignment = .width; requestPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 208).isActive = true
        responseSegment.selectedSegment = 0; responseSegment.target = self; responseSegment.action = #selector(responseSectionChanged); compact(responseSegment); responseSegment.font = .systemFont(ofSize: 12)
        pretty.title = "Pretty JSON";  pretty.target = self; pretty.action = #selector(togglePretty); pretty.toolTip = "Format JSON on disk without loading the full response"
        saveResponse.title = "Save…"; saveResponse.target = self; saveResponse.action = #selector(exportResponse)
        copyResponse.widthAnchor.constraint(equalToConstant: 96).isActive = true; copyResponse.title = "Copy body"; copyResponse.target = self; copyResponse.action = #selector(copyResponseBody); copyResponse.toolTip = "Copy the entire response body"; copyResponse.setAccessibilityLabel("Copy response body")
        let responseTop = padded(stack([label("Response", size: 13, weight: .semibold), status, spacer(), responseInfo]), x: 10, y: 8); responseTop.heightAnchor.constraint(equalToConstant: 32).isActive = true
        responseFind.title = "Find…"; responseFind.target = self; responseFind.action = #selector(showResponseFind); responseFind.toolTip = "Find in the entire response (⌘F)"
        let responseTools = padded(stack([responseSegment, pretty, spacer(), responseFind, copyResponse, saveResponse]), x: 10, y: 0); responseTools.heightAnchor.constraint(equalToConstant: 28).isActive = true
        responseReader.failed = { [weak self] message in self?.footer.stringValue = message }
        pin(response, in: responseHost, inset: 10, verticalInset: 8)
        pin(emptyResponse, in: responseHost)
        let emptyContent = stack([emptyTitle, emptyMessage, label("⌘ Return to send   ·   ⌘ I to import", size: 11, color: .tertiaryLabelColor)], vertical: true, spacing: 8)
        emptyContent.alignment = .centerX; emptyContent.translatesAutoresizingMaskIntoConstraints = false; emptyResponse.addSubview(emptyContent)
        NSLayoutConstraint.activate([emptyContent.centerXAnchor.constraint(equalTo: emptyResponse.centerXAnchor), emptyContent.centerYAnchor.constraint(equalTo: emptyResponse.centerYAnchor)])
        responseHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        requestHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let sharedFooter = ControlBar([importButton, exportButton, spacer(), footer], color: bandDarkColor); sharedFooter.heightAnchor.constraint(equalToConstant: 44).isActive = true
        responseHost.setContentHuggingPriority(.init(1), for: .vertical)
        responseHost.setContentCompressionResistancePriority(.init(1), for: .vertical)
        let responsePanel = Surface(bandLightColor); responsePanel.identifier = .init("responseBand")
        for child in [responseTop, responseTools, responseHost] { child.translatesAutoresizingMaskIntoConstraints = false; responsePanel.addSubview(child); child.leadingAnchor.constraint(equalTo: responsePanel.leadingAnchor).isActive = true; child.trailingAnchor.constraint(equalTo: responsePanel.trailingAnchor).isActive = true }
        NSLayoutConstraint.activate([responseTop.topAnchor.constraint(equalTo: responsePanel.topAnchor), responseTools.topAnchor.constraint(equalTo: responseTop.bottomAnchor), responseHost.topAnchor.constraint(equalTo: responseTools.bottomAnchor), responseHost.bottomAnchor.constraint(equalTo: responsePanel.bottomAnchor)])
        responsePanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        responseHost.wantsLayer = true; responseHost.layer?.masksToBounds = true
        let verticalSplit = ResizeSplitView(); verticalSplit.isVertical = false; verticalSplit.dividerStyle = .thin; verticalSplit.addArrangedSubview(requestPanel); verticalSplit.addArrangedSubview(responsePanel)
        verticalSplit.setContentHuggingPriority(.init(1), for: .vertical)
        verticalSplit.setContentCompressionResistancePriority(.init(1), for: .vertical)
        let mainLayout = stack([toolbar, tabScroll, verticalSplit], vertical: true, spacing: 0); mainLayout.alignment = .width; pin(mainLayout, in: main)
        split.setContentHuggingPriority(.init(1), for: .vertical)
        let rootLayout = stack([split, sharedFooter], vertical: true, spacing: 0); rootLayout.alignment = .width; pin(rootLayout, in: root)
        DispatchQueue.main.async { verticalSplit.setPosition(278, ofDividerAt: 0) }
    }
    func draftChanged() { if !updating { refreshTabBar() } }
    func commitFields() { window?.makeFirstResponder(nil); if let r = current?.request { if r.url != url.stringValue { r.setURL(url.stringValue) } } }
    func refreshEnvironments() { env.removeAllItems(); env.addItem(withTitle: "No environment"); env.addItems(withTitles: store.environments.map(\.name)); env.selectItem(at: store.selectedEnvironment + 1) }
    @objc func environmentChanged() { commitFields(); store.selectedEnvironment = env.indexOfSelectedItem - 1; store.save() }
    func refreshTabBar() {
        tabBar.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 10; var selectedFrame = NSRect.zero
        for (i, tab) in tabs.enumerated() {
            let view = RequestTabView(request: tab.request, dirty: tab.draft.isDirty, active: current === tab, index: i, target: self)
            let textWidth = (tab.request.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
            let methodWidth = RequestTabView.methodWidth(tab.request.method)
            let width = min(280, max(164, ceil(textWidth) + methodWidth + 72))
            view.frame = NSRect(x: x, y: 8, width: width, height: 28); if current === tab { selectedFrame = view.frame }; tabBar.addSubview(view); x += width + 6
        }
        tabBar.frame = NSRect(x: 0, y: 0, width: max(tabScroll.contentSize.width, x + 10), height: 44)
        tabBar.scrollToVisible(selectedFrame)
        save.isEnabled = current?.draft.isDirty == true
        window?.isDocumentEdited = current?.draft.isDirty == true
    }
    func open(_ request: RequestItem) {
        commitFields()
        if let tab = tabs.first(where: { $0.draft.source === request }) { current = tab }
        else { let saved = store.collections.contains { $0.allRequests.contains { $0 === request } }; let tab = RequestTab(request, saved: saved); tabs.append(tab); current = tab }
        displayCurrent()
    }
    @objc func selectTab(_ sender: NSButton) { commitFields(); guard tabs.indices.contains(sender.tag) else { return }; current = tabs[sender.tag]; displayCurrent() }
    @objc func closeCurrentTab() { guard let current, let i = tabs.firstIndex(where: { $0 === current }) else { return }; let sender = NSButton(); sender.tag = i; closeTab(sender) }
    @objc func closeTab(_ sender: NSButton) {
        commitFields(); guard tabs.indices.contains(sender.tag) else { return }; let tab = tabs[sender.tag]
        confirmDiscard(tab) { [weak self] approved in
            guard approved, let self, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.tabs.remove(at: index); tab.transfer?.cancel(); tab.resetWork()
            if let file = tab.response?.file { try? FileManager.default.removeItem(at: file) }; if let file = tab.prettyFile { try? FileManager.default.removeItem(at: file) }
            if self.current === tab { self.current = self.tabs.isEmpty ? nil : self.tabs[min(index, self.tabs.count - 1)] }
            if self.tabs.isEmpty { self.newRequest() } else { self.displayCurrent() }
        }
    }
    func confirmDiscard(_ tab: RequestTab, completion: @escaping (Bool) -> Void) {
        guard tab.draft.isDirty else { completion(true); return }
        let alert = NSAlert(); alert.messageText = "Save changes to “\(tab.request.name)”?"; alert.informativeText = "Your changes have not been saved to the collection."; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window!) { [weak self] result in
            if result == .alertFirstButtonReturn { self?.saveTab(tab); completion(true) }
            else { completion(result == .alertSecondButtonReturn) }
        }
    }
    func displayCurrent() {
        guard let tab = current else { return }; updating = true; let r = tab.request; url.stringValue = r.url; if method.itemTitles.contains(r.method) { method.selectItem(withTitle: r.method) } else { method.addItem(withTitle: r.method); method.selectItem(withTitle: r.method) }; params.rows = r.params; headers.rows = r.headers; body.set(r.body, highlight: r.bodyMode == "raw"); form.rows = r.form
        bodyMode.selectItem(at: ["raw", "urlencoded", "file", "formdata"].firstIndex(of: r.bodyMode) ?? 3)
        let type = r.auth?["type"] as? String; authMode.selectItem(at: type == nil ? 0 : (["noauth", "bearer", "basic", "apikey"].firstIndex(of: type!).map { $0 + 1 } ?? 5)); authFields.rows = type.map { (r.auth?[$0] as? [JSON] ?? []).map(Pair.init) } ?? []
        updating = false; refreshTabBar(); requestSectionChanged(); showBodyMode(); renderResponse()
    }
    @objc func methodChanged() { current?.request.method = method.titleOfSelectedItem ?? "GET"; draftChanged(); reloadSidebar() }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === search { reloadSidebar(); return }; if updating { return }; if obj.object as? NSTextField === url { current?.request.setURL(url.stringValue); params.rows = current?.request.params ?? []; draftChanged() } }

    func updateURLFromParams() { guard let r = current?.request else { return }; r.url = r.resolvedRawURL; url.stringValue = r.url }
    @objc func requestSectionChanged() { for (i, child) in requestHost.subviews.enumerated() { child.isHidden = i != requestSegment.selectedSegment }; let hasScripts = (current?.request.original["event"] as? [JSON])?.isEmpty == false || selectedCollection?.original["event"] != nil; requestHint.stringValue = hasScripts ? "Postman scripts preserved · not executed" : "" }
    func showBodyMode() { chooseFile.isHidden = current?.request.bodyMode != "file"; body.syntaxHighlighting = current?.request.bodyMode == "raw"; bodyHost.subviews.forEach { $0.removeFromSuperview() }; if ["urlencoded", "formdata"].contains(current?.request.bodyMode ?? "") { pin(form, in: bodyHost) } else { pin(body, in: bodyHost, inset: 10, verticalInset: 8); body.text.isEditable = current?.request.bodyMode != "file"; if current?.request.bodyMode == "file" { body.set(current?.request.body ?? "Choose a file for a memory-efficient upload.") } } }
    @objc func bodyModeChanged() { current?.request.bodyMode = ["raw", "urlencoded", "file", "formdata"][bodyMode.indexOfSelectedItem]; showBodyMode(); draftChanged() }
    @objc func chooseBodyFile() { let p = NSOpenPanel(); p.canChooseDirectories = false; p.beginSheetModal(for: window!) { [weak self] result in guard result == .OK, let url = p.url, let self = self else { return }; self.current?.request.bodyMode = "file"; self.current?.request.body = url.path; self.bodyMode.selectItem(at: 2); self.showBodyMode(); self.draftChanged() } }
    @objc func authModeChanged() {
        guard let r = current?.request else { return }; let index = authMode.indexOfSelectedItem
        if index == 0 { r.auth = nil; authFields.rows = [] } else if index < 5 { let type = ["noauth", "bearer", "basic", "apikey"][index - 1]; let keys: [String] = type == "bearer" ? ["token"] : type == "basic" ? ["username", "password"] : type == "apikey" ? ["key", "value", "in"] : []; let rows = keys.map { Pair($0, $0 == "in" ? "header" : "") }; r.auth = ["type": type, type: rows.map(\.json)]; authFields.rows = rows }; draftChanged()
    }
    @objc func newRequest() { commitFields(); let r = RequestItem(); let tab = RequestTab(r, saved: false); tab.destination = insertionContainer(for: outline.item(atRow: outline.selectedRow)); tabs.append(tab); current = tab; displayCurrent(); window?.makeFirstResponder(url) }
    @objc func saveRequest() {
        commitFields(); guard let tab = current else { return }
        if tab.draft.source == nil && tab.request.name == "Untitled request" {
            prompt("Save request", value: "Untitled request") { [weak self] title in tab.request.name = title; self?.saveTab(tab) }
        } else { saveTab(tab) }
    }
    func saveTab(_ tab: RequestTab) {
        let old = tab.draft.source; let saved = tab.draft.save(); var replaced = false
        func replace(_ nodes: [CollectionNode]) { for node in nodes { if let old, node.request === old { node.request = saved; node.name = saved.name; replaced = true }; replace(node.children) } }
        for collection in store.collections { replace(collection.nodes) }
        if !replaced {
            if store.collections.isEmpty { makeCollection("My collection") }
            let collection = selectedCollection.flatMap { selected in store.collections.first { $0 === selected } } ?? store.collections[0]
            let target = tab.destination.flatMap { $0.isValid(in: store.collections) ? $0 : nil } ?? CollectionContainer(collection: collection)
            let node = CollectionNode(json: saved.exported()); node.request = saved; target.nodes.append(node)
            CollectionTree.refreshInheritance(in: target.collection); selectedCollection = target.collection; tab.destination = nil
            revealTreeItem(node)
        }
        synchronizeDraftInheritance(); store.save(); reloadSidebar(); refreshTabBar()
    }
    func makeCollection(_ name: String) { let c = try! Collection(json: ["info": ["name": name], "item": [JSON]()]); store.collections.append(c); selectedCollection = c; store.save(); reloadSidebar() }
    @objc func newCollection() { prompt("New collection", value: "My collection") { [weak self] in self?.makeCollection($0) } }
    func prompt(_ title: String, value: String, completion: @escaping (String) -> Void) { let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); let field = InputField(); field.stringValue = value; field.frame = NSRect(x: 0, y: 0, width: 320, height: 32); alert.accessoryView = field; alert.beginSheetModal(for: window!) { result in if result == .alertFirstButtonReturn && !field.stringValue.isEmpty { completion(field.stringValue) } }; alert.window.makeFirstResponder(field) }
    func reloadSidebar(selecting item: Any? = nil) {
        let selection = item ?? outline.item(atRow: outline.selectedRow)
        let q = search.stringValue.lowercased(); filtered = sidebarMode == 0 ? store.collections.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.allRequests.contains(where: { $0.name.lowercased().contains(q) || $0.url.lowercased().contains(q) }) } : store.history.filter { q.isEmpty || Pair.string($0["name"]).lowercased().contains(q) || Pair.string($0["url"]).lowercased().contains(q) }.map(HistoryEntry.init)
        restoringTree = true; outline.reloadData()
        if sidebarMode == 0 {
            func expand(_ item: AnyObject) {
                if search.stringValue.isEmpty && collapsedFolders.contains(ObjectIdentifier(item)) { return }
                outline.expandItem(item)
                for child in children(item) { if let c = child as? CollectionNode, c.request == nil { expand(c) } }
            }
            for c in filtered.compactMap({ $0 as? Collection }) { expand(c) }
        }; restoringTree = false
        if let selection { let row = outline.row(forItem: selection); if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } }
    }
    func children(_ item: Any?) -> [Any] {
        guard let item = item else { return filtered }
        let nodes: [CollectionNode]; if let c = item as? Collection { nodes = c.nodes } else if let n = item as? CollectionNode { nodes = n.children } else { return [] }
        let q = search.stringValue.lowercased(); return nodes.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.allRequests.contains(where: { $0.name.lowercased().contains(q) || $0.url.lowercased().contains(q) }) }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(item)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let collection = item as? Collection { return !collection.nodes.isEmpty }
        guard let node = item as? CollectionNode else { return false }
        return node.request == nil && !node.children.isEmpty
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { AccentRowView() }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let c = item as? Collection { return folderCell(c.name, bold: true) }
        if let n = item as? CollectionNode { if let r = n.request { let verb = label(r.method, size: 9, weight: .bold, color: methodColor(r.method)); verb.widthAnchor.constraint(equalToConstant: max(38, RequestTabView.methodWidth(verb.stringValue))).isActive = true; let title = label(r.name, size: 12); title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); return TreeCellView(stack([verb, title], spacing: 4)) }; return folderCell(n.name, bold: false) }
        if let history = item as? HistoryEntry { let j = history.json; let verb = label(Pair.string(j["method"]), size: 9, weight: .bold, color: methodColor(Pair.string(j["method"]))); verb.widthAnchor.constraint(equalToConstant: max(38, RequestTabView.methodWidth(verb.stringValue))).isActive = true; return TreeCellView(stack([verb, label(Pair.string(j["name"]), size: 12)], spacing: 4)) }; return nil
    }
    func folderCell(_ name: String, bold: Bool) -> NSView { TreeCellView(label(name, size: 12, weight: bold ? .semibold : .regular)) }
    @objc func sidebarSegmentChanged(_ sender: RelaySegments) { sidebarMode = sender.selectedSegment; reloadSidebar() }
    @objc func sidebarSelected() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let item = outline.item(atRow: row) else { return }
        if outlineView(outline, isItemExpandable: item), let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown {
            let point = outline.convert(event.locationInWindow, from: nil)
            if !outline.frameOfOutlineCell(atRow: row).contains(point) { if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) } }
        }
        if let c = item as? Collection { selectedCollection = c }
        if let n = item as? CollectionNode { func contains(_ nodes: [CollectionNode]) -> Bool { nodes.contains { $0 === n || contains($0.children) } }
            selectedCollection = store.collections.first { contains($0.nodes) }; if let r = n.request { open(r) } }
        if let history = item as? HistoryEntry, let snapshot = history.json["snapshot"] as? JSON { open(RequestItem(item: snapshot)) }
    }
    func outlineViewItemDidCollapse(_ notification: Notification) { if !restoringTree, let item = notification.userInfo?["NSObject"] as AnyObject? { collapsedFolders.insert(ObjectIdentifier(item)) } }
    func outlineViewItemDidExpand(_ notification: Notification) { if !restoringTree, let item = notification.userInfo?["NSObject"] as AnyObject? { collapsedFolders.remove(ObjectIdentifier(item)) } }
    func contextItem() -> Any? { outline.item(atRow: outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow) }
    @objc func renameNode() { let item = contextItem(); if let c = item as? Collection { prompt("Rename collection", value: c.name) { [weak self] value in c.name = value; self?.store.save(); self?.reloadSidebar() } } else if let n = item as? CollectionNode { prompt("Rename \(n.request == nil ? "folder" : "request")", value: n.request?.name ?? n.name) { [weak self] value in n.name = value; n.request?.name = value; self?.tabs.filter { $0.draft.source === n.request }.forEach { $0.request.name = value }; self?.store.save(); self?.reloadSidebar(); self?.displayCurrent() } } }
    @objc func deleteNode() {
        guard let item = contextItem(), item is Collection || item is CollectionNode else { return }; let alert = NSAlert(); alert.messageText = "Delete this \(item is Collection ? "collection" : "item")?"; alert.informativeText = "This removes it from your local workspace."; alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel"); alert.beginSheetModal(for: window!) { [weak self] result in guard result == .alertFirstButtonReturn, let self = self else { return }; if let c = item as? Collection { self.store.collections.removeAll { $0 === c }; if self.selectedCollection === c { self.selectedCollection = nil } } else if let n = item as? CollectionNode { func remove(_ nodes: inout [CollectionNode]) { nodes.removeAll { $0 === n }; for child in nodes { remove(&child.children) } }; for c in self.store.collections { remove(&c.nodes) } }; self.store.save(); self.reloadSidebar() }
    }
    @objc func importFiles() {
        commitFields(); let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = true; panel.message = "Select Postman collection v2.1 or environment JSON files."; panel.beginSheetModal(for: window!) { [weak self] result in guard result == .OK, let self = self else { return }; let urls = panel.urls; self.status.stringValue = "Importing…"; self.worker.async {
            var collections: [Collection] = []; var environments: [Environment] = []; var errors: [String] = []
            for url in urls { do { let json = try Postman.read(Data(contentsOf: url)); if json["info"] != nil { collections.append(try Collection(json: json)) } else { environments.append(try Environment(json: json)) } } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") } }
            DispatchQueue.main.async { self.store.collections.append(contentsOf: collections); self.store.environments.append(contentsOf: environments); if let c = collections.first { self.selectedCollection = c; if let r = c.allRequests.first { self.open(r) } }; self.refreshEnvironments(); self.store.save(); self.reloadSidebar(); self.requestHint.stringValue = "Imported \(collections.count) collections, \(environments.count) environments"; if !errors.isEmpty { self.showError(errors.joined(separator: "\n\n")) } }
        } }
    }
    @objc func exportCollection() {
        commitFields(); let c = (contextItem() as? Collection) ?? selectedCollection ?? store.collections.first
        guard let c = c else { showError("Create or import a collection first."); return }; saveJSON(c.exported(), filename: c.name + ".postman_collection.json")
    }
    func saveJSON(_ json: JSON, filename: String) { let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = filename; panel.beginSheetModal(for: window!) { [weak self] result in guard result == .OK, let url = panel.url, let self = self else { return }; self.worker.async { do { try Postman.encode(json).write(to: url, options: .atomic) } catch { DispatchQueue.main.async { self.showError(error.localizedDescription) } } } } }
    func showError(_ message: String) { let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Postino"; alert.informativeText = message; alert.beginSheetModal(for: window!) }
    @objc func sendRequest() {
        commitFields(); guard let tab = current else { return }; if let transfer = tab.transfer { transfer.cancel(); return }
        do {
            let variables = store.environments.indices.contains(store.selectedEnvironment) ? store.environments[store.selectedEnvironment].variables : [:]
            let (request, file) = try RequestBuilder.build(tab.request, environment: variables)
            let snapshot = tab.request.exported(); let sentName = tab.request.name
            tab.error = nil; tab.resetWork()
            if let old = tab.response?.file { try? FileManager.default.removeItem(at: old) }; if let old = tab.prettyFile { try? FileManager.default.removeItem(at: old) }; tab.response = nil; tab.prettyFile = nil
            let transfer = try HTTPTransfer(directory: store.responses, completion: { [weak self, weak tab] result in
                guard let self = self, let tab = tab else { return }; tab.transfer = nil
                switch result { case .success(let response): tab.response = response; self.store.history.insert(["name": sentName, "method": request.httpMethod ?? "GET", "url": request.url?.absoluteString ?? "", "status": response.status, "date": ISO8601DateFormatter().string(from: Date()), "snapshot": snapshot], at: 0); self.store.history = Array(self.store.history.prefix(100)); self.store.save(); self.reloadSidebar()
                case .failure(let error): tab.error = (error as NSError).code == NSURLErrorCancelled ? "Request cancelled." : error.localizedDescription }
                if self.current === tab { self.renderResponse(); if let response = tab.response, response.bytes < 2_000_000, response.contentType.contains("json") { self.togglePretty() } }
            }, progress: { [weak self, weak tab] bytes in guard let self = self, let tab = tab, self.current === tab else { return }; self.status.stringValue = "Receiving \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))…" })
            tab.transfer = transfer; transfer.start(request, file: file); renderResponse()
        } catch { tab.error = error.localizedDescription; renderResponse() }
    }
    static func reason(_ status: Int) -> String { [200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 206: "Partial Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 413: "Payload Too Large", 415: "Unsupported Media Type", 422: "Unprocessable Content", 429: "Too Many Requests", 500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout"][status] ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized }
    var activeFile: URL? { current?.prettyFile ?? current?.response?.file }
    @objc func responseSectionChanged() { renderResponse() }
    func renderResponse() {
        guard let tab = current else { return }; emptyResponse.isHidden = tab.response != nil; response.isHidden = tab.response == nil; emptyTitle.stringValue = tab.transfer != nil ? "Receiving response…" : tab.error == nil ? "Send your first request" : "Request could not be completed"; emptyMessage.stringValue = tab.error ?? (tab.transfer != nil ? "Streaming directly to disk." : "The response will appear here."); send.title = tab.transfer == nil ? "Send" : "Cancel"; pretty.isEnabled = !tab.formatting && tab.response != nil && (tab.response!.contentType.contains("json") || tab.response!.contentType.isEmpty); pretty.title = tab.formatting ? "Formatting…" : tab.prettyFile == nil ? "Pretty JSON" : "Raw"; saveResponse.isEnabled = tab.response != nil; copyResponse.isEnabled = tab.response != nil && !copyingResponse; responseFind.isEnabled = tab.response != nil
        if tab.transfer != nil { status.stringValue = "Sending request…"; status.textColor = accentInk; responseInfo.stringValue = ""; response.set(""); footer.stringValue = "Downloading directly to disk. You can cancel at any time."; responseReader.clear(); return }
        guard let result = tab.response else { status.stringValue = tab.error == nil ? "Ready to send" : "Request failed"; status.textColor = tab.error == nil ? .secondaryLabelColor : .systemRed; responseInfo.stringValue = ""; response.set(""); footer.stringValue = ""; responseReader.clear(); return }
        status.stringValue = "\(result.status) \(Self.reason(result.status))"; status.textColor = result.status < 400 ? .systemGreen : .systemRed; responseInfo.stringValue = "\(String(format: "%.0f", result.duration * 1000)) ms   ·   \(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file))"
        if responseSegment.selectedSegment == 1 { response.set(result.headers.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")); footer.stringValue = ""; responseReader.clear(); return }
        footer.stringValue = ""
        if let file = activeFile { responseReader.open(file, highlight: result.contentType.contains("json")) }
    }
    @objc func togglePretty() {
        guard let tab = current, let result = tab.response else { return }; if let old = tab.prettyFile { try? FileManager.default.removeItem(at: old); tab.prettyFile = nil; renderResponse(); return }
        let generation = tab.generation; let cancellation = tab.workCancellation; tab.formatting = true; let destination = store.responses.appendingPathComponent(UUID().uuidString + ".pretty.json"); pretty.isEnabled = false; pretty.title = "Formatting…"; footer.stringValue = "Formatting JSON on disk… you can continue working."
        worker.async { do { try ResponseFile.pretty(result.file, destination: destination, cancelled: { cancellation.isCancelled }); DispatchQueue.main.async { guard tab.generation == generation else { try? FileManager.default.removeItem(at: destination); return }; tab.formatting = false; tab.prettyFile = destination; if self.current === tab { self.renderResponse() } } } catch { DispatchQueue.main.async { guard !cancellation.isCancelled else { return }; tab.formatting = false; if self.current === tab { self.renderResponse(); self.showError(error.localizedDescription) } } } }
    }
    @objc func showResponseFind() {
        responseSegment.selectedSegment = 0; renderResponse()
        window?.makeFirstResponder(response.text)
        responseReader.findClient.finder.performAction(.showFindInterface)
    }
    @objc func copyResponseBody() {
        guard !copyingResponse, let file = activeFile else { return }
        copyFeedbackReset?.cancel(); copyResponse.setAccessibilityLabel("Copy response body"); copyingResponse = true; copyResponse.isEnabled = false; copyResponse.title = "Copying…"
        worker.async {
            let result = Result { try String(contentsOf: file, encoding: .utf8) }
            DispatchQueue.main.async {
                self.copyingResponse = false; self.copyResponse.title = "Copy body"; self.copyResponse.isEnabled = self.current?.response != nil
                switch result {
                case .success(let text):
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(text, forType: .string) {
                        self.copyResponse.title = "Copied!"
                        self.copyResponse.setAccessibilityLabel("Response body copied")
                        NSAccessibility.post(element: self.copyResponse, notification: .announcementRequested, userInfo: [.announcement: "Response body copied to clipboard", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                        let reset = DispatchWorkItem { [weak self] in self?.copyResponse.title = "Copy body"; self?.copyResponse.setAccessibilityLabel("Copy response body") }
                        self.copyFeedbackReset = reset; DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: reset)
                    } else { self.showError("Could not copy the response body to the clipboard.") }
                case .failure(let error): self.showError("Could not copy the response body: \(error.localizedDescription)")
                }
            }
        }
    }
    @objc func exportResponse() { guard let result = current?.response else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = result.contentType.contains("json") ? "response.json" : "response.txt"; panel.beginSheetModal(for: window!) { [weak self] state in guard state == .OK, let destination = panel.url, let self = self else { return }; self.worker.async { do { let h = try FileHandle(forReadingFrom: result.file); defer { try? h.close() }; guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw RelayError.message("Cannot write response file.") }; let out = try FileHandle(forWritingTo: destination); defer { try? out.close() }; try ResponseFile.copy(from: h, to: out) } catch { DispatchQueue.main.async { self.showError(error.localizedDescription) } } } } }
    func confirmCloseAll(completion: @escaping (Bool) -> Void) {
        commitFields(); guard !confirmingClose else { completion(false); return }; confirmingClose = true
        let dirty = tabs.filter { $0.draft.isDirty }
        func next(_ index: Int) { if index == dirty.count { confirmingClose = false; closingApproved = true; completion(true); return }; confirmDiscard(dirty[index]) { approved in if approved { next(index + 1) } else { self.confirmingClose = false; completion(false) } } }
        next(0)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if closingApproved { return true }; confirmCloseAll { approved in if approved { sender.performClose(nil) } }; return false }
    func windowWillClose(_ notification: Notification) { commitFields(); store.save(now: true); tabs.forEach { $0.transfer?.cancel(); $0.resetWork() }; NSApp.terminate(nil) }
}
