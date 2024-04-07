import Foundation
import CouchDBClient

let couchDBClient = CouchDBClient(
    couchProtocol: .http,
    couchHost: "127.0.0.1",
    couchPort: 5984,
    userName: "admin",
    userPassword: "yourPassword"
)

let dbName = "fortests"

struct MyDoc: CouchDBRepresentable {
    var _id: String?
    var _rev: String?
    var title: String
}

Task {
    var doc = MyDoc(title: "My Document")
    try await couchDBClient.insert(dbName: dbName, doc: &doc)
    print(doc)
}

RunLoop.main.run()
