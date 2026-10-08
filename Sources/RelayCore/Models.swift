import Foundation

public typealias JSON = [String: Any]
public struct Pair {
    public var key: String; public var value: String; public var enabled: Bool; public var extra: JSON
    public init(_ key: String = "", _ value: String = "", enabled: Bool = true, extra: JSON = [:]) { self.key = key; self.value = value; self.enabled = enabled; self.extra = extra }
    public init(json: JSON) { key = json["key"] as? String ?? ""; value = Self.string(json["value"]); enabled = !(json["disabled"] as? Bool ?? false) && (json["enabled"] as? Bool ?? true); extra = json }
    public static func string(_ x: Any?) -> String { if let s = x as? String { return s }; if let x = x, !(x is NSNull) { return String(describing: x) }; return "" }
    public var json: JSON { var j = extra; j["key"] = key; j["value"] = value; j["disabled"] = !enabled; return j }
}
public final class RequestItem {
    public let id: String
    public var name: String; public var method: String; public var url: String
    public var headers: [Pair]; public var params: [Pair]; public var body: String; public var bodyMode: String; public var form: [Pair]
    public var auth: JSON?; public var original: JSON; public var inheritedAuth: JSON?; public var variables: [String: String]
    public init(item: JSON = ["name": "Untitled request", "request": ["method": "GET", "url": ""]], inheritedAuth: JSON? = nil, variables: [String: String] = [:]) {
        original = item; id = item["_relayID"] as? String ?? UUID().uuidString; name = item["name"] as? String ?? "Untitled request"
        let r = item["request"] as? JSON ?? ["url": item["request"] as? String ?? ""]
        method = r["method"] as? String ?? "GET"
        let u = r["url"] as? JSON
        url = r["url"] as? String ?? u?["raw"] as? String ?? ""
        if url.isEmpty, let u = u { let host = (u["host"] as? [String] ?? []).joined(separator: "."); let path = (u["path"] as? [String] ?? []).joined(separator: "/"); url = "\(u["protocol"] as? String ?? "https")://\(host)/\(path)" }
        headers = (r["header"] as? [JSON] ?? []).map(Pair.init)
        params = (u?["query"] as? [JSON] ?? []).map(Pair.init)
        if params.isEmpty { params = Self.queryPairs(url) }
        let b = r["body"] as? JSON ?? [:]; bodyMode = b["mode"] as? String ?? "raw"; body = b["raw"] as? String ?? ""
        if bodyMode == "file" { body = (b["file"] as? JSON)?["src"] as? String ?? "" }
        form = (b[bodyMode] as? [JSON] ?? []).map(Pair.init)
        auth = r["auth"] as? JSON; self.inheritedAuth = inheritedAuth; self.variables = variables
    }
    public static func queryPairs(_ raw: String) -> [Pair] {
        guard let q = raw.split(separator: "?", maxSplits: 1).last, raw.contains("?") else { return [] }
        return q.split(separator: "#", maxSplits: 1)[0].split(separator: "&").map { segment in let p = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false); return Pair(String(p[0]).removingPercentEncoding ?? String(p[0]), p.count > 1 ? (String(p[1]).removingPercentEncoding ?? String(p[1])) : "") }
    }
    public func setURL(_ raw: String) { url = raw; params = Self.queryPairs(raw) }
    public var resolvedRawURL: String {
        let base = url.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? url
        let active = params.filter { $0.enabled && !$0.key.isEmpty }
        if active.isEmpty { return base }
        // Keep variable placeholders intact in exports; percent encoding happens after substitution.
        return base + "?" + active.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
    public func exported(internalIDs: Bool = false) -> JSON {
        var item = original; item["name"] = name; item.removeValue(forKey: "_relayID"); if internalIDs { item["_relayID"] = id }
        var r = original["request"] as? JSON ?? [:]; r["method"] = method
        var u = r["url"] as? JSON ?? [:]; u["raw"] = resolvedRawURL; u["query"] = params.filter { !$0.key.isEmpty }.map(\.json)
        // URL components are derived anew, so a Postman export never contains stale host/path fields.
        let rawBase = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        if let c = URLComponents(string: rawBase), let host = c.host { u["protocol"] = c.scheme; u["host"] = host.components(separatedBy: "."); u["path"] = c.path.split(separator: "/").map(String.init); u["port"] = c.port.map(String.init) }
        else { ["protocol", "host", "path", "port"].forEach { u.removeValue(forKey: $0) } }
        r["url"] = u; r["header"] = headers.filter { !$0.key.isEmpty }.map(\.json)
        var b = r["body"] as? JSON ?? [:]; b["mode"] = bodyMode
        if bodyMode == "raw" { b["raw"] = body } else if bodyMode == "file" { var f = b["file"] as? JSON ?? [:]; f["src"] = body; b["file"] = f } else { b[bodyMode] = form.filter { !$0.key.isEmpty }.map(\.json) }
        r["body"] = b; r["auth"] = auth; item["request"] = r; return item
    }
}
public final class CollectionNode {
    public var name: String; public var children: [CollectionNode]; public var request: RequestItem?; public var original: JSON
    public init(json: JSON, auth: JSON? = nil, variables: [String: String] = [:]) {
        original = json; name = json["name"] as? String ?? "Folder"
        var vars = variables; for p in (json["variable"] as? [JSON] ?? []).map(Pair.init) where p.enabled { vars[p.key] = p.value }
        let inherited = json["auth"] as? JSON ?? auth
        children = (json["item"] as? [JSON] ?? []).map { CollectionNode(json: $0, auth: inherited, variables: vars) }
        request = json["request"] == nil ? nil : RequestItem(item: json, inheritedAuth: inherited, variables: vars)
    }
    public var allRequests: [RequestItem] { request.map { [$0] } ?? children.flatMap(\.allRequests) }
    public func exported(internalIDs: Bool = false) -> JSON { if let r = request { return r.exported(internalIDs: internalIDs) }; var j = original; j["name"] = name; j["item"] = children.map { $0.exported(internalIDs: internalIDs) }; return j }
}
public final class Collection {
    public var original: JSON; public var name: String; public var nodes: [CollectionNode]
    public init(json: JSON) throws {
        guard let info = json["info"] as? JSON, let name = info["name"] as? String, let items = json["item"] as? [JSON] else { throw RelayError.message("This file is not a Postman v2 collection. Export it as Collection v2.1 JSON in Postman.") }
        original = json; self.name = name
        var vars: [String: String] = [:]; for p in (json["variable"] as? [JSON] ?? []).map(Pair.init) where p.enabled { vars[p.key] = p.value }
        nodes = items.map { CollectionNode(json: $0, auth: json["auth"] as? JSON, variables: vars) }
    }
    public var allRequests: [RequestItem] { nodes.flatMap(\.allRequests) }
    public func exported(internalIDs: Bool = false) -> JSON { var j = original; var info = j["info"] as? JSON ?? [:]; info["name"] = name; info["schema"] = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"; j["info"] = info; j["item"] = nodes.map { $0.exported(internalIDs: internalIDs) }; return j }
}
public final class Environment {
    public var name: String; public var values: [Pair]; public var original: JSON
    public init(json: JSON) throws { guard let name = json["name"] as? String, let values = json["values"] as? [JSON] else { throw RelayError.message("This file is not a Postman environment JSON file.") }; self.name = name; self.values = values.map(Pair.init); original = json }
    public var variables: [String: String] { var v: [String: String] = [:]; for p in values where p.enabled && !p.key.isEmpty { v[p.key] = p.value }; return v }
    public var exported: JSON { var j = original; j["name"] = name; j["_postman_variable_scope"] = "environment"; j["values"] = values.filter { !$0.key.isEmpty }.map { p in var v = p.extra; v["key"] = p.key; v["value"] = p.value; v["enabled"] = p.enabled; v.removeValue(forKey: "disabled"); return v }; return j }
}
public enum RelayError: LocalizedError { case message(String); public var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
public enum Postman {
    public static func read(_ data: Data) throws -> JSON { guard let json = try JSONSerialization.jsonObject(with: data) as? JSON else { throw RelayError.message("Expected a JSON object.") }; return json }
    public static func encode(_ json: JSON) throws -> Data { try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
}
