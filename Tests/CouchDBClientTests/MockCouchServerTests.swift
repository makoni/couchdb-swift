import Foundation
import NIO
import Testing
@testable import CouchDBClient

@Suite(.serialized)
struct MockCouchServerTests {

	private func makeClient(port: Int) -> CouchDBClient {
		CouchDBClient(
			config: .init(
				couchHost: "127.0.0.1",
				couchPort: port,
				userName: "admin"
			)
		)
	}

	@Test("Delete with empty response body. Should throw noData")
	func delete_empty_body_throws_noData() async throws {
		let server = MockCouchServer { _, _ in
			.init(status: .ok, body: Data())
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = makeClient(port: port)

		let error = await #expect(throws: CouchDBClientError.self) {
			_ = try await client.delete(fromDb: "fortests", uri: "any_doc", rev: "1-abc")
		}

		#expect(
			{
				switch error {
				case .noData:
					return true
				default: return false
				}
			}(), "Expected CouchDBClientError.noData")
	}

	@Test("Delete with bad request response. Should throw deleteError")
	func delete_bad_request_throws_deleteError() async throws {
		let server = MockCouchServer { _, _ in
			.init(status: .badRequest, body: Data(#"{"error":"bad_request","reason":"Invalid rev format"}"#.utf8))
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = makeClient(port: port)

		let error = await #expect(throws: CouchDBClientError.self) {
			_ = try await client.delete(fromDb: "fortests", uri: "any_doc", rev: "garbage")
		}

		#expect(
			{
				switch error {
				case .deleteError(let error):
					return error.reason == "Invalid rev format"
				default: return false
				}
			}(), "Expected CouchDBClientError.deleteError")
	}

	@Test("Insert with conflict response. Should throw conflictError")
	func insert_conflict_throws_conflictError() async throws {
		let server = MockCouchServer { _, _ in
			.init(status: .conflict, body: Data(#"{"error":"conflict","reason":"Document exists"}"#.utf8))
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = makeClient(port: port)

		let error = await #expect(throws: CouchDBClientError.self) {
			_ = try await client.insert(dbName: "fortests", doc: CouchDBClientTests.ExpectedDoc(name: "My doc"))
		}

		#expect(
			{
				switch error {
				case .conflictError(let error):
					return error.error == "conflict"
				default: return false
				}
			}(), "Expected CouchDBClientError.conflictError")
	}

	@Test("Response larger than the default limit. Should throw NIOTooManyBytesError")
	func oversized_response_capped_at_default() async throws {
		let body = Data(count: 11 * 1024 * 1024)
		let server = MockCouchServer { _, _ in
			.init(status: .ok, body: body)
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = makeClient(port: port)

		do {
			_ = try await client.get(fromDB: "fortests", uri: "any_doc")
			Issue.record("Expected NIOTooManyBytesError but the request succeeded")
		} catch let error as NIOTooManyBytesError {
			#expect(error.maxBytes == 10 * 1024 * 1024)
		}
	}

	@Test("Response of exactly the default limit. Should be returned")
	func response_at_default_limit_succeeds() async throws {
		let body = Data(count: 10 * 1024 * 1024)
		let server = MockCouchServer { _, _ in
			.init(status: .ok, body: body)
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = makeClient(port: port)

		let response = try await client.get(fromDB: "fortests", uri: "any_doc")
		let bytes = try await response.body.collect(upTo: 10 * 1024 * 1024)

		#expect(bytes.readableBytes == 10 * 1024 * 1024)
	}

	@Test("Response within a custom limit. Should be returned")
	func response_within_custom_limit_succeeds() async throws {
		let body = Data(count: 11 * 1024 * 1024)
		let server = MockCouchServer { _, _ in
			.init(status: .ok, body: body)
		}
		let port = try server.start()
		defer { try? server.stop() }

		let client = CouchDBClient(
			config: .init(
				couchHost: "127.0.0.1",
				couchPort: port,
				userName: "admin",
				maxResponseBytes: 12 * 1024 * 1024
			)
		)

		let response = try await client.get(fromDB: "fortests", uri: "any_doc")
		let bytes = try await response.body.collect(upTo: 12 * 1024 * 1024)

		#expect(bytes.readableBytes == 11 * 1024 * 1024)
	}
}
