import Foundation
import CryptoKit

public enum UpdateInstallError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Everything is downloaded and validated while the old app is still running.
/// The helper only replaces it after AppKit approves quitting and saves finish.
public final class PreparedAppUpdate {
    public let directory: URL
    public let stagedApp: URL
    public let destination: URL
    private let helper: URL
    init(directory: URL, stagedApp: URL, destination: URL, helper: URL) {
        self.directory = directory; self.stagedApp = stagedApp; self.destination = destination; self.helper = helper
    }
    public func discard() {
        try? FileManager.default.removeItem(at: stagedApp)
        try? FileManager.default.removeItem(at: directory)
    }
    public func launchHelper(parentPID: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        guard FileManager.default.fileExists(atPath: stagedApp.path),
              !FileManager.default.fileExists(atPath: destination.path + ".postino-update-lock") else {
            throw UpdateInstallError.message("Another update is already in progress, or the staged update is missing.")
        }
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".Postino-backup-\(UUID().uuidString).app")
        let log = directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helper.path, destination.path, stagedApp.path, backup.path, String(parentPID), directory.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
        try process.run()
    }
}

public final class AppUpdateInstaller: NSObject, URLSessionDownloadDelegate {
    private let release: AppRelease
    private let asset: AppRelease.Asset
    private let destination: URL
    private let helper: URL
    private let progress: (Double) -> Void
    private var completion: ((Result<PreparedAppUpdate, Error>) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private let lock = NSLock()
    private var cancelled = false
    public init(release: AppRelease, destination: URL, helper: URL, progress: @escaping (Double) -> Void,
                completion: @escaping (Result<PreparedAppUpdate, Error>) -> Void) throws {
        self.release = release; asset = try release.updateAsset(); self.destination = destination; self.helper = helper
        self.progress = progress; self.completion = completion
    }
    public func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 300
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        task = session.downloadTask(with: asset.url); task?.resume()
    }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock(); task?.cancel() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 200_000_000 { cancel(); return }
        progress(min(1, Double(totalBytesWritten) / Double(asset.size)))
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateInstallError.message("The update could not be downloaded from GitHub. Please try again later.")
            }
            if isCancelled { throw URLError(.cancelled) }
            let prepared = try Self.prepare(archive: location, release: release, destination: destination, helper: helper)
            if isCancelled { prepared.discard(); throw URLError(.cancelled) }
            finish(.success(prepared))
        } catch { finish(.failure(error)) }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
    private func finish(_ result: Result<PreparedAppUpdate, Error>) {
        let callback = completion; completion = nil; callback?(result)
        session?.finishTasksAndInvalidate(); session = nil; task = nil
    }
    public static func prepare(archive: URL, release: AppRelease, destination: URL, helper: URL) throws -> PreparedAppUpdate {
        let fm = FileManager.default, asset = try release.updateAsset()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        let parent = destination.deletingLastPathComponent()
        guard destination.pathExtension == "app", Bundle(url: destination)?.bundleIdentifier == "app.postauomo.http",
              fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: destination.path),
              fm.fileExists(atPath: helper.path) else {
            throw UpdateInstallError.message("Postino cannot update from its current location. Move it to a writable Applications folder and try again.")
        }
        let attributes = try fm.attributesOfItem(atPath: archive.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == asset.size else {
            throw UpdateInstallError.message("The update download is incomplete. Please try again.")
        }
        let handle = try FileHandle(forReadingFrom: archive); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        let digest = "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == asset.digest?.lowercased() else {
            throw UpdateInstallError.message("The downloaded update did not match GitHub's checksum. Nothing was installed.")
        }
        let directory = fm.temporaryDirectory.appendingPathComponent("PostinoUpdate-\(UUID().uuidString)", isDirectory: true)
        let staged = parent.appendingPathComponent(".Postino-incoming-\(UUID().uuidString).app", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
            let entries = try run("/usr/bin/zipinfo", ["-1", archive.path])
            guard !entries.isEmpty, entries.components(separatedBy: .newlines).allSatisfy({ entry in
                !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..")
            }) else { throw UpdateInstallError.message("The update archive has an invalid structure.") }
            _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            let app = extracted.appendingPathComponent("Postino.app")
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "app.postauomo.http",
                  bundle.infoDictionary?["PostinoReleaseTag"] as? String == release.tag,
                  let executable = bundle.executableURL, fm.isExecutableFile(atPath: executable.path) else {
                throw UpdateInstallError.message("The download does not contain the expected Postino release.")
            }
            if let minimum = bundle.infoDictionary?["LSMinimumSystemVersion"] as? String {
                let parts = minimum.split(separator: ".").compactMap { Int($0) }
                guard !parts.isEmpty, parts.count <= 3,
                      ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0, patchVersion: parts.count > 2 ? parts[2] : 0)) else {
                    throw UpdateInstallError.message("This update requires macOS \(minimum) or later.")
                }
            }
            // Symlinks must stay inside the extracted app bundle.
            let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey])
            while let file = enumerator?.nextObject() as? URL {
                if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
                   !file.resolvingSymlinksInPath().path.hasPrefix(app.path + "/") {
                    throw UpdateInstallError.message("The update contains an invalid symbolic link.")
                }
            }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            _ = try run("/usr/bin/lipo", [executable.path, "-verify_arch", architecture])
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            let copiedHelper = directory.appendingPathComponent("install-update.sh")
            try fm.copyItem(at: helper, to: copiedHelper)
            _ = try run("/usr/bin/ditto", [app.path, staged.path])
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            return PreparedAppUpdate(directory: directory, stagedApp: staged, destination: destination, helper: copiedHelper)
        } catch {
            try? fm.removeItem(at: staged); try? fm.removeItem(at: directory)
            throw error
        }
    }
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateInstallError.message("Postino could not validate or stage the update (\(URL(fileURLWithPath: executable).lastPathComponent)). Nothing was installed.\n\(detail)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
