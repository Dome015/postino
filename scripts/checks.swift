import Foundation
import RelayCore
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) }; checks += 1; print("PASS \(message)") }
func mustFail(_ name: String, _ action: () throws -> Void) { do { try action(); fatalError("Expected failure: \(name)") } catch { checks += 1; print("PASS \(name)") } }
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Relay-checks-" + UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let collectionJSON: JSON = ["info": ["name": "Round trip", "description": "Keep me"], "auth": ["type": "bearer", "bearer": [["key": "token", "value": "{{token}}"]]], "variable": [["key": "host", "value": "http://127.0.0.1:18765"]], "event": [["listen": "prerequest", "script": ["exec": ["console.log('preserved')"]]]], "item": [["name": "Nested", "item": [["name": "Echo", "response": [["name": "Saved example"]], "request": ["method": "GET", "url": "{{host}}/echo", "header": [["key": "X-Disabled", "value": "no", "disabled": true]]]]]]]]
let collection = try Collection(json: collectionJSON); let r = collection.allRequests[0]; r.params = [Pair("q", "café & +")]
let roundtrip = try Collection(json: Postman.read(Postman.encode(collection.exported())))
check(roundtrip.nodes[0].children.count == 1, "Nested collection import/export")
check((roundtrip.original["event"] as? [JSON])?.count == 1, "Preserved scripts")
check((roundtrip.allRequests[0].original["response"] as? [JSON])?.count == 1, "Preserved examples")
let emptyDraft = RequestDraft(RequestItem(), saved: false)
check(!emptyDraft.isDirty, "Untouched empty tab does not prompt to save")
emptyDraft.request.method = "POST"; check(emptyDraft.isDirty, "Editing an empty tab marks it dirty")
let draft = RequestDraft(r)
check(!draft.isDirty, "Opening a request preserves a clean draft")
draft.request.name = "Edited"; draft.request.body = "large changed body"; draft.request.params[0].value = "changed"
check(draft.isDirty && r.name == "Echo" && r.body.isEmpty && r.params[0].value == "café & +", "Draft edits do not mutate saved collection")
let savedDraft = draft.save()
check(!draft.isDirty && savedDraft.name == "Edited" && savedDraft !== draft.request, "Save creates an independent snapshot and clears dirty state")
draft.request.headers.append(Pair("X-Draft", "yes")); check(draft.isDirty && savedDraft.headers.count == 1, "Later edits leave saved headers intact")
draft.request.headers.removeLast(); check(!draft.isDirty, "Reverting an edit clears dirty state")
check(savedDraft.id == r.id && savedDraft.inheritedAuth != nil && (savedDraft.original["response"] as? [JSON])?.count == 1, "Draft save preserves identity, inherited auth and Postman metadata")
let built = try RequestBuilder.build(r, environment: ["token": "secret"])
check(built.0.value(forHTTPHeaderField: "Authorization") == "Bearer secret", "Inherited bearer auth")
check(built.0.value(forHTTPHeaderField: "X-Disabled") == nil, "Disabled header excluded")
check(URLComponents(url: built.0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "café & +", "Query percent encoding")
let environment = try Environment(json: ["name": "Local", "values": [["key": "x", "value": "yes", "enabled": true, "type": "secret"], ["key": "off", "value": "no", "enabled": false]]])
check(environment.variables["off"] == nil, "Disabled environment values")
let roundtripEnv = try Environment(json: Postman.read(Postman.encode(environment.exported)))
check(roundtripEnv.values[0].extra["type"] as? String == "secret", "Environment round trip preserves secret metadata")
mustFail("Undefined variables rejected") { _ = try RequestBuilder.resolve("{{missing}}", variables: [:]) }
mustFail("Circular variables rejected") { _ = try RequestBuilder.resolve("{{a}}", variables: ["a": "{{b}}", "b": "{{a}}"] ) }
mustFail("Invalid collection rejected") { _ = try Collection(json: [:]) }
mustFail("Non HTTP URL rejected") { _ = try RequestBuilder.build(RequestItem(item: ["request": ["url": "file:///etc/passwd"]])) }
let raw = dir.appendingPathComponent("raw.json"), formatted = dir.appendingPathComponent("pretty.json")
let json = "{\"number\":123456789012345678901234567890,\"escaped\":\"say \\\"hi\\\"\",\"items\":[{},[],true,null],\"text\":\"" + String(repeating: "a", count: ResponseFile.pageSize - 115) + "🦊café\"}"
try Data(json.utf8).write(to: raw); try ResponseFile.pretty(raw, destination: formatted)
let pretty = try String(contentsOf: formatted, encoding: .utf8)
_ = try JSONSerialization.jsonObject(with: Data(pretty.utf8)); check(pretty.contains("123456789012345678901234567890"), "JSON formatting preserves exact large integers")
var joined = ""; for i in 0..<Int((ResponseFile.size(formatted) + Int64(ResponseFile.pageSize) - 1) / Int64(ResponseFile.pageSize)) { joined += try ResponseFile.page(formatted, index: i) }
check(joined == pretty, "UTF-8 page boundaries preserve every character")
let boundary = dir.appendingPathComponent("boundary"); try Data((String(repeating: "x", count: 262140) + "needle-at-boundary").utf8).write(to: boundary)
check((try? ResponseFile.search(boundary, term: "needle-at-boundary")) == 262140, "Full file search across chunk boundary")
let multipart = RequestItem(item: ["request": ["method": "POST", "url": "http://127.0.0.1:18765/echo", "body": ["mode": "formdata", "formdata": [["key": "message", "value": "hello", "type": "text"], ["key": "document", "type": "file", "src": raw.path]]]]])
let multi = try RequestBuilder.build(multipart); let multiFile = multi.1!; let multiText = try String(contentsOf: multiFile, encoding: .utf8); check(multiText.contains("name=\"message\"") && multiText.contains("hello") && multiText.contains("filename=\"raw.json\""), "Multipart streams text and file parts")
func run(_ request: URLRequest, file: URL? = nil, cancel: Bool = false) throws -> Result<HTTPResult, Error> {
    var result: Result<HTTPResult, Error>?
    let transfer = try HTTPTransfer(directory: dir, completion: { result = $0 }, progress: { _ in }); transfer.start(request, file: file)
    if cancel { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { transfer.cancel() } }
    let deadline = Date().addingTimeInterval(45)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    guard let result else { fatalError("HTTP request timed out") }; return result
}
let echo = try run(built.0).get(); let echoJSON = try Postman.read(Data(contentsOf: echo.file))
check(echo.status == 200 && ResponseFile.size(echo.file) == echo.bytes, "Real GET response saved directly to disk")
check((echoJSON["headers"] as? JSON)?["Authorization"] as? String == "Bearer secret", "Server received authorization")
let post = try run(multi.0, file: multi.1).get(); check(post.status == 201, "Multipart file upload executes")
check(!FileManager.default.fileExists(atPath: multiFile.path), "Temporary upload cleaned up")
let slow = try run(URLRequest(url: URL(string: "http://127.0.0.1:18765/slow")!), cancel: true)
if case .failure(let error) = slow { check((error as NSError).code == NSURLErrorCancelled, "Cancellation stops in-flight request") } else { fatalError("Cancellation failed") }
let large = try run(URLRequest(url: URL(string: "http://127.0.0.1:18765/large")!)).get()
check(large.bytes > 100_000_000, "100 MB+ response streamed to disk")
let largePretty = dir.appendingPathComponent("large.pretty.json"); let started = Date(); try ResponseFile.pretty(large.file, destination: largePretty)
let lastPage = Int(ResponseFile.size(largePretty) / Int64(ResponseFile.pageSize)); let last = try ResponseFile.page(largePretty, index: lastPage)
check(last.contains("]"), "Last page of large formatted response readable")
check((try? ResponseFile.search(large.file, term: "Studio headphones", from: UInt64(large.bytes - 2000))) != nil, "Search finds content near end of 100 MB response")
print("\(checks) checks passed. Download \(large.bytes) bytes in \(String(format: "%.2f", large.duration))s. Disk JSON formatting \(String(format: "%.2f", Date().timeIntervalSince(started)))s.")
