import Foundation

/// Export the current executable request without changing workspace storage.
public enum CurlExporter {
    public static func command(_ item: RequestItem, environment: [String: String] = [:]) throws -> String {
        let multipart = item.bodyMode == "formdata"
        let request: URLRequest, file: URL?
        if multipart { request = try RequestBuilder.baseRequest(item, environment: environment, timeout: 120); file = nil }
        else { (request, file) = try RequestBuilder.build(item, environment: environment) }
        let vars = item.variables.merging(environment) { _, new in new }
        func resolve(_ value: String) throws -> String { try RequestBuilder.resolve(value, variables: vars) }
        var options = ["curl --disable", "--globoff", "--location", "--request " + (try quote(request.httpMethod ?? "GET"))]
        // --request HEAD alone makes curl wait for a body the server won't send.
        if request.httpMethod == "HEAD" {
            guard !multipart && file == nil && request.httpBody == nil else { throw RelayError.message("cURL cannot copy a HEAD request with a body. Remove the body or choose another method.") }
            options.append("--head")
        }
        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            if multipart && key.caseInsensitiveCompare("Content-Type") == .orderedSame { continue }
            guard !key.hasPrefix("@") else { throw RelayError.message("cURL cannot represent a header name beginning with @.") }
            options.append("--header " + (try quote(value.isEmpty ? key + ";" : key + ": " + value)))
        }
        if multipart {
            let fields = item.form.filter { $0.enabled && !$0.key.isEmpty }
            if fields.isEmpty {
                options.append("--header 'Content-Type: multipart/form-data; boundary=Postino-empty'")
                options.append("--data-raw " + (try quote("--Postino-empty--\r\n")))
            } else { options.append("--form-escape") }
            for pair in fields {
                let key = try resolve(pair.key).replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                guard !key.contains("=") else { throw RelayError.message("cURL cannot represent a multipart field name containing =.") }
                if pair.extra["type"] as? String == "file" {
                    let path = !pair.value.isEmpty ? pair.value : (pair.extra["src"] as? String ?? (pair.extra["src"] as? [String])?.first ?? "")
                    let file = URL(fileURLWithPath: try resolve(path))
                    guard FileManager.default.isReadableFile(atPath: file.path) else { throw RelayError.message("The multipart file cannot be read. Choose a local file.") }
                    let type = pair.extra["contentType"] as? String ?? "application/octet-stream"
                    guard !type.contains(where: { $0.isNewline }) else { throw RelayError.message("Multipart content types cannot contain newlines.") }
                    options.append("--form " + (try quote(key + "=@" + formQuote(file.path) + ";headers=" + formQuote("Content-Type: " + type))))
                } else {
                    options.append("--form-string " + (try quote(key + "=" + resolve(pair.value))))
                }
            }
        } else if let file {
            if request.value(forHTTPHeaderField: "Content-Type") == nil { options.append("--header 'Content-Type:'") }
            options.append("--data-binary " + (try quote("@" + file.path)))
        } else if let data = request.httpBody {
            guard let body = String(data: data, encoding: .utf8) else { throw RelayError.message("The request body cannot be represented as text in a cURL command.") }
            options.append("--data-raw " + (try quote(body)))
        }
        options.append("--url " + (try quote(request.url!.absoluteString)))
        return options.joined(separator: " \\\n  ")
    }
    private static func quote(_ value: String) throws -> String {
        guard !value.contains("\0") else { throw RelayError.message("Shell commands cannot contain null bytes. Use a binary file body instead.") }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    private static func formQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
