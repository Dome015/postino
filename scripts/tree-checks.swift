import Foundation
import RelayCore

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checks += 1 }
func request(_ name: String) -> JSON { ["name": name, "response": [["name": "Example"]], "request": ["method": "POST", "url": "{{host}}/test", "body": ["mode": "raw", "raw": "{\"keep\":true}"]]] }
let first = try Collection(json: ["info": ["name": "First"], "variable": [["key": "host", "value": "first"]], "auth": ["type": "bearer", "bearer": [["key": "token", "value": "one"]]], "item": [["name": "Folder A", "variable": [["key": "host", "value": "folder-a"]], "item": [request("A"), request("B"), request("C"), ["name": "Nested", "item": [JSON]()]]]]])
let second = try Collection(json: ["info": ["name": "Second"], "variable": [["key": "host", "value": "second"]], "auth": ["type": "basic", "basic": [["key": "username", "value": "two"]]], "item": [["name": "Folder B", "item": [JSON]()]]])
let collections = [first, second]
let folderA = first.nodes[0], folderB = second.nodes[0], nested = folderA.children[3]
let a = folderA.children[0], b = folderA.children[1], c = folderA.children[2]
let source = CollectionContainer(collection: first, folder: folderA)
let target = CollectionContainer(collection: second, folder: folderB)
check(CollectionTree.move(a, to: source, at: 3, in: collections), "Can reorder down within a folder")
check(folderA.children.map(\.name) == ["B", "C", "A", "Nested"], "Downward insertion compensates for removed source")
check(CollectionTree.move(a, to: source, at: 0, in: collections), "Can reorder upward")
check(folderA.children.map(\.name) == ["A", "B", "C", "Nested"], "Upward insertion uses the intended position")
check(CollectionTree.move(a, to: source, at: 1, in: collections) && folderA.children[0] === a, "Adjacent no-op does not duplicate a node")
let identity = b.request!
let draft = RequestDraft(identity); draft.request.body = "unsaved body"
check(CollectionTree.move(b, to: target, at: 0, in: collections), "Move between collections and into an empty folder")
check(folderB.children[0] === b && b.request === identity && !folderA.children.contains { $0 === b }, "Move preserves request identity without duplicating it")
check(identity.variables["host"] == "second" && identity.inheritedAuth?["type"] as? String == "basic", "Inherited variables and auth follow the new parent")
check(draft.isDirty && draft.request.body == "unsaved body" && draft.source === identity, "Moving a saved node preserves an open dirty draft")
check(identity.body == "{\"keep\":true}" && (identity.original["response"] as? [JSON])?.first?["name"] as? String == "Example", "Body and Postman metadata survive the move")
check(CollectionTree.move(c, to: CollectionContainer(collection: second), at: 0, in: collections), "Move a request to a collection root")
check(second.nodes[0] === c && c.request?.variables["host"] == "second", "Root insertion keeps order and inheritance")
let beforeCycle = try Postman.encode(first.exported(internalIDs: true))
check(!CollectionTree.move(folderA, to: CollectionContainer(collection: first, folder: nested), at: 0, in: collections), "Cannot move a folder into its descendant")
check(!CollectionTree.move(folderA, to: source, at: 0, in: collections), "Cannot move a folder into itself")
let afterCycle = try Postman.encode(first.exported(internalIDs: true))
check(afterCycle == beforeCycle, "Rejected cycles do not change the tree")
check(!CollectionTree.move(a, to: target, at: 999, in: collections) && source.nodes[0] === a, "Invalid insertion leaves the source untouched")
check(!CollectionTree.move(a, to: CollectionContainer(collection: second, folder: folderA), at: 0, in: collections), "Reject a folder belonging to a different collection")
check(!CollectionTree.move(a, to: CollectionContainer(collection: first, folder: a), at: 0, in: collections), "A request cannot contain another request")
check(CollectionTree.move(folderA, to: target, at: 1, in: collections), "Move an entire folder without rebuilding its requests")
check(a.request?.variables["host"] == "folder-a" && a.request?.inheritedAuth?["type"] as? String == "basic", "Folder overrides persist while inherited auth follows the destination")
let reloaded = try Collection(json: Postman.read(Postman.encode(second.exported(internalIDs: true))))
check(reloaded.nodes.map(\.name) == ["C", "Folder B"], "Collection order persists through workspace/export round trips")
check(reloaded.nodes[1].children.map(\.name) == ["B", "Folder A"], "Folder order persists through round trips")
check(reloaded.allRequests.map(\.id) == second.allRequests.map(\.id), "Moved request IDs persist")
check(reloaded.allRequests.last?.variables["host"] == "folder-a" && reloaded.allRequests.last?.inheritedAuth?["type"] as? String == "basic", "Reloaded inheritance matches the live tree")
print("Passed \(checks) collection move, ordering, inheritance, draft, and persistence checks")
