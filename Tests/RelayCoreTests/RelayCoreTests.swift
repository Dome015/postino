import XCTest
@testable import RelayCore
final class RelayCoreTests: XCTestCase {
    func testPostmanRoundTripPreservesFoldersScriptsExamplesAndSecrets() throws {
        let j: JSON = ["info": ["name": "Test", "description": "Keep me"], "auth": ["type": "bearer", "bearer": [["key": "token", "value": "{{token}}"]]], "variable": [["key": "base", "value": "http://localhost"]], "event": [["listen": "prerequest", "script": ["exec": ["pm.environment.set('a', 'b')"]]]], "item": [["name": "Folder", "item": [["name": "Read", "response": [["name": "Example"]], "request": ["method": "GET", "url": ["raw": "{{base}}/users?limit=1", "query": [["key": "limit", "value": "1"]]], "header": [["key": "X-Test", "value": "disabled", "disabled": true]]]]]]]]
        let collection = try Collection(json: j); let request = try XCTUnwrap(collection.allRequests.first)
        request.params[0].value = "25"; let exported = collection.exported(); let roundTrip = try Collection(json: Postman.read(Postman.encode(exported)))
        XCTAssertEqual(roundTrip.allRequests.first?.params[0].value, "25"); XCTAssertEqual(roundTrip.allRequests.first?.headers[0].enabled, false); XCTAssertEqual((exported["event"] as? [JSON])?.count, 1); XCTAssertEqual((roundTrip.allRequests.first?.original["response"] as? [JSON])?.count, 1)
        let built = try RequestBuilder.build(request, environment: ["token": "secret"])
        XCTAssertEqual(built.0.url?.absoluteString, "http://localhost/users?limit=25"); XCTAssertEqual(built.0.value(forHTTPHeaderField: "Authorization"), "Bearer secret"); XCTAssertNil(built.0.value(forHTTPHeaderField: "X-Test"))
    }
    func testEnvironmentRoundTripAndDisabledValues() throws {
        let env = try Environment(json: ["name": "Local", "values": [["key": "a", "value": "1", "enabled": true, "type": "secret"], ["key": "b", "value": "2", "enabled": false]], "id": "original"])
        XCTAssertNil(env.variables["b"]); let parsed = try Environment(json: Postman.read(Postman.encode(env.exported))); XCTAssertEqual(parsed.values[0].extra["type"] as? String, "secret"); XCTAssertEqual(parsed.original["id"] as? String, "original")
    }
    func testVariablesEncodingAuthAndRawBody() throws {
        let r = RequestItem(item: ["name": "Write", "request": ["method": "POST", "url": "{{host}}/echo", "body": ["mode": "raw", "raw": "{\"name\":\"{{name}}\"}"], "auth": ["type": "basic", "basic": [["key": "username", "value": "u"], ["key": "password", "value": "p"]]]]])
        r.params = [Pair("q", "a&b + café")]; let request = try RequestBuilder.build(r, environment: ["host": "http://localhost", "name": "Test"]).0
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b + café"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dTpw"); XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "{\"name\":\"Test\"}"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testUndefinedAndCircularVariablesFail() { XCTAssertThrowsError(try RequestBuilder.resolve("{{missing}}", variables: [:])); XCTAssertThrowsError(try RequestBuilder.resolve("{{a}}", variables: ["a": "{{b}}", "b": "{{a}}"])); XCTAssertEqual(try RequestBuilder.resolve("{{a}}", variables: ["a": "{{b}}", "b": "yes"]), "yes") }
    func testMalformedImportsAndURLs() { XCTAssertThrowsError(try Collection(json: [:])); XCTAssertThrowsError(try Environment(json: [:])); XCTAssertThrowsError(try RequestBuilder.build(RequestItem(item: ["request": ["url": "file:///etc/passwd"]]))) }
    func testDiskFormatterPrecisionSearchAndUTF8Paging() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("raw.json"), pretty = directory.appendingPathComponent("pretty.json")
        let string = "{\"number\":123456789012345678901234567890,\"escaped\":\"say \\\"hi\\\"\",\"items\":[{},[],true,null],\"text\":\"" + String(repeating: "a", count: ResponseFile.pageSize - 115) + "🦊café\"}"
        try Data(string.utf8).write(to: source); try ResponseFile.pretty(source, destination: pretty)
        let formatted = try String(contentsOf: pretty); XCTAssertTrue(formatted.contains("123456789012345678901234567890")); XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(formatted.utf8)))
        var pages = ""; for i in 0..<Int((ResponseFile.size(pretty) + Int64(ResponseFile.pageSize) - 1) / Int64(ResponseFile.pageSize)) { pages += try ResponseFile.page(pretty, index: i) }; XCTAssertEqual(pages, formatted)
        XCTAssertNotNil(try ResponseFile.search(pretty, term: "🦊café")); XCTAssertNil(try ResponseFile.search(pretty, term: "no-match"))
    }
    func testStreamingSearchAcrossChunkBoundary() throws { let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: file) }; try Data((String(repeating: "x", count: 262140) + "needle-at-boundary").utf8).write(to: file); XCTAssertEqual(try ResponseFile.search(file, term: "needle-at-boundary"), 262140) }
    func testLiveHTTPDownload() throws {
        guard ProcessInfo.processInfo.environment["RELAY_INTEGRATION"] == "1" else { throw XCTSkip("Start fixture_server.py and set RELAY_INTEGRATION=1") }
        let done = expectation(description: "request"); let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
        let request = URLRequest(url: URL(string: "http://127.0.0.1:18765/products")!)
        let transfer = try HTTPTransfer(directory: dir, completion: { result in do { let response = try result.get(); XCTAssertEqual(response.status, 200); XCTAssertGreaterThan(response.bytes, 100); XCTAssertEqual(ResponseFile.size(response.file), response.bytes); XCTAssertNoThrow(try Postman.read(Data(contentsOf: response.file))) } catch { XCTFail(error.localizedDescription) }; done.fulfill() }, progress: { _ in }); transfer.start(request); wait(for: [done], timeout: 10)
    }
}
