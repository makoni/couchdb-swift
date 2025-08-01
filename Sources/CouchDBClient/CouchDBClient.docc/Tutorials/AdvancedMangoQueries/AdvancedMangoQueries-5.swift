// Advanced Mango Queries Step 5: Executing the Query
struct User: Codable {
    let name: String
    let email: String
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
        fields: ["name", "email"],
        useIndex: "my-index"
    )

    let result: CouchDBFindResponse<User> = try await couchDBClient.find(inDB: dbName, query: query)
    print(result.docs)
}
