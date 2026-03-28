// Advanced Mango Queries Step 3: Projections (Fields)
struct User: CouchDBRepresentable {
    let name: String
    let email: String
    let _id: String
    let _rev: String?

    func updateRevision(_ newRevision: String) -> User {
        User(name: name, email: email, _id: _id, _rev: newRevision)
    }
}

Task {
    let query = MangoQuery(
        selector: [
            "type": .string("user"),
            "age": .comparison(.greaterThan(.int(30)))
        ],
        sort: [MangoSortField(field: "name", direction: .asc)],
        limit: 10,
        skip: 0,
        fields: ["_id", "_rev", "name", "email"]
    )
}
