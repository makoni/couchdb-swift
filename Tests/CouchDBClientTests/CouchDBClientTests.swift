import Foundation
import Testing
import NIO
import AsyncHTTPClient
@testable import CouchDBClient

fileprivate let config = CouchDBClient.Config(
	couchProtocol: .http,
	couchHost: "127.0.0.1",
	couchPort: 5984,
	userName: "admin",
	userPassword: (ProcessInfo.processInfo.environment["COUCHDB_PASS"] ?? ""),
	requestsTimeout: 30
)

fileprivate let httpClient = HTTPClient()

@Suite(.serialized)
struct CouchDBClientTests {

	struct ExpectedDoc: CouchDBRepresentable {
		var name: String
		var _id: String = {
			#if canImport(Foundation)
			return Foundation.UUID().uuidString
			#else
			return "id-" + String(Int.random(in: 0..<1000000))
			#endif
		}()
		var _rev: String?

		func updateRevision(_ newRevision: String) -> Self {
			return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
		}
	}

	let testsDB = "fortests"

	let couchDBClient = CouchDBClient(config: config)

	@Test("Initial creation of database for testing. Should create or recreate db")
	func createDB() async throws {
		let exists = try await couchDBClient.dbExists(testsDB)
		if exists {
			try await couchDBClient.deleteDB(testsDB)
		}
		try await couchDBClient.createDB(testsDB)
	}

	@Test("Test dbExists method. Should return true for existing db")
	func DBExists() async throws {
		let exists = try await couchDBClient.dbExists(testsDB)
		#expect(exists == true)
	}

	@Test("Test dbExists method. Should return false for non existing db")
	func DBDoesNotExist() async throws {
		let nonExistentDB = "db_should_not_exist"
		let exists = try await couchDBClient.dbExists(nonExistentDB)
		#expect(exists == false)
	}

	@Test("Get all dbs")
	func getAllDbs() async throws {
		let dbs = try await couchDBClient.getAllDBs()
		#expect(!dbs.isEmpty)
		#expect(dbs.contains(testsDB))
	}

	@Test("Update and delete document")
	func updateAndDeleteDocMethods() async throws {
		var testDoc = ExpectedDoc(name: "test name")
		testDoc = try await couchDBClient.insert(dbName: testsDB, doc: testDoc)
		let expectedInsertId = testDoc._id
		let expectedInsertRev = testDoc._rev!

		testDoc = try await couchDBClient.get(fromDB: testsDB, uri: expectedInsertId)

		testDoc.name = "test name 3"
		let expectedName = testDoc.name
		testDoc = try await couchDBClient.update(dbName: testsDB, doc: testDoc)
		#expect(testDoc._rev != expectedInsertRev)
		#expect(testDoc._id == expectedInsertId)

		let getResponse2 = try await couchDBClient.get(fromDB: testsDB, uri: expectedInsertId)
		let expectedBytes2 = getResponse2.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024 * 10
		var bytes2 = try await getResponse2.body.collect(upTo: expectedBytes2)
		let data2 = bytes2.readData(length: bytes2.readableBytes)

		testDoc = try JSONDecoder().decode(ExpectedDoc.self, from: data2!)
		#expect(expectedName == testDoc.name)

		let response = try await couchDBClient.delete(fromDb: testsDB, doc: testDoc)
		#expect(response.ok == true)
		#expect(!response.id.isEmpty)
		#expect(!response.rev.isEmpty)
	}

	@Test("Insert, Get, Update and Delete methods")
	func insertGetUpdateDelete() async throws {
		var testDoc = ExpectedDoc(name: "test name")
		let insertEncodeData = try JSONEncoder().encode(testDoc)
		let response = try await couchDBClient.insert(
			dbName: testsDB,
			body: HTTPClientRequest.Body.bytes(ByteBuffer(data: insertEncodeData))
		)
		#expect(response.ok == true)
		#expect(!response.id.isEmpty)
		#expect(!response.rev.isEmpty)

		let expectedInsertId = response.id
		let expectedInsertRev = response.rev

		var expectedName = testDoc.name
		let getResponse = try await couchDBClient.get(fromDB: testsDB, uri: expectedInsertId)
		let expectedBytes = getResponse.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024 * 10
		var bytes = try await getResponse.body.collect(upTo: expectedBytes)

		let data = bytes.readData(length: bytes.readableBytes)
		testDoc = try JSONDecoder().decode(ExpectedDoc.self, from: data!)

		#expect(expectedName == testDoc.name)
		#expect(testDoc._rev == expectedInsertRev)
		#expect(testDoc._id == expectedInsertId)

		testDoc.name = "test name 2"
		expectedName = testDoc.name

		let updateEncodedData = try JSONEncoder().encode(testDoc)
		let body: HTTPClientRequest.Body = .bytes(ByteBuffer(data: updateEncodedData))
		let updateResponse = try await couchDBClient.update(
			dbName: testsDB,
			uri: expectedInsertId,
			body: body
		)

		#expect(!updateResponse.rev.isEmpty)
		#expect(!updateResponse.id.isEmpty)
		#expect(updateResponse.rev != expectedInsertRev)
		#expect(updateResponse.id == expectedInsertId)

		let getResponse2 = try await couchDBClient.get(fromDB: testsDB, uri: expectedInsertId)
		let expectedBytes2 = getResponse2.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024 * 10
		var bytes2 = try await getResponse2.body.collect(upTo: expectedBytes2)

		let data2 = bytes2.readData(length: bytes2.readableBytes)
		testDoc = try JSONDecoder().decode(ExpectedDoc.self, from: data2!)

		#expect(expectedName == testDoc.name)

		let deleteResponse = try await couchDBClient.delete(
			fromDb: testsDB,
			uri: testDoc._id,
			rev: testDoc._rev!
		)
		#expect(deleteResponse.ok == true)
		#expect(!deleteResponse.id.isEmpty)
		#expect(!deleteResponse.rev.isEmpty)
	}

	@Test("Authorization works. Should set session cookie")
	func authorization() async throws {
		let session: CreateSessionResponse = try #require(
			try await couchDBClient.authIfNeed()
		)
		#expect(session.ok == true)

		_ = try #require(
			await couchDBClient.sessionCookieExpires
		)
	}

	@Test("Find request with providing body")
	func find_with_body() async throws {
		let testDoc = ExpectedDoc(name: "Greg")
		let insertEncodedData = try JSONEncoder().encode(testDoc)

		let insertResponse = try await couchDBClient.insert(
			dbName: testsDB,
			body: HTTPClientRequest.Body.bytes(ByteBuffer(data: insertEncodedData))
		)

		let selector = ["selector": ["name": "Greg"]]
		let bodyData = try JSONEncoder().encode(selector)
		let requestBody: HTTPClientRequest.Body = .bytes(ByteBuffer(data: bodyData))

		let findResponse = try await couchDBClient.find(
			inDB: testsDB,
			body: requestBody
		)

		let expectedBytes = findResponse.headers.first(name: "content-length").flatMap(Int.init)
		var bytes = try await findResponse.body.collect(upTo: expectedBytes ?? 1024 * 1024 * 10)
		guard let data = bytes.readData(length: bytes.readableBytes) else {
			throw CouchDBClientError.noData
		}

		let decodedResponse = try JSONDecoder().decode(CouchDBFindResponse<ExpectedDoc>.self, from: data)

		#expect(decodedResponse.docs.count > 0)
		#expect(decodedResponse.docs.contains(where: { $0._id == insertResponse.id }))

		_ = try await couchDBClient.delete(
			fromDb: testsDB,
			uri: insertResponse.id,
			rev: insertResponse.rev
		)
	}

	@Test("Find request using generics")
	func find_with_generics() async throws {
		let testDoc = ExpectedDoc(name: "Sam")
		let insertEncodedData = try JSONEncoder().encode(testDoc)

		let insertResponse = try await couchDBClient.insert(
			dbName: testsDB,
			body: HTTPClientRequest.Body.bytes(ByteBuffer(data: insertEncodedData))
		)

		let selector = ["selector": ["name": "Sam"]]
		let docs: [ExpectedDoc] = try await couchDBClient.find(inDB: testsDB, selector: selector)

		#expect(docs.count > 0)
		let id = try #require(docs.first?._id)
		#expect(id == insertResponse.id)

		_ = try await couchDBClient.delete(
			fromDb: testsDB,
			uri: docs.first!._id,
			rev: docs.first!._rev!
		)
	}

	@Test("Create DB, handle conflict")
	func createDB_conflict() async throws {
		let error = await #expect(throws: CouchDBClientError.self) {
			_ = try await couchDBClient.createDB(testsDB)
		}

		#expect({
            switch error {
            case .insertError(let error):
                return error.error == "file_exists" || error.error == "conflict"
            default: return false
            }
		}(), "Expected CouchDBClientError.insertError")

	}

	@Test("Delete non existing DB. Should throw deleteError")
	func delete_non_existing_DB() async throws {
		let nonExistentDB = "db_should_not_exist"

        let error = await #expect(throws: CouchDBClientError.self) {
            _ = try await couchDBClient.deleteDB(nonExistentDB)
        }

        #expect({
            switch error {
            case .deleteError(let error):
                return error.error == "not_found"
            default: return false
            }
        }(), "Expected CouchDBClientError.deleteError")
	}

	@Test("Get non existing document. Should throw notFound")
	func get_non_existing_document() async throws {
        let error = await #expect(throws: CouchDBClientError.self) {
            let _: ExpectedDoc = try await couchDBClient.get(fromDB: testsDB, uri: "aaaaa")
        }

        #expect({
            switch error {
            case .notFound(_): return true
            default: return false
            }
        }(), "Expected CouchDBClientError.notFound")
	}

	@Test("Update document without updating rev. Should throw conflict")
	func update_document_conflict() async throws {
		let doc = ExpectedDoc(name: "should not exist", _id: "nonexistent_doc_id", _rev: "1-abc")
		var insertedDoc: ExpectedDoc!

        let error = await #expect(throws: CouchDBClientError.self) {
            insertedDoc = try await couchDBClient.insert(dbName: testsDB, doc: doc)
            _ = try await couchDBClient.update(dbName: testsDB, doc: doc)
        }

        #expect({
            switch error {
            case .conflictError(let error):
                return error.error == "conflict"
            default: return false
            }
        }(), "Expected CouchDBClientError.conflictError")

		_ = try await couchDBClient.delete(fromDb: testsDB, doc: insertedDoc)
	}

	@Test("Delete non existing document. Should throw deleteError")
	func delete_non_existing_document() async throws {
		let doc = ExpectedDoc(name: "should not exist", _id: "nonexistent_doc_id", _rev: "1-abc")

        let error = await #expect(throws: CouchDBClientError.self) {
            _ = try await couchDBClient.delete(fromDb: testsDB, doc: doc)
        }

        #expect({
            switch error {
            case .deleteError(let error):
                return error.error == "not_found"
            default: return false
            }
        }(), "Expected CouchDBClientError.deleteError")
	}

	@Test("Call getAllDBs providing an EventLoopGroup")
	func getAllDBs_with_eventLoopGroup() async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
		let dbs = try await couchDBClient.getAllDBs(eventLoopGroup: group)

        #expect(dbs.contains(testsDB))

        try await group.shutdownGracefully()
	}

	@Test("Call dbExists providing an EventLoopGroup")
	func dbExists_with_eventLoopGroup() async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        #expect(
            try await couchDBClient.dbExists(testsDB, eventLoopGroup: group)
        )

        try await group.shutdownGracefully()
	}

	@Test("Calling createDB providing an EventLoopGroup")
	func createDB_with_eventLoopGroup() async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
		let tempDB = "tempdb_for_eventloop"

        _ = try await couchDBClient.createDB(tempDB, eventLoopGroup: group)

        #expect(
            try await couchDBClient.dbExists(tempDB)
        )

        try await couchDBClient.deleteDB(tempDB)
		try await group.shutdownGracefully()
	}

	@Test("Calling deleteDB providing an EventLoopGroup")
	func test20_deleteDB_with_eventLoopGroup() async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
		let tempDB = "tempdb_for_eventloop_delete"

        _ = try await couchDBClient.createDB(tempDB)
		_ = try await couchDBClient.deleteDB(tempDB, eventLoopGroup: group)

		#expect(
            try await couchDBClient.dbExists(tempDB) == false
        )

        try await group.shutdownGracefully()
	}

	@Test("Calling find with custom date decoding strategy")
	func test21_find_with_custom_date_decoding_strategy() async throws {
		let testDoc = ExpectedDoc(name: "DateTest")
		let insertEncodedData = try JSONEncoder().encode(testDoc)
		let insertResponse = try await couchDBClient.insert(
			dbName: testsDB,
			body: .bytes(ByteBuffer(data: insertEncodedData))
		)

        let selector = ["selector": ["name": "DateTest"]]
		let docs: [ExpectedDoc] = try await couchDBClient.find(
			inDB: testsDB,
			selector: selector,
			dateDecodingStrategy: .iso8601
		)

        #expect(docs.contains(where: { $0._id == insertResponse.id }))

		_ = try await couchDBClient.delete(
			fromDb: testsDB,
			uri: insertResponse.id,
			rev: insertResponse.rev
		)
	}

	@Test("Cleanup: Delete Test Database")
	func deleteDB() async throws {
		try await couchDBClient.deleteDB(testsDB)
	}
}
