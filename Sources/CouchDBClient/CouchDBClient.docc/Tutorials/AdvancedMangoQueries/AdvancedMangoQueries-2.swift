// Advanced Mango Queries Step 2: Sorting, Limit, and Skip
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
        skip: 0
    )
}
