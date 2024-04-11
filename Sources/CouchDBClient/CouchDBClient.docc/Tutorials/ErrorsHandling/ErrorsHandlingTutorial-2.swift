Task {
    var doc = MyDoc(title: "My Document")
    
    do {
        try await couchDBClient.insert(dbName: dbName, doc: &doc)
    } catch CouchDBClientError.insertError(let error) {
        print(error.reason)
        return
    } catch {
        print(error.localizedDescription)
        return
    }
    print(doc)
    
    doc.title = "Updated title"
    try await couchDBClient.update(dbName: dbName, doc: &doc)
    print(doc)
    
    let docFromDB: MyDoc = try await couchDBClient.get(fromDB: dbName, uri: doc._id!)
    print(docFromDB)
    
    let deleteResponse = try await couchDBClient.delete(fromDb: dbName, doc: doc)
}
