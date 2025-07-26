// Step 3: Execute index creation
let indexFields = ["type", "age"]
let mangoIndex = MangoIndex(/* correct initializer here, e.g. fields: indexFields */)

Task {
    let response = try await couchDBClient.createIndex(dbName: dbName, index: mangoIndex)
    print(response)
}
