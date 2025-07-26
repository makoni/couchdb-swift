// Advanced Mango Queries Step 3: Projections (Fields)
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
        fields: ["name", "email"]
    )
}
