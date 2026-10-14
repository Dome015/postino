import Foundation
import RelayCore

@main struct CurlChecks {
    static func main() throws {
        let base = "http://127.0.0.1:\(CommandLine.arguments[1])"
        let fm = FileManager.default, root = URL(fileURLWithPath: "build/curl-check-files-\(UUID().uuidString)").standardizedFileURL
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let marker = root.appendingPathComponent("shell-injection")
        let hostile = "@literal 'quoted' \"double\" $(touch \(marker.path)) `touch \(marker.path)`; $HOME\nsecond line 📨"
        func item(_ method: String = "POST") -> RequestItem {
            RequestItem(item: ["name": "Export", "request": ["method": method, "url": "{{base}}/echo"]], variables: ["base": base])
        }
        func execute(_ item: RequestItem, environment: [String: String] = [:]) throws -> JSON {
            let command = try CurlExporter.command(item, environment: environment)
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-c", command]
            process.standardOutput = output; process.standardError = errors
            try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            precondition(process.terminationStatus == 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            if item.method == "HEAD" { return [:] }
            return try JSONSerialization.jsonObject(with: data) as! JSON
        }
        let get = item("GET"); get.variables["base"] = "https://invalid.example"
        get.params = [Pair("q", "a b&[]{}'"), Pair("off", "ignored", enabled: false)]
        get.headers = [Pair("X-Literal", "'quoted' $HOME $(touch \(marker.path))"), Pair("X-Empty", ""), Pair("X-Off", "ignored", enabled: false)]
        get.inheritedAuth = ["type": "bearer", "bearer": [["key": "token", "value": "{{token}}"]]]
        let response = try execute(get, environment: ["base": base, "token": "demo-token"])
        let headers = response["headers"] as! [String: String], query = response["query"] as! [String: [String]]
        precondition(query == ["q": ["a b&[]{}'"]] && headers["Authorization"] == "Bearer demo-token")
        precondition(headers["X-Literal"] == get.headers[0].value && headers["X-Empty"] == "" && headers["X-Off"] == nil)
        let raw = item("PATCH"); raw.body = hostile
        let rawResponse = try execute(raw)
        precondition(rawResponse["method"] as? String == "PATCH" && rawResponse["body"] as? String == hostile)
        let encoded = item(); encoded.bodyMode = "urlencoded"; encoded.form = [Pair("literal", "a+b &c"), Pair("off", "no", enabled: false)]
        let encodedResponse = try execute(encoded)
        precondition(encodedResponse["body"] as? String == "literal=a%2Bb%20%26c")
        let file = root.appendingPathComponent("file's \"comma,;\\ name.txt")
        let fileBody = "file bytes\0\n📨"; try fileBody.write(to: file, atomically: true, encoding: .utf8)
        let binary = item("PUT"); binary.bodyMode = "file"; binary.body = file.path
        let binaryResponse = try execute(binary)
        precondition(binaryResponse["body"] as? String == fileBody)
        let multipart = item(); multipart.bodyMode = "formdata"
        multipart.headers = [Pair("Content-Type", "invalid/type")]
        multipart.form = [Pair("text", hostile), Pair("upload", "", extra: ["type": "file", "src": file.path, "contentType": "application/json"]), Pair("off", "no", enabled: false)]
        let multipartResponse = try execute(multipart), parts = multipartResponse["parts"] as! [JSON]
        precondition(parts.count == 2 && parts[0]["body"] as? String == hostile)
        precondition(parts[1]["filename"] as? String == file.lastPathComponent && parts[1]["body"] as? String == fileBody && parts[1]["type"] as? String == "application/json")
        multipart.form[1].extra["contentType"] = "text/plain; charset=utf-8"
        let typedParts = try execute(multipart)["parts"] as! [JSON]
        precondition(typedParts[1]["type"] as? String == "text/plain" && typedParts[1]["charset"] as? String == "utf-8")
        multipart.form = []
        let emptyMultipart = try execute(multipart)
        precondition((emptyMultipart["parts"] as? [JSON])?.isEmpty == true && (emptyMultipart["body"] as? String)?.hasSuffix("--\r\n") == true)
        _ = try execute(item("HEAD"))
        precondition(!fm.fileExists(atPath: marker.path), "Shell quoting must prevent execution of request content")
        for invalid in ["{{missing}}", "null\0byte"] {
            let request = item(); request.body = invalid
            do { _ = try CurlExporter.command(request); preconditionFailure("Invalid content must fail clearly") }
            catch is RelayError {}
        }
        print("Passed executable cURL exports for URL/query encoding, environments, inherited auth, headers, shell quoting, raw/form/binary/multipart bodies and HEAD")
    }
}
