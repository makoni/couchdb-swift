//
//  HTTPClientTests.swift
//  couchdb-swift
//
//  Created by Sergei Armodin on 09.07.2025.
//

import Foundation
import Testing
import AsyncHTTPClient
@testable import CouchDBClient

@Suite("HTTP Client tests")
struct HTTPClientTests {
	let config = CouchDBClient.Config(
		couchProtocol: .http,
		couchHost: "127.0.0.1",
		couchPort: 5984,
		userName: "admin",
		userPassword: (ProcessInfo.processInfo.environment["COUCHDB_PASS"] ?? ""),
		requestsTimeout: 30
	)

	@Test("Test buildUrl method")
	func buildUrl() async {
		let couchDBClient = CouchDBClient(config: config)
		let expectedUrl = "http://127.0.0.1:5984?key=testKey"
		let url = await couchDBClient.buildUrl(
			path: "",
			query: [
				URLQueryItem(name: "key", value: "testKey")
			])
		#expect(url == expectedUrl)
	}

	@Test("Provide own HTTPClient")
	func provide_HTTPClient() async throws {
		let httpClient = HTTPClient()
		let couchDBClient = CouchDBClient(config: config, httpClient: httpClient)

		let httpClientProvided = try #require(await couchDBClient.httpClient)

		let httpClientCreatedIfNeed = await couchDBClient.createHTTPClientIfNeed()
		#expect(httpClientProvided === httpClientCreatedIfNeed)
		#expect(httpClientProvided === httpClient)

		try await httpClient.shutdown()
	}

	@Test("HTTPClient shutdown")
	func shutdown() async throws {
		let client = CouchDBClient(
			config: config,
			httpClient: HTTPClient()
		)
		try await client.shutdown()
	}
}
