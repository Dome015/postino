import Foundation

public enum RequestBuilder {
    public static func resolve(_ text: String, variables: [String: String]) throws -> String {
        var result = text
        let regex = try NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
        for _ in 0..<12 {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)); if matches.isEmpty { return result }
            var changed = false
            for m in matches.reversed() { guard let range = Range(m.range, in: result), let kr = Range(m.range(at: 1), in: result) else { continue }; let key = String(result[kr]); guard let value = variables[key] else { throw RelayError.message("Variable {{\(key)}} is undefined. Select an environment or add its value.") }; result.replaceSubrange(range, with: value); changed = true }
            if !changed { break }
        }
        throw RelayError.message("Variables contain a circular reference.")
    }
    public static func build(_ item: RequestItem, environment: [String: String] = [:], timeout: TimeInterval = 120) throws -> (URLRequest, URL?) {
        let vars = item.variables.merging(environment) { _, new in new }
        func resolve(_ s: String) throws -> String { try Self.resolve(s, variables: vars) }
        let raw = try resolve(item.url.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? item.url)
        guard var components = URLComponents(string: raw), ["https", "http"].contains(components.scheme?.lowercased() ?? ""), components.host != nil else { throw RelayError.message("Enter a valid http:// or https:// URL.") }
        let pairs = try item.params.filter { $0.enabled && !$0.key.isEmpty }.map { URLQueryItem(name: try resolve($0.key), value: try resolve($0.value)) }; if !pairs.isEmpty { components.queryItems = pairs }
        guard let url = components.url else { throw RelayError.message("The URL could not be encoded.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout); request.httpMethod = item.method
        for h in item.headers where h.enabled && !h.key.isEmpty { let key = try resolve(h.key), value = try resolve(h.value); guard !key.contains(where: { $0.isNewline }), !value.contains(where: { $0.isNewline }) else { throw RelayError.message("Header names and values cannot contain newlines.") }; request.setValue(value, forHTTPHeaderField: key) }
        let auth = item.auth ?? item.inheritedAuth ?? [:]; let type = auth["type"] as? String ?? "noauth"
        let attrs = (auth[type] as? [JSON] ?? []).map(Pair.init); var av: [String: String] = [:]; for p in attrs { av[p.key] = try resolve(p.value) }
        switch type {
        case "noauth": break
        case "bearer": request.setValue("Bearer \(av["token"] ?? "")", forHTTPHeaderField: "Authorization")
        case "basic": let value = "\(av["username"] ?? ""):\(av["password"] ?? "")"; request.setValue("Basic " + Data(value.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        case "apikey": if av["in"] == "query" { var qi = components.queryItems ?? []; qi.append(URLQueryItem(name: av["key"] ?? "", value: av["value"] ?? "")); components.queryItems = qi; request.url = components.url } else { request.setValue(av["value"] ?? "", forHTTPHeaderField: av["key"] ?? "X-API-Key") }
        default: throw RelayError.message("Imported \(type) authentication is preserved, but is not executed. Choose Bearer, Basic, API key, or set an Authorization header.")
        }
        var bodyFile: URL?
        if item.bodyMode == "raw", !item.body.isEmpty { request.httpBody = Data(try resolve(item.body).utf8); if request.value(forHTTPHeaderField: "Content-Type") == nil { let options = ((item.original["request"] as? JSON)?["body"] as? JSON)?["options"] as? JSON; let language = (options?["raw"] as? JSON)?["language"] as? String; request.setValue(language == "json" || item.body.trimmingCharacters(in: .whitespacesAndNewlines).first.map({ $0 == "{" || $0 == "[" }) == true ? "application/json" : "text/plain", forHTTPHeaderField: "Content-Type") } }
        else if item.bodyMode == "urlencoded" { var c = URLComponents(); c.queryItems = try item.form.filter { $0.enabled && !$0.key.isEmpty }.map { URLQueryItem(name: try resolve($0.key), value: try resolve($0.value)) }; request.httpBody = Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        else if item.bodyMode == "file", !item.body.isEmpty { bodyFile = URL(fileURLWithPath: try resolve(item.body)); guard FileManager.default.isReadableFile(atPath: bodyFile!.path) else { throw RelayError.message("The body file cannot be read. Choose a local file.") } }
        else if item.bodyMode == "formdata" {
            let boundary = "Relay-" + UUID().uuidString
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Relay-upload-" + UUID().uuidString)
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw RelayError.message("Cannot create multipart upload.") }
            let out = try FileHandle(forWritingTo: temporary)
            func write(_ s: String) throws { try out.write(contentsOf: Data(s.utf8)) }
            func quoted(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "") }
            do {
                for pair in item.form where pair.enabled && !pair.key.isEmpty {
                    let key = try resolve(pair.key)
                    try write("--\(boundary)\r\n")
                    if pair.extra["type"] as? String == "file" {
                        let path = !pair.value.isEmpty ? pair.value : (pair.extra["src"] as? String ?? (pair.extra["src"] as? [String])?.first ?? "")
                        let file = URL(fileURLWithPath: try resolve(path))
                        let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
                        try write("Content-Disposition: form-data; name=\"\(quoted(key))\"; filename=\"\(quoted(file.lastPathComponent))\"\r\nContent-Type: \(pair.extra["contentType"] as? String ?? "application/octet-stream")\r\n\r\n")
                        try ResponseFile.copy(from: input, to: out)
                    } else { try write("Content-Disposition: form-data; name=\"\(quoted(key))\"\r\n\r\n\(try resolve(pair.value))") }
                    try write("\r\n")
                }
                try write("--\(boundary)--\r\n"); try out.close(); bodyFile = temporary
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            } catch { try? out.close(); try? FileManager.default.removeItem(at: temporary); throw error }
        }
        else if !["raw", "urlencoded", "file"].contains(item.bodyMode) { throw RelayError.message("Body mode \(item.bodyMode) is preserved but not supported for sending.") }
        return (request, bodyFile)
    }
}
public struct HTTPResult {
    public let file: URL; public let status: Int; public let headers: [String: String]; public let bytes: Int64; public let duration: TimeInterval; public let url: String; public let contentType: String
    public init(file: URL, status: Int, headers: [String: String], bytes: Int64, duration: TimeInterval, url: String, contentType: String) { self.file = file; self.status = status; self.headers = headers; self.bytes = bytes; self.duration = duration; self.url = url; self.contentType = contentType }
}
public final class HTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var uploadFile: URL?; private var session: URLSession!; private var task: URLSessionTask?; private var handle: FileHandle?; private var destination: URL; private var failure: Error?; private var started = Date(); private var bytes: Int64 = 0; private var lastProgress = Date.distantPast
    private let completion: (Result<HTTPResult, Error>) -> Void; private let progress: (Int64) -> Void
    public init(directory: URL, completion: @escaping (Result<HTTPResult, Error>) -> Void, progress: @escaping (Int64) -> Void) throws {
        destination = directory.appendingPathComponent(UUID().uuidString + ".response"); self.completion = completion; self.progress = progress; super.init()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw RelayError.message("Cannot create response file.") }; handle = try FileHandle(forWritingTo: destination)
        let config = URLSessionConfiguration.default; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    public func start(_ request: URLRequest, file: URL? = nil) { started = Date(); uploadFile = file?.lastPathComponent.hasPrefix("Relay-upload-") == true ? file : nil; if let file = file { task = session.uploadTask(with: request, fromFile: file) } else { task = session.dataTask(with: request) }; task?.resume() }
    public func cancel() { task?.cancel() }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try handle?.write(contentsOf: data); bytes += Int64(data.count); if Date().timeIntervalSince(lastProgress) > 0.15 { lastProgress = Date(); let n = bytes; DispatchQueue.main.async { self.progress(n) } } } catch { failure = error; dataTask.cancel() }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close(); handle = nil; if let file = uploadFile { try? FileManager.default.removeItem(at: file) }
        let result: Result<HTTPResult, Error>
        if let e = failure ?? error { try? FileManager.default.removeItem(at: destination); result = .failure(e) }
        else if let response = task.response as? HTTPURLResponse { var headers: [String: String] = [:]; for (k, v) in response.allHeaderFields { headers[String(describing: k)] = String(describing: v) }; result = .success(HTTPResult(file: destination, status: response.statusCode, headers: headers, bytes: bytes, duration: Date().timeIntervalSince(started), url: response.url?.absoluteString ?? "", contentType: response.mimeType ?? "")) }
        else { result = .failure(RelayError.message("The server did not return an HTTP response.")); try? FileManager.default.removeItem(at: destination) }
        session.finishTasksAndInvalidate(); DispatchQueue.main.async { self.completion(result) }
    }
}
