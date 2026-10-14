import Foundation
import CryptoKit
import RelayCore

final class ReleaseProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var failure: Error?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url == AppUpdateChecker.endpoint)
        precondition(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil, "Public checks need no credentials")
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct UpdateChecks {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "") throws {
        let result = try condition(); precondition(result, message)
    }
    static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
    static func main() throws {
        let fm = FileManager.default
        let tag = "postino-200-1"
        var json: [String: Any] = ["tag_name": tag, "name": "A new release", "html_url": "https://github.com/Dome015/postino/releases/tag/\(tag)", "published_at": "2026-10-13T12:00:00Z", "draft": false, "prerelease": false, "assets": []]
        func release() throws -> AppRelease { try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: json)) }
        let older = InstalledRelease(info: ["PostinoBuildDate": "2026-10-12T10:00:00Z"])
        let same = InstalledRelease(tag: tag, builtAt: older.builtAt)
        let newer = InstalledRelease(info: ["PostinoBuildDate": "2026-10-14T10:00:00.123Z"])
        try expect(try AppUpdateChecker.evaluate(release(), installed: older) == .available(release()))
        try expect(try AppUpdateChecker.evaluate(release(), installed: same) == .current, "Publishing after a build must not offer that build itself")
        try expect(try AppUpdateChecker.evaluate(release(), installed: newer) == .current, "Do not downgrade newer local builds")
        try expect(try AppUpdateChecker.evaluate(release(), installed: InstalledRelease(tag: nil, builtAt: nil)) == .unknownBuild(release()))
        func rejectsRelease(_ field: String, _ value: Any) throws {
            let previous = json[field]; json[field] = value
            defer { json[field] = previous }
            do { _ = try AppUpdateChecker.evaluate(release(), installed: older); preconditionFailure("Invalid release accepted: \(field)") }
            catch is AppUpdateError {}
        }
        try rejectsRelease("draft", true); try rejectsRelease("prerelease", true)
        try rejectsRelease("published_at", "invalid"); try rejectsRelease("html_url", "https://example.com/update")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: config), checker = AppUpdateChecker(session: session)
        func check() -> Result<AppUpdateResult, Error> {
            let done = DispatchSemaphore(value: 0); var result: Result<AppUpdateResult, Error>!
            checker.check(installed: older) { result = $0; done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success, "Checks must complete without blocking the main thread")
            return result
        }
        ReleaseProtocol.body = try JSONSerialization.data(withJSONObject: json)
        try expect(try check().get() == .available(release()))
        for status in [403, 404, 429, 500] {
            ReleaseProtocol.status = status
            guard case .failure(let error) = check(), let error = error as? AppUpdateError else { preconditionFailure("HTTP \(status) must fail") }
            if status == 404 { guard case .noRelease = error else { preconditionFailure() } }
        }
        ReleaseProtocol.status = 200; ReleaseProtocol.body = Data("not json".utf8)
        guard case .failure = check() else { preconditionFailure("Malformed responses must fail") }
        ReleaseProtocol.failure = URLError(.notConnectedToInternet)
        guard case .failure = check() else { preconditionFailure("Offline checks must fail cleanly") }
        session.invalidateAndCancel()

        // Real ZIPs, signatures and filesystem operations, using only disposable app copies.
        let root = URL(fileURLWithPath: "build/update-fixtures-\(UUID().uuidString)").standardizedFileURL
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let destination = root.appendingPathComponent("Postino's $ test.app")
        let source = root.appendingPathComponent("Postino.app")
        try fm.copyItem(at: URL(fileURLWithPath: "build/Release/Postino.app"), to: destination)
        try fm.copyItem(at: destination, to: source)
        let plist = source.appendingPathComponent("Contents/Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        info["PostinoReleaseTag"] = tag
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        try expect(try run("/usr/bin/codesign", ["--force", "--sign", "-", source.path]) == 0)
        let archive = root.appendingPathComponent("release.zip")
        try expect(try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path]) == 0)
        let data = try Data(contentsOf: archive)
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        json["assets"] = [["name": "Postino-200-1.zip", "browser_download_url": "https://github.com/Dome015/postino/releases/download/\(tag)/Postino-200-1.zip", "size": data.count, "digest": digest]]
        let validRelease = try release()
        let helper = URL(fileURLWithPath: "Resources/InstallUpdate.sh").standardizedFileURL
        let prepared = try AppUpdateInstaller.prepare(archive: archive, release: validRelease, destination: destination, helper: helper)
        precondition(fm.fileExists(atPath: prepared.stagedApp.path), "Validated update stages beside the running app")
        precondition(Bundle(url: destination)?.infoDictionary?["PostinoReleaseTag"] as? String != tag, "Preparing must preserve the running app")
        prepared.discard(); precondition(!fm.fileExists(atPath: prepared.stagedApp.path))
        var broken = data; broken[broken.startIndex] ^= 1
        try broken.write(to: archive)
        do { _ = try AppUpdateInstaller.prepare(archive: archive, release: validRelease, destination: destination, helper: helper); preconditionFailure("Checksum mismatch accepted") }
        catch is UpdateInstallError {}
        precondition(fm.fileExists(atPath: destination.path), "A failed validation must leave the installed app intact")
        try data.write(to: archive)
        json["tag_name"] = "postino-201-1"
        json["assets"] = [["name": "Postino-201-1.zip", "browser_download_url": "https://github.com/Dome015/postino/releases/download/postino-201-1/Postino-201-1.zip", "size": data.count, "digest": digest]]
        do { _ = try AppUpdateInstaller.prepare(archive: archive, release: release(), destination: destination, helper: helper); preconditionFailure("Wrong bundle release accepted") }
        catch is UpdateInstallError {}

        // Stub only the final GUI launch/alert commands in a test copy of the
        // helper. Exercise the actual replacement and rollback without launching
        // a normal workspace or modifying the real app.
        let original = try String(contentsOf: helper, encoding: .utf8)
        let testHelper = root.appendingPathComponent("test-helper.sh")
        for launchSucceeds in [true, false] {
            let target = root.appendingPathComponent("Target's $ name.app")
            let incoming = root.appendingPathComponent(".Postino-incoming-test.app")
            let backup = root.appendingPathComponent(".Postino-backup-test.app")
            let work = root.appendingPathComponent("PostinoUpdate-test")
            for directory in [target, incoming, work] { try fm.createDirectory(at: directory, withIntermediateDirectories: false) }
            try Data("old".utf8).write(to: target.appendingPathComponent("identity"))
            try Data("new".utf8).write(to: incoming.appendingPathComponent("identity"))
            let command = launchSucceeds ? "/usr/bin/true" : "/usr/bin/false"
            try original.replacingOccurrences(of: "/usr/bin/open", with: command).replacingOccurrences(of: "/usr/bin/osascript", with: "/usr/bin/true").write(to: testHelper, atomically: true, encoding: .utf8)
            let status = try run("/bin/zsh", [testHelper.path, target.path, incoming.path, backup.path, "99999999", work.path])
            precondition((status == 0) == launchSucceeds)
            try expect(try String(contentsOf: target.appendingPathComponent("identity"), encoding: .utf8) == (launchSucceeds ? "new" : "old"), "Install succeeds or restores the previous app when relaunch fails")
            precondition(!fm.fileExists(atPath: backup.path) && !fm.fileExists(atPath: incoming.path) && !fm.fileExists(atPath: work.path))
            try fm.removeItem(at: target)
        }
        print("Passed release identity/date comparison, public API/offline/error handling, checksum and bundle validation, staging, helper replacement and rollback checks")
    }
}
