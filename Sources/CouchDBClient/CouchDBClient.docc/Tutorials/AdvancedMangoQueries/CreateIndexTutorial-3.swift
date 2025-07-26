// Step 3: Execute index creation
let indexFields: [[String: String]] = [["type": "asc"], ["age": "asc"]]
let indexDef = IndexDefinition(fields: indexFields)
let mangoIndex = MangoIndex(ddoc: "my-ddoc", name: "my-index", type: "json", def: indexDef)

func createIndexExample(couchDBClient: CouchDBClient, dbName: String) async throws {
    let response = try await couchDBClient.createIndex(inDB: dbName, index: mangoIndex)
    print(response)
}
