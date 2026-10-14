import Foundation

/// An open request is independent of its saved collection entry.
public final class RequestDraft {
    public let request: RequestItem
    public private(set) var source: RequestItem?
    public private(set) var isEphemeral: Bool
    private let initial: RequestItem
    public init(_ source: RequestItem, saved: Bool = true, ephemeral: Bool = false) {
        request = Self.copy(source)
        initial = Self.copy(source)
        isEphemeral = ephemeral
        self.source = saved && !ephemeral ? source : nil
    }
    public var canSave: Bool { isEphemeral || isDirty }
    public var isDirty: Bool {
        if isEphemeral { return false }
        if source == nil && (!request.url.isEmpty || !request.body.isEmpty || !request.headers.isEmpty || !request.params.isEmpty || !request.form.isEmpty || request.auth != nil || request.name != "Untitled request") { return true }
        let source = source ?? initial
        return request.name != source.name || request.method != source.method || request.url != source.url || request.body != source.body || request.bodyMode != source.bodyMode ||
            !NSArray(array: request.headers.map(\.json)).isEqual(to: source.headers.map(\.json)) ||
            !NSArray(array: request.params.map(\.json)).isEqual(to: source.params.map(\.json)) ||
            !NSArray(array: request.form.map(\.json)).isEqual(to: source.form.map(\.json)) ||
            !NSDictionary(dictionary: request.auth ?? [:]).isEqual(to: source.auth ?? [:])
    }
    public func save() -> RequestItem {
        let saved = Self.copy(request)
        source = saved
        isEphemeral = false
        return saved
    }
    private static func copy(_ item: RequestItem) -> RequestItem {
        let copy = RequestItem(item: item.exported(internalIDs: true), inheritedAuth: item.inheritedAuth, variables: item.variables)
        copy.url = item.url; copy.params = item.params; copy.headers = item.headers; copy.form = item.form; copy.auth = item.auth
        return copy
    }
}
