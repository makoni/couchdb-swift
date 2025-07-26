import Foundation
import Testing
import NIOCore  // For ByteBuffer
@testable import CouchDBClient

fileprivate let config = CouchDBClient.Config(
	couchProtocol: .http,
	couchHost: "127.0.0.1",
	couchPort: 5984,
	userName: "admin",
	userPassword: (ProcessInfo.processInfo.environment["COUCHDB_PASS"] ?? ""),
	requestsTimeout: 30
)

fileprivate let couchDBClient = CouchDBClient(config: config)
fileprivate let testsDB = "attachments_api_tests"

@Suite(.serialized)
struct AttachmentsAPITests {
	let testDocId = "test_doc_with_attachment"
	let testAttachmentName = "test-image.png"
	let testAttachmentPath = "Tests/CouchDBClientTests/test-image.png"
	let testContentType = "image/png"

	@Test("Setup: Create DB and insert test doc")
	func setupDBAndDoc() async throws {
		if try await couchDBClient.dbExists(testsDB) {
			try await couchDBClient.deleteDB(testsDB)
		}
		try await couchDBClient.createDB(testsDB)
		struct Doc: Codable {
			let _id: String
			let type: String
		}
		let doc = Doc(_id: testDocId, type: "attachment-test")
		let encodedDoc = try JSONEncoder().encode(doc)
		_ = try await couchDBClient.insert(dbName: testsDB, body: .bytes(ByteBuffer(data: encodedDoc)))
	}

	@Test("Upload attachment to document")
	func uploadAttachment() async throws {
		let data = try Data(contentsOf: URL(fileURLWithPath: testAttachmentPath))
		let response = try await couchDBClient.get(fromDB: testsDB, uri: testDocId)
		let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024 * 10
		var bytes = try await response.body.collect(upTo: expectedBytes)
		guard let dataDoc = bytes.readData(length: bytes.readableBytes) else { throw CouchDBClientError.noData }
		let doc = try JSONSerialization.jsonObject(with: dataDoc, options: []) as? [String: Any]
		let rev = (doc?["_rev"] as? String) ?? ""
		let uploadResponse = try await couchDBClient.uploadAttachment(
			dbName: testsDB,
			docId: testDocId,
			attachmentName: testAttachmentName,
			data: data,
			contentType: testContentType,
			rev: rev
		)
		#expect(uploadResponse.ok == true)
		#expect(!uploadResponse.rev.isEmpty)
	}

	@Test("Download attachment and verify data matches upload")
	func downloadAttachment() async throws {
		let uploadedData = try Data(contentsOf: URL(fileURLWithPath: testAttachmentPath))
		let downloadedData = try await couchDBClient.downloadAttachment(
			dbName: testsDB,
			docId: testDocId,
			attachmentName: testAttachmentName
		)
		#expect(downloadedData == uploadedData)
	}

	@Test("Delete attachment from document")
	func deleteAttachment() async throws {
		let response = try await couchDBClient.get(fromDB: testsDB, uri: testDocId)
		let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024 * 10
		var bytes = try await response.body.collect(upTo: expectedBytes)
		guard let dataDoc = bytes.readData(length: bytes.readableBytes) else { throw CouchDBClientError.noData }
		let doc = try JSONSerialization.jsonObject(with: dataDoc, options: []) as? [String: Any]
		let rev = (doc?["_rev"] as? String) ?? ""
		let deleteResponse = try await couchDBClient.deleteAttachment(
			dbName: testsDB,
			docId: testDocId,
			attachmentName: testAttachmentName,
			rev: rev
		)
		#expect(deleteResponse.ok == true)
		#expect(!deleteResponse.rev.isEmpty)
	}

	@Test("Cleanup: Delete Test Database")
	func cleanupDB() async throws {
		try await couchDBClient.deleteDB(testsDB)
	}
}
