import Foundation
import RelayCore
final class Workspace {
    var collections: [Collection] = []; var environments: [Environment] = []; var history: [JSON] = []; var selectedEnvironment = -1
    let directory: URL; let responses: URL
    private let queue = DispatchQueue(label: "relay.persistence", qos: .utility); private var pending: DispatchWorkItem?
    init() {
        let demo = CommandLine.arguments.contains("--demo")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newStorage = support.appendingPathComponent("Postauomo")
        let legacyStorage = support.appendingPathComponent("Relay")
        var storage = newStorage
        if !demo && !FileManager.default.fileExists(atPath: newStorage.path) && FileManager.default.fileExists(atPath: legacyStorage.path) {
            do { try FileManager.default.copyItem(at: legacyStorage, to: newStorage) }
            catch { storage = legacyStorage; NSLog("Postino is using the existing workspace: %@", error.localizedDescription) }
        }
        directory = demo ? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".demo") : storage
        responses = directory.appendingPathComponent("Responses")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? Data(contentsOf: directory.appendingPathComponent("workspace.json")), let j = try? Postman.read(data) {
            collections = (j["collections"] as? [JSON] ?? []).compactMap { try? Collection(json: $0) }; environments = (j["environments"] as? [JSON] ?? []).compactMap { try? Environment(json: $0) }; history = j["history"] as? [JSON] ?? []; selectedEnvironment = j["selectedEnvironment"] as? Int ?? -1
        }
        if collections.isEmpty {
            let host = demo ? "http://127.0.0.1:18765" : "https://postman-echo.com"
            let requests: [JSON] = demo ? [
                ["name": "List products", "request": ["method": "GET", "url": "{{base_url}}/products?limit=50", "header": [["key": "Accept", "value": "application/json"]]]],
                ["name": "Get product", "request": ["method": "GET", "url": "{{base_url}}/products/1"]],
                ["name": "Create product", "request": ["method": "POST", "url": "{{base_url}}/products", "body": ["mode": "raw", "raw": "{\n  \"name\": \"Studio headphones\",\n  \"price\": 129.00\n}", "options": ["raw": ["language": "json"]]]]],
                ["name": "Large JSON · 100 MB", "request": ["method": "GET", "url": "{{base_url}}/large"]]
            ] : [
                ["name": "Echo a GET request", "request": ["method": "GET", "url": "{{base_url}}/get?hello=world", "header": [["key": "Accept", "value": "application/json"]]]],
                ["name": "Send JSON", "request": ["method": "POST", "url": "{{base_url}}/post", "body": ["mode": "raw", "raw": "{\n  \"message\": \"Hello from Postino\"\n}", "options": ["raw": ["language": "json"]]]]],
                ["name": "Inspect headers", "request": ["method": "GET", "url": "{{base_url}}/headers"]]
            ]
            let j: JSON = ["info": ["name": demo ? "Commerce API" : "Getting started", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"], "item": [["name": demo ? "Products" : "Example requests", "item": requests]]]
            collections = [try! Collection(json: j)]; environments = [try! Environment(json: ["name": demo ? "Local development" : "Postman Echo", "values": [["key": "base_url", "value": host, "enabled": true]]])]; selectedEnvironment = 0
        }
        if !environments.indices.contains(selectedEnvironment) { selectedEnvironment = -1 }
        // Responses are session-scoped; never grow the response cache across launches.
        try? FileManager.default.removeItem(at: responses); try? FileManager.default.createDirectory(at: responses, withIntermediateDirectories: true)
    }
    func save(now: Bool = false) {
        pending?.cancel()
        let snapshot: JSON = ["collections": collections.map { $0.exported(internalIDs: true) }, "environments": environments.map(\.exported), "history": Array(history.prefix(100)), "selectedEnvironment": selectedEnvironment]
        let url = directory.appendingPathComponent("workspace.json")
        let work = DispatchWorkItem { do { let data = try Postman.encode(snapshot); try data.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) } catch { NSLog("Postino workspace save failed: %@", error.localizedDescription) } }
        pending = work; if now { queue.sync(execute: work) } else { queue.asyncAfter(deadline: .now() + 0.4, execute: work) }
    }
}
