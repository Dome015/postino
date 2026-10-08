import Foundation

/// A collection root or a folder within it. Nodes retain their identity when moved.
public struct CollectionContainer {
    public let collection: Collection
    public let folder: CollectionNode?
    public init(collection: Collection, folder: CollectionNode? = nil) { self.collection = collection; self.folder = folder }
    public var nodes: [CollectionNode] {
        get { folder?.children ?? collection.nodes }
        nonmutating set { if let folder { folder.children = newValue } else { collection.nodes = newValue } }
    }
    public func isSame(as other: CollectionContainer) -> Bool { collection === other.collection && folder === other.folder }
    public func isValid(in collections: [Collection]) -> Bool {
        guard collections.contains(where: { $0 === collection }) else { return false }
        guard let folder else { return true }
        return folder.request == nil && CollectionTree.location(of: folder, in: [collection]) != nil
    }
}
public enum CollectionTree {
    public struct Location {
        public let container: CollectionContainer
        public let index: Int
    }
    public static func location(of node: CollectionNode, in collections: [Collection]) -> Location? {
        func find(_ container: CollectionContainer) -> Location? {
            for (index, child) in container.nodes.enumerated() {
                if child === node { return Location(container: container, index: index) }
                if child.request == nil, let found = find(CollectionContainer(collection: container.collection, folder: child)) { return found }
            }
            return nil
        }
        for collection in collections { if let found = find(CollectionContainer(collection: collection)) { return found } }
        return nil
    }
    public static func canMove(_ node: CollectionNode, to target: CollectionContainer, in collections: [Collection]) -> Bool {
        guard location(of: node, in: collections) != nil, target.isValid(in: collections) else { return false }
        func contains(_ parent: CollectionNode, _ child: CollectionNode) -> Bool { parent === child || parent.children.contains { contains($0, child) } }
        return target.folder.map { !contains(node, $0) } ?? true
    }
    /// The insertion index refers to the destination before removing the source.
    @discardableResult public static func move(_ node: CollectionNode, to target: CollectionContainer, at index: Int, in collections: [Collection]) -> Bool {
        guard canMove(node, to: target, in: collections), (0...target.nodes.count).contains(index),
              let source = location(of: node, in: collections) else { return false }
        var insertion = index
        if source.container.isSame(as: target), source.index < insertion { insertion -= 1 }
        source.container.nodes.remove(at: source.index)
        target.nodes.insert(node, at: insertion)
        refreshInheritance(in: target.collection)
        return true
    }
    public static func refreshInheritance(in collection: Collection) {
        func variables(_ json: JSON, inheriting inherited: [String: String]) -> [String: String] {
            var result = inherited
            for pair in (json["variable"] as? [JSON] ?? []).map(Pair.init) where pair.enabled { result[pair.key] = pair.value }
            return result
        }
        func update(_ nodes: [CollectionNode], auth: JSON?, inherited: [String: String]) {
            for node in nodes {
                let values = variables(node.original, inheriting: inherited)
                let inheritedAuth = node.original["auth"] as? JSON ?? auth
                if let request = node.request { request.variables = values; request.inheritedAuth = inheritedAuth }
                else { update(node.children, auth: inheritedAuth, inherited: values) }
            }
        }
        update(collection.nodes, auth: collection.original["auth"] as? JSON, inherited: variables(collection.original, inheriting: [:]))
    }
}
