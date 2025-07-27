// Advanced Mango Queries Step 1: Building Selectors
struct User: Codable {
    let name: String
    let email: String
}

Task {
    let query = MangoQuery(
        selector: [
            "type": .string("user"),
            "age": .comparison(.greaterThan(.int(30)))
        ]
    )
}
