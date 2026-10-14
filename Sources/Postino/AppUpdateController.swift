import AppKit
import RelayCore

/// Background checks stay quiet unless a newer release is available. Installation
/// starts only when the user chooses Update and restart.
final class AppUpdateController {
    private weak var window: NSWindow?
    private let checker: AppUpdateChecker
    private let defaults: UserDefaults
    private let installed: InstalledRelease
    private let canPresent: () -> Bool
    private let stateChanged: (Bool) -> Void
    private let restart: (PreparedAppUpdate) -> Void
    private var timer: Timer?
    private var sheetObserver: NSObjectProtocol?
    private var pendingResult: Result<AppUpdateResult, Error>?
    private var notifiedAt: [String: Date] = [:]
    private var installer: AppUpdateInstaller?
    private var downloadSheet: NSAlert?
    private var manualRequested = false
    private(set) var isChecking = false
    private let lastCheckKey = "PostinoLastUpdateCheck"

    init(window: NSWindow?, defaults: UserDefaults = .standard, checker: AppUpdateChecker = AppUpdateChecker(),
         installed: InstalledRelease = InstalledRelease(info: Bundle.main.infoDictionary ?? [:]),
         canPresent: @escaping () -> Bool, stateChanged: @escaping (Bool) -> Void,
         restart: @escaping (PreparedAppUpdate) -> Void) {
        self.window = window; self.defaults = defaults; self.checker = checker; self.installed = installed
        self.canPresent = canPresent; self.stateChanged = stateChanged; self.restart = restart
        if let window {
            sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.presentPendingRelease() }
            }
        }
    }
    deinit {
        timer?.invalidate()
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
    }
    func startAutomaticChecks() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkAutomaticallyIfDue() }
        checkAutomaticallyIfDue()
    }
    func checkAutomaticallyIfDue() {
        presentPendingRelease()
        let last = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 3600 else { return }
        check(manual: false)
    }
    func check(manual: Bool) {
        guard installer == nil else { return }
        // A manual request can join an automatic check already in flight.
        if isChecking { manualRequested = manualRequested || manual; return }
        if manual && !canShowSheet { NSSound.beep(); return }
        isChecking = true; manualRequested = manual; stateChanged(true)
        defaults.set(Date(), forKey: lastCheckKey)
        checker.check(installed: installed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let manual = self.manualRequested
                self.isChecking = false; self.manualRequested = false; self.stateChanged(false)
                switch result {
                case .success(.available(let release)):
                    let lastNotice = self.notifiedAt[release.tag] ?? .distantPast
                    if manual || Date().timeIntervalSince(lastNotice) >= 24 * 3600 { self.pendingResult = result }
                case .success(.current):
                    if manual { self.pendingResult = result }
                case .success(.unknownBuild), .failure:
                    if manual { self.pendingResult = result }
                }
                self.presentPendingRelease()
            }
        }
    }
    private var canShowSheet: Bool { installer == nil && window?.isVisible == true && window?.attachedSheet == nil && canPresent() }
    private func presentPendingRelease() {
        guard canShowSheet, let result = pendingResult else { return }
        pendingResult = nil
        switch result {
        case .success(.available(let release)): presentRelease(release)
        case .success(.current): showMessage("No updates found.", "There are no newer published releases of Postino.")
        case .success(.unknownBuild): showMessage("Could not compare versions", "This development build has no release metadata. Rebuild Postino before checking for updates.")
        case .failure(let error): showMessage("Could not check for updates", error.localizedDescription)
        }
    }
    private func showMessage(_ title: String, _ message: String) {
        guard canShowSheet, let window else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    private func presentRelease(_ release: AppRelease) {
        guard canShowSheet, let window else { return }
        notifiedAt[release.tag] = Date()
        let alert = NSAlert()
        alert.messageText = "A newer version of Postino is available."
        alert.informativeText = "\(release.displayName) is ready to download. Postino will restart after updating."
        alert.addButton(withTitle: "Update and restart"); alert.addButton(withTitle: "Remind me later")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { DispatchQueue.main.async { self?.download(release) } }
        }
    }
    private func download(_ release: AppRelease) {
        guard canShowSheet, let window else { return }
        do {
            guard let helper = Bundle.main.url(forResource: "InstallUpdate", withExtension: "sh") else {
                throw UpdateInstallError.message("The update installer is missing. Please reinstall Postino from GitHub.")
            }
            let progress = NSProgressIndicator(); progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
            progress.frame = NSRect(x: 0, y: 0, width: 280, height: 18)
            let alert = NSAlert(); alert.messageText = "Downloading update…"; alert.informativeText = "Postino will verify the download before restarting."
            alert.accessoryView = progress; alert.addButton(withTitle: "Cancel")
            installer = try AppUpdateInstaller(release: release, destination: Bundle.main.bundleURL, helper: helper, progress: { value in
                DispatchQueue.main.async { progress.doubleValue = value }
            }, completion: { [weak self] result in
                DispatchQueue.main.async { self?.downloadFinished(result) }
            })
            isChecking = true; stateChanged(true); downloadSheet = alert
            alert.beginSheetModal(for: window) { [weak self] _ in
                guard let self, self.downloadSheet != nil else { return }
                self.installer?.cancel()
            }
            installer?.start()
        } catch { showMessage("Could not update Postino", error.localizedDescription) }
    }
    private func downloadFinished(_ result: Result<PreparedAppUpdate, Error>) {
        let alert = downloadSheet; downloadSheet = nil
        if let alert, let window { window.endSheet(alert.window) }
        installer = nil
        // Finish unwinding the progress sheet before presenting save confirmation.
        DispatchQueue.main.async {
            self.isChecking = false; self.stateChanged(false)
            switch result {
            case .success(let update): self.restart(update)
            case .failure(let error):
                if (error as? URLError)?.code != .cancelled { self.showMessage("Could not update Postino", error.localizedDescription) }
            }
        }
    }
}
