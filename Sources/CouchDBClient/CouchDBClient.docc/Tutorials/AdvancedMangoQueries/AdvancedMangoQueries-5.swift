// Advanced Mango Queries Step 5: Executing the Query
struct User: Codable {
    let name: String
    let email: String
}

Task {
    let query = MangoQuery(
        selector: [
            "type": .string("user"),
            "age": .dictionary(["$gt": .int(30)])
        ],
        fields: ["name", "email"],
        sort: [["name": "asc"]],
        limit: 10,
        skip: 0,
        useIndex: "my-index"
    )

    let result: CouchDBFindResponse<User> = try await couchDBClient.find(dbName: dbName, query: query)
    print(result.docs)
}
