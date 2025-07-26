// Advanced Mango Queries Step 4: Index Usage
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
        sort: [["name": .asc]],
        limit: 10,
        skip: 0,
        fields: ["name", "email"],
        useIndex: "my-index"
    )
}
