//
//  couchdb_vapor.swift
//  couchdb-swift
//
//  Created by Sergey Armodin on 06/03/2019.
//

import Foundation

import NIO
import NIOHTTP1
import AsyncHTTPClient

/// A CouchDB client actor with methods using Swift Concurrency.
public actor CouchDBClient {
	/// A configuration model for CouchDB client setup.
	/// This structure is used to define the necessary parameters for connecting to a CouchDB database.
	/// It conforms to the `Sendable` protocol for thread safety during concurrent operations.
	public struct Config: Sendable {
		/// The protocol used for CouchDB communication (e.g., HTTP or HTTPS).
		let couchProtocol: CouchDBProtocol

		/// The hostname or IP address of the CouchDB server.
		let couchHost: String

		/// The port number used for CouchDB communication.
		let couchPort: Int

		/// The username for CouchDB authentication.
		let userName: String

		/// The password for CouchDB authentication.
		let userPassword: String

		/// The timeout duration for CouchDB requests, specified in seconds.
		let requestsTimeout: Int64

		/// Initializes a new `Config` instance with default values for certain parameters.
		/// - Parameters:
		///   - couchProtocol: The communication protocol, defaulting to `.http`.
		///   - couchHost: The hostname or IP address, defaulting to `"127.0.0.1"`.
		///   - couchPort: The port number, defaulting to `5984`.
		///   - userName: The username for authentication (required).
		///   - userPassword: The password for authentication (required).
		///   - requestsTimeout: The timeout duration in seconds, defaulting to `30`.
		public init(
			couchProtocol: CouchDBClient.CouchDBProtocol = .http,
			couchHost: String = "127.0.0.1",
			couchPort: Int = 5984,
			userName: String,
			userPassword: String = ProcessInfo.processInfo.environment["COUCHDB_PASS"] ?? "",
			requestsTimeout: Int64 = 30
		) {
			self.couchProtocol = couchProtocol
			self.couchHost = couchHost
			self.couchPort = couchPort
			self.userName = userName
			self.userPassword = userPassword
			self.requestsTimeout = requestsTimeout
		}
	}

	/// An enumeration representing the available communication protocols for CouchDB.
	/// This enum conforms to `String` for raw value representation and `Sendable` for thread safety.
	public enum CouchDBProtocol: String, Sendable {
		/// HTTP protocol for CouchDB communication.
		case http

		/// HTTPS protocol for CouchDB communication, providing secure communication.
		case https
	}

	// MARK: - Public properties

	/// Flag if authorized in CouchDB.
	public var isAuthorized: Bool { authData?.ok ?? false }

	// MARK: - Private properties
	/// Requests protocol.
	private let couchProtocol: CouchDBProtocol
	/// Host.
	private let couchHost: String
	/// Port.
	private let couchPort: Int
	/// Session cookie for requests that need authorization.
	internal var sessionCookie: String?
	/// Session cookie as Cookie struct.
	internal var sessionCookieExpires: Date?
	/// CouchDB user name.
	private let userName: String
	/// You can set a timeout for requests in seconds. Default value is 30.
	private var requestsTimeout: Int64 = 30
	/// CouchDB user password.
	private let userPassword: String
	/// Authorization response from CouchDB.
	private var authData: CreateSessionResponse?
	/// HTTP client
	internal let httpClient: HTTPClient?

	// MARK: - Initializer

	/// Initializes a new instance of the CouchDB client using the provided configuration.
	///
	/// This initializer sets up the client with connection parameters and securely handles the user password,
	/// supporting environment variable fallback for sensitive data. It allows for optional customization of the
	/// connection parameters such as protocol, host, and port.
	///
	/// - Parameters:
	///   - config: A `CouchDBClient.Config` instance containing the configuration details, including protocol, host, port, username, and password.
	///   - httpClient: An optional `HTTPClient` instance. If not provided, a shared instance will be used.
	///
	/// ### Example Usage:
	/// ```swift
	/// // Create a configuration:
	/// let config = CouchDBClient.Config(
	///     couchProtocol: .http,
	///     couchHost: "127.0.0.1",
	///     couchPort: 5984,
	///     userName: "user",
	///     userPassword: "myPassword",
	///     requestsTimeout: 30
	/// )
	///
	/// // Create a client instance:
	/// let couchDBClient = CouchDBClient(config: config)
	/// ```
	///
	/// If you prefer not to include your password in the code, you can pass the `COUCHDB_PASS` environment variable
	/// in your command line. For example:
	/// ```bash
	/// COUCHDB_PASS=myPassword /path/.build/x86_64-unknown-linux-gnu/release/Run
	/// ```
	/// In this case, you can omit the `userPassword` parameter in the configuration:
	/// ```swift
	/// let config = CouchDBClient.Config(
	///     userName: "user"
	/// )
	/// let couchDBClient = CouchDBClient(config: config)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible at the specified `couchHost` and `couchPort`
	/// before attempting to connect.
	public init(config: CouchDBClient.Config, httpClient: HTTPClient? = nil) {
		self.couchProtocol = config.couchProtocol
		self.couchHost = config.couchHost
		self.couchPort = config.couchPort
		self.userName = config.userName
		self.userPassword = config.userPassword
		self.requestsTimeout = config.requestsTimeout
		self.httpClient = httpClient
	}

	/// Shuts down the HTTP client used by the CouchDB client.
	///
	/// This asynchronous function ensures that the `HTTPClient` instance is properly shut down,
	/// releasing any resources it holds. It is important to call this method when the `CouchDBClient`
	/// is no longer needed to avoid resource leaks.
	///
	/// - Throws: An error if the shutdown process fails.
	public func shutdown() async throws {
		try await httpClient?.shutdown()
	}

	// MARK: - Public methods

	/// Retrieves a list of all database names from the CouchDB server.
	///
	/// This asynchronous function sends a `GET` request to the CouchDB server to fetch the names of all databases.
	/// It supports using a custom NIO `EventLoopGroup` for network operations.
	///
	/// - Parameter eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///   If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: An array of `String` containing the names of all databases available on the server.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or the returned JSON cannot be decoded into `[String]`.
	///
	/// ### Example Usage:
	/// ```swift
	/// let dbNames = try await couchDBClient.getAllDBs()
	/// print("Available databases: \(dbNames)")
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle any thrown errors appropriately, particularly authentication-related issues.

	public func getAllDBs(eventLoopGroup: EventLoopGroup? = nil) async throws -> [String] {
		let url = buildUrl(path: "/_all_dbs")
		let request = try buildRequest(fromUrl: url, withMethod: .GET)
		let data = try await authorizedData(request, eventLoopGroup: eventLoopGroup)
		return try JSONDecoder().decode([String].self, from: data)
	}

	/// Checks if a database exists on the CouchDB server.
	///
	/// This asynchronous function sends a `HEAD` request to the CouchDB server to verify the existence of a specified database.
	/// It supports using a custom NIO's `EventLoopGroup` for managing network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database to check for existence.
	///   - eventLoopGroup: An optional `EventLoopGroup` used for executing network requests.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: A `Bool` indicating whether the database exists (`true`) or not (`false`).
	/// - Throws: A `CouchDBClientError` if authentication fails, plus any underlying request execution error.
	///
	/// ### Function Workflow:
	/// 1. Constructs a `HEAD` request for the provided database name.
	/// 2. Executes the request using an authenticated client, optionally scoped to the provided `EventLoopGroup`.
	/// 3. Returns `true` when the response status is `.ok`, and `false` otherwise.
	///
	/// ### Example Usage:
	/// ```swift
	/// let doesExist = try await couchDBClient.dbExists("myDatabase")
	/// print("Database exists: \(doesExist)")
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially authentication-related issues.

	public func dbExists(_ dbName: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> Bool {
		let url = buildUrl(path: "/" + dbName)
		let request = try buildRequest(fromUrl: url, withMethod: .HEAD)
		let response = try await authorizedResponse(request, eventLoopGroup: eventLoopGroup)
		return response.status == .ok
	}

	/// Creates a new database on the CouchDB server.
	///
	/// This method sends a `PUT` request for the specified database name and decodes CouchDB's update response.
	/// It supports using a custom `EventLoopGroup` for network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database to be created.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network requests.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: An `UpdateDBResponse` object that contains the result of the database creation operation.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or CouchDB returns an error payload that maps to `.insertError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// ```swift
	/// let creationResult = try await couchDBClient.createDB("newDatabase")
	/// print("Database creation successful: \(creationResult.ok)")
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle any thrown errors appropriately, including authentication issues and potential conflicts if the database already exists.
	@discardableResult public func createDB(_ dbName: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> UpdateDBResponse {
		let url = buildUrl(path: "/\(dbName)")
		let request = try self.buildRequest(fromUrl: url, withMethod: .PUT)
		return try await authorizedDecoded(
			UpdateDBResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.insertError(error: $0) }
		)
	}

	/// Deletes a database from the CouchDB server.
	///
	/// This method sends a `DELETE` request for the specified database and decodes CouchDB's update response.
	/// It supports using a custom `EventLoopGroup` for managing network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database to delete.
	///   - eventLoopGroup: An optional `EventLoopGroup` used for executing network operations.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: An `UpdateDBResponse` object that contains the result of the database deletion operation.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or CouchDB returns an error payload that maps to `.deleteError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// ```swift
	/// let deletionResult = try await couchDBClient.deleteDB("obsoleteDatabase")
	/// print("Database deletion successful: \(deletionResult.ok)")
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially authentication issues and conflicts if the database does not exist.
	@discardableResult public func deleteDB(_ dbName: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> UpdateDBResponse {
		let url = buildUrl(path: "/\(dbName)")
		let request = try self.buildRequest(fromUrl: url, withMethod: .DELETE)
		return try await authorizedDecoded(
			UpdateDBResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.deleteError(error: $0) }
		)
	}

	/// Fetches raw data from a specified database and URI on the CouchDB server.
	///
	/// This method sends a `GET` request to a database resource and returns the raw `HTTPClientResponse`.
	/// Before returning, it buffers the response body in memory so callers can inspect or decode it without reissuing the request.
	/// It supports using a custom `EventLoopGroup` and optional query parameters.
	///
	/// - Parameters:
	///   - dbName: The name of the database from which to fetch data.
	///   - uri: The URI path of the specific resource or endpoint within the database (e.g., document ID or view path).
	///   - queryItems: An optional array of `URLQueryItem` to specify query parameters for the request.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: An `HTTPClientResponse` whose body has already been buffered in memory.
	/// - Throws: A `CouchDBClientError` if authentication fails, the resource is not found,
	///   or the response body is missing.
	///
	/// ### Example Usage:
	/// #### Define Your Document Data Model
	/// ```swift
	/// struct ExpectedDoc: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = NSUUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Fetch a Raw Response:
	/// ```swift
	/// let response = try await couchDBClient.get(
	///     fromDB: "myDatabase",
	///     uri: "documentID"
	/// )
	/// print(response.status)
	/// ```
	///
	/// #### Fetch Data for Manual Decoding:
	/// ```swift
	/// let response = try await couchDBClient.get(
	///     fromDB: "myDatabase",
	///     uri: "_design/all/_view/by_url",
	///     queryItems: [
	///         URLQueryItem(name: "key", value: "\"\(url)\"")
	///     ]
	/// )
	/// print(response.status)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible. Handle thrown errors appropriately, especially for authentication issues.
	public func get(fromDB dbName: String, uri: String, queryItems: [URLQueryItem]? = nil, eventLoopGroup: EventLoopGroup? = nil) async throws -> HTTPClientResponse {
		let result = try await performGetRequest(
			fromDB: dbName,
			uri: uri,
			queryItems: queryItems,
			eventLoopGroup: eventLoopGroup
		)
		var response = result.response
		response.body = .bytes(result.bytes)
		return response
	}

	/// Retrieves and decodes a document of a specified type from a database on the CouchDB server.
	///
	/// This generic method fetches a document from a specific database resource and decodes the buffered response body
	/// into the requested `CouchDBRepresentable` type. It supports custom query parameters, a configurable date decoding strategy,
	/// and an optional custom `EventLoopGroup`.
	///
	/// - Parameters:
	///   - dbName: The name of the database from which to fetch the document.
	///   - uri: The URI path of the specific document within the database (e.g., a document ID).
	///   - queryItems: An optional array of `URLQueryItem` to specify query parameters for the request.
	///   - dateDecodingStrategy: The date decoding strategy to use when decoding dates. Defaults to `.secondsSince1970`.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function uses a shared `HTTPClient`.
	/// - Returns: A document of type `T`, where `T` conforms to `CouchDBRepresentable`.
	/// - Throws: A `CouchDBClientError` if the resource is not found, authentication fails,
	///   the response body is missing, or CouchDB returns an error payload that maps to `.getError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// #### Define Your Document Model:
	/// ```swift
	/// struct MyDocumentType: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = UUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return MyDocumentType(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Retrieve a Document by ID:
	/// ```swift
	/// let doc: MyDocumentType = try await couchDBClient.get(
	///     fromDB: "myDatabase",
	///     uri: "documentID"
	/// )
	/// print(doc)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for authentication failures and data decoding issues.
	public func get<T: CouchDBRepresentable>(fromDB dbName: String, uri: String, queryItems: [URLQueryItem]? = nil, dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .secondsSince1970, eventLoopGroup: EventLoopGroup? = nil) async throws -> T {
		let result = try await performGetRequest(
			fromDB: dbName,
			uri: uri,
			queryItems: queryItems,
			eventLoopGroup: eventLoopGroup
		)
		var bytes = result.bytes

		guard let data = bytes.readData(length: bytes.readableBytes) else {
			throw CouchDBClientError.noData
		}

		return try decodeJSON(
			T.self,
			from: data,
			dateDecodingStrategy: dateDecodingStrategy,
			mapCouchError: { CouchDBClientError.getError(error: $0) }
		)
	}

	/// Performs a query using a selector payload and decodes the matching documents.
	///
	/// This deprecated compatibility overload accepts an arbitrary selector payload, sends it to CouchDB's `_find` endpoint,
	/// and decodes the resulting documents into the requested `CouchDBRepresentable` type.
	///
	/// - Parameters:
	///   - dbName: The name of the database in which to perform the query.
	///   - selector: A `Codable` object that defines the criteria for selecting documents.
	///   - dateDecodingStrategy: The date decoding strategy to use for decoding dates within the documents. Defaults to `.secondsSince1970`.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: An array of documents of type `T`, where `T` conforms to `CouchDBRepresentable`.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or CouchDB returns an error payload that maps to `.findError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// ```swift
	/// let selector = ["selector": ["name": "Sam"]]
	/// let documents: [MyDocumentType] = try await couchDBClient.find(
	///     inDB: "myDatabase",
	///     selector: selector
	/// )
	/// print(documents)
	/// ```
	///
	/// - Note: Prefer ``find(inDB:query:dateDecodingStrategy:eventLoopGroup:)`` for a type-safe Mango query API.
	@available(*, deprecated, message: "Use find(inDB:query:) instead")
	public func find<T: CouchDBRepresentable>(inDB dbName: String, selector: Codable, dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .secondsSince1970, eventLoopGroup: EventLoopGroup? = nil) async throws -> [T] {
		let encoder = JSONEncoder()
		let selectorData = try encoder.encode(selector)
		let requestBody: HTTPClientRequest.Body = .bytes(ByteBuffer(data: selectorData))

		let result = try await performFindRequest(
			inDB: dbName,
			body: requestBody,
			eventLoopGroup: eventLoopGroup
		)
		var bytes = result.bytes

		guard let data = bytes.readData(length: bytes.readableBytes) else {
			throw CouchDBClientError.noData
		}

		let response = try decodeJSON(
			CouchDBFindResponse<T>.self,
			from: data,
			dateDecodingStrategy: dateDecodingStrategy,
			mapCouchError: { CouchDBClientError.findError(error: $0) }
		)
		return response.docs
	}

	/// Performs a Mango query and decodes the matching documents.
	///
	/// This generic method sends a `MangoQuery` to CouchDB's `_find` endpoint and decodes the resulting documents
	/// into the requested `CouchDBRepresentable` type.
	///
	/// - Parameters:
	///   - dbName: The name of the database in which to perform the query.
	///   - query: A `MangoQuery` object that defines the criteria for selecting documents.
	///   - dateDecodingStrategy: The date decoding strategy to use for decoding dates within the documents. Defaults to `.secondsSince1970`.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function defaults to using a shared instance of `HTTPClient`.
	/// - Returns: An array of documents of type `T`, where `T` conforms to `CouchDBRepresentable`.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or CouchDB returns an error payload that maps to `.findError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// ```swift
	/// let query = MangoQuery(selector: ["name": .string("Sam")])
	/// let documents: [MyDocumentType] = try await couchDBClient.find(
	///     inDB: "myDatabase",
	///     query: query
	/// )
	/// print(documents)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for data decoding issues or query mismatches.
	public func find<T: CouchDBRepresentable>(inDB dbName: String, query: MangoQuery, dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .secondsSince1970, eventLoopGroup: EventLoopGroup? = nil) async throws -> [T] {
		let encoder = JSONEncoder()
		let queryData = try encoder.encode(query)
		let requestBody: HTTPClientRequest.Body = .bytes(ByteBuffer(data: queryData))

		let result = try await performFindRequest(
			inDB: dbName,
			body: requestBody,
			eventLoopGroup: eventLoopGroup
		)
		var bytes = result.bytes

		guard let data = bytes.readData(length: bytes.readableBytes) else {
			throw CouchDBClientError.noData
		}

		let response = try decodeJSON(
			CouchDBFindResponse<T>.self,
			from: data,
			dateDecodingStrategy: dateDecodingStrategy,
			mapCouchError: { CouchDBClientError.findError(error: $0) }
		)
		return response.docs
	}

	/// Executes a raw `_find` request against a specified database.
	///
	/// This method sends a custom request body to CouchDB's `_find` endpoint and returns the raw `HTTPClientResponse`.
	/// Before returning, it buffers the response body in memory so callers can decode it manually.
	///
	/// - Parameters:
	///   - dbName: The name of the database in which to execute the query.
	///   - body: The `HTTPClientRequest.Body` containing the encoded query to be sent to the server.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network requests.
	///     If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: An `HTTPClientResponse` whose body has already been buffered in memory.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.unauthorized`: If authentication fails.
	///
	/// ### Example Usage:
	/// #### Perform a Find Query:
	/// ```swift
	/// let selector = ["selector": ["name": "Greg"]]
	/// let bodyData = try JSONEncoder().encode(selector)
	/// let findResponse = try await couchDBClient.find(
	///     inDB: "myDatabase",
	///     body: .bytes(ByteBuffer(data: bodyData))
	/// )
	///
	/// print(findResponse.status)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially authentication-related issues.
	public func find(inDB dbName: String, body: HTTPClientRequest.Body, eventLoopGroup: EventLoopGroup? = nil) async throws -> HTTPClientResponse {
		let result = try await performFindRequest(
			inDB: dbName,
			body: body,
			eventLoopGroup: eventLoopGroup
		)
		var response = result.response
		response.body = .bytes(result.bytes)
		return response
	}

	/// Updates a document in a specified database on the CouchDB server.
	///
	/// This asynchronous function sends a `PUT` request to the CouchDB server to update a document at a given URI within a specified database.
	/// It allows the use of a custom `EventLoopGroup` for network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database containing the document to be updated.
	///   - uri: The URI path of the specific document within the database.
	///   - body: The `HTTPClientRequest.Body` containing the updated content of the document.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: A `CouchUpdateResponse` object containing the result of the update operation.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.unauthorized` if authentication fails,
	///   `.noData` if the response body cannot be read, `.conflictError(error:)` when CouchDB returns a conflict,
	///   `.updateError(error:)` when CouchDB reports a not-found or update error, and `.unknownResponse` if
	///   CouchDB returns an unexpected error payload.
	///
	/// ### Function Workflow:
	/// 1. Constructs a `PUT` request for the target document and attaches the provided body.
	/// 2. Executes the request using an authenticated client and buffers the response body.
	/// 3. Throws `.conflictError(error:)` when CouchDB responds with `409 Conflict`.
	/// 4. Throws `.updateError(error:)` when CouchDB responds with `404 Not Found`.
	/// 5. Decodes and returns `CouchUpdateResponse` for successful responses.
	///
	/// ### Example Usage:
	/// #### Define Your Document Model:
	/// ```swift
	/// struct ExpectedDoc: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = UUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Update a Document:
	/// ```swift
	/// // Fetch the document by ID
	/// var response = try await couchDBClient.get(
	///     fromDB: "myDatabase",
	///     uri: "documentID"
	/// )
	///
	/// // Parse the document
	/// let bytes = response.body!.readBytes(length: response.body!.readableBytes)!
	/// var doc = try JSONDecoder().decode(
	///     ExpectedDoc.self,
	///     from: Data(bytes)
	/// )
	///
	/// // Modify the document
	/// doc.name = "Updated name"
	///
	/// // Encode the updated document into JSON
	/// let data = try JSONEncoder().encode(doc)
	/// let body: HTTPClientRequest.Body = .bytes(ByteBuffer(data: data))
	///
	/// // Send the update request
	/// let updateResponse = try await couchDBClient.update(
	///     dbName: "myDatabase",
	///     uri: doc._id,
	///     body: body
	/// )
	///
	/// print(updateResponse)
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for authentication or data-related issues.
	public func update(dbName: String, uri: String, body: HTTPClientRequest.Body, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		let url = buildUrl(path: "/" + dbName + "/" + uri)
		var request = try buildRequest(fromUrl: url, withMethod: .PUT)
		request.body = body
		let result = try await authorizedResponseAndData(request, eventLoopGroup: eventLoopGroup)

		if result.response.status == .conflict {
			throw CouchDBClientError.conflictError(error: try decodeCouchError(from: result.data))
		}

		if result.response.status == .notFound {
			throw CouchDBClientError.updateError(error: try decodeCouchError(from: result.data))
		}

		return try decodeJSON(
			CouchUpdateResponse.self,
			from: result.data,
			mapCouchError: { CouchDBClientError.updateError(error: $0) }
		)
	}

	/// Updates a document conforming to `CouchDBRepresentable` in a specified database on the CouchDB server.
	///
	/// This asynchronous generic function updates a document in the specified database. The document must conform to the
	/// `CouchDBRepresentable` protocol, which requires `_id` and `_rev` properties. The function supports using a custom
	/// `EventLoopGroup` for network operations and allows a configurable date encoding strategy.
	///
	/// - Parameters:
	///   - dbName: The name of the database containing the document to be updated.
	///   - doc: A reference to the document of type `T` that will be updated. The document must have valid `_id` and `_rev` properties.
	///   - dateEncodingStrategy: The date encoding strategy to use when encoding dates in the document. Defaults to `.secondsSince1970`.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	///     If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: The updated document of type `T`, with its `_rev` property reflecting the new revision token.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.revMissing` if the document's `_rev` is missing or empty, `.unknownResponse` if the server's response is not successful or unexpected.
	///
	/// ### Function Workflow:
	/// 1. Verifies that the document has a valid `_rev` property.
	/// 2. Encodes the document using a `JSONEncoder` configured with the specified date encoding strategy.
	/// 3. Constructs the request body using the encoded document data.
	/// 4. Sends a `PUT` request to update the document in the specified database.
	/// 5. Processes the server's response and throws an error if the operation fails.
	/// 6. Returns the document updated with the new `_rev` value from CouchDB.
	///
	/// ### Example Usage:
	/// #### Define Your Document Model:
	/// ```swift
	/// struct ExpectedDoc: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = UUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Retrieve and Update a Document:
	/// ```swift
	/// var doc: ExpectedDoc = try await couchDBClient.get(
	///     fromDB: "myDatabase",
	///     uri: "documentID"
	/// )
	///
	/// // Modify the document
	/// doc.name = "Updated name"
	///
	/// // Update the document in the database
	/// doc = try await couchDBClient.update(
	///     dbName: "myDatabase",
	///     doc: doc
	/// )
	///
	/// print(doc) // Document now includes the updated name and a new `_rev` value
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for document updates and server responses.
	public func update<T: CouchDBRepresentable>(dbName: String, doc: T, dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .secondsSince1970, eventLoopGroup: EventLoopGroup? = nil) async throws -> T {
		guard doc._rev?.isEmpty == false else { throw CouchDBClientError.revMissing }

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = dateEncodingStrategy
		let encodedData = try encoder.encode(doc)

		let body: HTTPClientRequest.Body = .bytes(ByteBuffer(data: encodedData))

		let updateResponse = try await update(
			dbName: dbName,
			uri: doc._id,
			body: body,
			eventLoopGroup: eventLoopGroup
		)

		guard updateResponse.ok == true else {
			throw CouchDBClientError.unknownResponse
		}

		return doc.updateRevision(updateResponse.rev)
	}

	/// Inserts a raw document body into a specified database on the CouchDB server.
	///
	/// This method sends a `POST` request with a caller-provided request body and decodes CouchDB's update response.
	/// It allows the use of a custom `EventLoopGroup` for managing network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database into which the new document will be inserted.
	///   - body: The `HTTPClientRequest.Body` containing the JSON-encoded content of the new document.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network requests.
	///     If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: A `CouchUpdateResponse` object containing the result of the insertion operation.
	/// - Throws: A `CouchDBClientError` if authentication fails, the response body is missing,
	///   or CouchDB returns an error payload that maps to `.insertError(error:)`.
	///   Non-CouchDB decoding failures are propagated as the underlying decoding error.
	///
	/// ### Example Usage:
	/// #### Define Your Document Model:
	/// ```swift
	/// struct ExpectedDoc: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = UUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Create and Insert a Document:
	/// ```swift
	/// let testDoc = ExpectedDoc(name: "My name")
	/// let encodedData = try JSONEncoder().encode(testDoc)
	///
	/// let body: HTTPClientRequest.Body = .bytes(ByteBuffer(data: encodedData))
	///
	/// let response = try await couchDBClient.insert(
	///     dbName: "myDatabase",
	///     body: body
	/// )
	///
	/// print(response) // Response includes operation status and revision token
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for authentication issues or unexpected server responses.
	public func insert(dbName: String, body: HTTPClientRequest.Body, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		let url = buildUrl(path: "/\(dbName)")
		var request = try self.buildRequest(fromUrl: url, withMethod: .POST)
		request.body = body
		return try await authorizedDecoded(
			CouchUpdateResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.insertError(error: $0) }
		)
	}

	/// Inserts a new document conforming to `CouchDBRepresentable` into a specified database on the CouchDB server.
	///
	/// This asynchronous generic function inserts a new document into the specified database. The document must conform to the
	/// `CouchDBRepresentable` protocol, which requires `_id` and `_rev` properties. It supports using a custom `EventLoopGroup` for
	/// network operations and allows a configurable date encoding strategy.
	///
	/// - Parameters:
	///   - dbName: The name of the database where the new document will be inserted.
	///   - doc: The document of type `T` to be inserted. The type `T` must conform to `CouchDBRepresentable`.
	///   - dateEncodingStrategy: The strategy used for encoding dates within the document. Defaults to `.secondsSince1970`.
	///   - eventLoopGroup: An optional `EventLoopGroup` for managing network operations. If not provided, a shared instance of `HTTPClient` is used.
	/// - Returns: The newly inserted document of type `T`, updated with its new `_rev` property.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.unknownResponse` if the server's response is unexpected or unsuccessful.
	///
	/// ### Function Workflow:
	/// 1. Encodes the document using a `JSONEncoder` configured with the specified date encoding strategy.
	/// 2. Prepares a `POST` request with the encoded document as the request body.
	/// 3. Sends the request to the CouchDB server and processes the response.
	/// 4. Returns the document updated with the new `_rev` from CouchDB.
	/// 5. Throws an error if the server's response is unexpected or unsuccessful.
	///
	/// ### Example Usage:
	/// #### Define Your Document Model:
	/// ```swift
	/// struct ExpectedDoc: CouchDBRepresentable {
	///     var name: String
	///     var _id: String = UUID().uuidString
	///     var _rev: String?
	///
	///     func updateRevision(_ newRevision: String) -> Self {
	///         return ExpectedDoc(name: name, _id: _id, _rev: newRevision)
	///     }
	/// }
	/// ```
	///
	/// #### Insert a New Document:
	/// ```swift
	/// var testDoc = ExpectedDoc(name: "My name")
	///
	/// testDoc = try await couchDBClient.insert(
	///     dbName: "myDatabase",
	///     doc: testDoc
	/// )
	///
	/// print(testDoc) // Document now contains its assigned `_id` and `_rev`.
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is operational and accessible before using this function.
	///   Handle thrown errors appropriately, especially for unexpected server responses.
	public func insert<T: CouchDBRepresentable>(dbName: String, doc: T, dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .secondsSince1970, eventLoopGroup: EventLoopGroup? = nil) async throws -> T {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = dateEncodingStrategy
		let insertEncodeData = try encoder.encode(doc)

		let body: HTTPClientRequest.Body = .bytes(ByteBuffer(data: insertEncodeData))

		let insertResponse = try await insert(
			dbName: dbName,
			body: body,
			eventLoopGroup: eventLoopGroup
		)

		guard insertResponse.ok == true else {
			throw CouchDBClientError.unknownResponse
		}

		return doc.updateRevision(insertResponse.rev)
	}

	/// Deletes a document from a specified database on the CouchDB server.
	///
	/// This asynchronous function sends a `DELETE` request to the CouchDB server to remove a document identified by its URI and revision number.
	/// It supports using a custom `EventLoopGroup` for managing network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database from which the document will be deleted.
	///   - uri: The URI path of the specific document within the database.
	///   - rev: The revision number of the document to be deleted.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network requests.
	///     If not provided, the function uses a shared instance of `HTTPClient`.
	/// - Returns: A `CouchUpdateResponse` object containing the result of the delete operation.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.unauthorized` if authentication fails,
	///   `.deleteError(error:)` when CouchDB reports the document as missing, or `.unknownResponse` when CouchDB
	///   returns an unexpected error payload.
	///
	/// ### Function Workflow:
	/// 1. Constructs a `DELETE` request using the database name, document URI, and revision query parameter.
	/// 2. Executes the request using an authenticated client and buffers the response body.
	/// 3. Throws `.deleteError(error:)` when CouchDB responds with `404 Not Found`.
	/// 4. Decodes and returns `CouchUpdateResponse` for successful responses.
	/// 5. Returns `CouchUpdateResponse(ok: false, id: "", rev: "")` when the response body is empty.
	///
	/// ### Example Usage:
	/// ```swift
	/// let response = try await couchDBClient.delete(
	///     fromDb: "myDatabase",
	///     uri: "documentID",
	///     rev: "documentRevision"
	/// )
	/// print(response) // Response includes operation status and revision token
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for authentication issues or unexpected server responses.
	public func delete(fromDb dbName: String, uri: String, rev: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		let url = buildUrl(
			path: "/" + dbName + "/" + uri,
			query: [
				URLQueryItem(name: "rev", value: rev)
			]
		)
		let request = try self.buildRequest(fromUrl: url, withMethod: .DELETE)
		let result = try await authorizedBytes(request, eventLoopGroup: eventLoopGroup)
		var bytes = result.bytes

		guard let data = bytes.readData(length: bytes.readableBytes) else {
			return CouchUpdateResponse(ok: false, id: "", rev: "")
		}

		if result.response.status == .notFound {
			throw CouchDBClientError.deleteError(error: try decodeCouchError(from: data))
		}

		return try JSONDecoder().decode(CouchUpdateResponse.self, from: data)
	}

	/// Deletes a document conforming to `CouchDBRepresentable` from a specified database on the CouchDB server.
	///
	/// This asynchronous function removes a document from the specified database. The document must conform to the
	/// `CouchDBRepresentable` protocol, which includes the `_id` and `_rev` properties required for the deletion process.
	/// It supports using a custom `EventLoopGroup` for network operations.
	///
	/// - Parameters:
	///   - dbName: The name of the database from which the document will be deleted.
	///   - doc: The document of type `CouchDBRepresentable` to be deleted.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network requests.
	///     If not provided, a shared instance of `HTTPClient` is used.
	/// - Returns: A `CouchUpdateResponse` object containing the result of the delete operation.
	/// - Throws: A `CouchDBClientError` if the operation fails, including: `.revMissing` if the document's `_rev` property is missing.
	///
	/// ### Function Workflow:
	/// 1. Validates the presence of the document's `_rev` property.
	/// 2. Delegates to `delete(fromDb:uri:rev:eventLoopGroup:)` using the document's `_id` and `_rev`.
	///
	/// ### Example Usage:
	/// ```swift
	/// let deleteResult = try await couchDBClient.delete(
	///     fromDb: "myDatabase",
	///     doc: myDocument
	/// )
	/// print(deleteResult) // Response includes operation status and revision token
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is operational and accessible before using this function.
	///   Handle thrown errors appropriately, especially for missing document properties or unexpected server responses.
	public func delete(fromDb dbName: String, doc: CouchDBRepresentable, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		guard let rev = doc._rev else { throw CouchDBClientError.revMissing }

		return try await delete(fromDb: dbName, uri: doc._id, rev: rev, eventLoopGroup: eventLoopGroup)
	}

	/// Lists all Mango indexes in a specified database.
	///
	/// - Parameters:
	///   - dbName: The name of the database.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	/// - Returns: A `MangoIndexesResponse` containing the list of indexes.
	/// - Throws: A `CouchDBClientError` if the operation fails.
	///
	/// ### Example Usage:
	/// ```swift
	/// // List all Mango indexes in a database
	/// let indexesResponse = try await couchDBClient.listIndexes(inDB: "myDatabase")
	/// print(indexesResponse.indexes)
	/// ```
	public func listIndexes(inDB dbName: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> MangoIndexesResponse {
		let url = buildUrl(path: "/\(dbName)/_index")
		let request = try buildRequest(fromUrl: url, withMethod: .GET)
		return try await authorizedDecoded(
			MangoIndexesResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.getError(error: $0) }
		)
	}

	/// Creates a new Mango index in a specified database.
	///
	/// - Parameters:
	///   - dbName: The name of the database.
	///   - index: The `MangoIndex` to create.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	/// - Returns: A `MangoCreateIndexResponse` indicating the result of the operation.
	/// - Throws: A `CouchDBClientError` if the operation fails.
	///
	/// ### Example Usage:
	/// ```swift
	/// // Define a Mango index
	/// let index = MangoIndex(
	///     fields: ["name"],
	///     name: "name-index",
	///     type: "json"
	/// )
	/// // Create the index in the database
	/// let response = try await couchDBClient.createIndex(inDB: "myDatabase", index: index)
	/// print(response.result) // Should print "created" or "exists"
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for index creation conflicts or server issues.
	public func createIndex(inDB dbName: String, index: MangoIndex, eventLoopGroup: EventLoopGroup? = nil) async throws -> MangoCreateIndexResponse {
		let url = buildUrl(path: "/\(dbName)/_index")
		let encoder = JSONEncoder()
		let indexData = try encoder.encode(index)
		let requestBody: HTTPClientRequest.Body = .bytes(ByteBuffer(data: indexData))

		var request = try buildRequest(fromUrl: url, withMethod: .POST)
		request.body = requestBody

		return try await authorizedDecoded(
			MangoCreateIndexResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.insertError(error: $0) }
		)
	}

	/// Explains a Mango query in a specified database.
	///
	/// - Parameters:
	///   - dbName: The name of the database.
	///   - query: The `MangoQuery` to explain.
	///   - eventLoopGroup: An optional `EventLoopGroup` for executing network operations.
	/// - Returns: A `MangoExplainResponse` containing the query execution plan.
	/// - Throws: A `CouchDBClientError` if the operation fails.
	///
	/// ### Example Usage:
	/// ```swift
	/// // Define a Mango query
	/// let query = MangoQuery(selector: ["name": .string("Sam")])
	/// // Explain the query execution plan
	/// let explainResponse = try await couchDBClient.explain(inDB: "myDatabase", query: query)
	/// print(explainResponse.index) // Shows which index will be used
	/// print(explainResponse.selector) // Shows the query selector
	/// ```
	///
	/// - Note: Ensure that the CouchDB server is running and accessible before calling this function.
	///   Handle thrown errors appropriately, especially for query or index issues.
	public func explain(inDB dbName: String, query: MangoQuery, eventLoopGroup: EventLoopGroup? = nil) async throws -> MangoExplainResponse {
		let url = buildUrl(path: "/\(dbName)/_explain")
		let encoder = JSONEncoder()
		let queryData = try encoder.encode(query)
		let requestBody: HTTPClientRequest.Body = .bytes(ByteBuffer(data: queryData))

		var request = try buildRequest(fromUrl: url, withMethod: .POST)
		request.body = requestBody

		return try await authorizedDecoded(
			MangoExplainResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.getError(error: $0) }
		)
	}

	/// Uploads an attachment to a CouchDB document.
	///
	/// - Parameters:
	///   - dbName: The database name.
	///   - docId: The document ID.
	///   - attachmentName: The name of the attachment.
	///   - data: The binary data to upload.
	///   - contentType: The MIME type of the attachment.
	///   - rev: The current document revision.
	///   - eventLoopGroup: Optional EventLoopGroup for network operations.
	/// - Returns: A CouchUpdateResponse with the new revision.
	/// - Throws: CouchDBClientError on failure.
	///
	/// ### Example Usage:
	/// ```swift
	/// let response = try await couchDBClient.uploadAttachment(
	///     dbName: "myDatabase",
	///     docId: "docid",
	///     attachmentName: "image.png",
	///     data: imageData,
	///     contentType: "image/png",
	///     rev: "currentRev"
	/// )
	/// print("Attachment uploaded, new revision: \(response.rev)")
	/// ```
	public func uploadAttachment(dbName: String, docId: String, attachmentName: String, data: Data, contentType: String, rev: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		let url = buildUrl(path: "/\(dbName)/\(docId)/\(attachmentName)", query: [URLQueryItem(name: "rev", value: rev)])
		var request = try buildRequest(fromUrl: url, withMethod: .PUT)
		request.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		request.body = .bytes(ByteBuffer(data: data))
		return try await authorizedDecoded(
			CouchUpdateResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.updateError(error: $0) }
		)
	}

	/// Downloads an attachment from a CouchDB document.
	///
	/// - Parameters:
	///   - dbName: The database name.
	///   - docId: The document ID.
	///   - attachmentName: The name of the attachment.
	///   - eventLoopGroup: Optional EventLoopGroup for network operations.
	/// - Returns: The binary data of the attachment.
	/// - Throws: CouchDBClientError on failure.
	///
	/// ### Example Usage:
	/// ```swift
	/// let attachmentData = try await couchDBClient.downloadAttachment(
	///     dbName: "myDatabase",
	///     docId: "docid",
	///     attachmentName: "image.png"
	/// )
	/// print("Downloaded attachment, size: \(attachmentData.count) bytes")
	/// ```
	public func downloadAttachment(dbName: String, docId: String, attachmentName: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> Data {
		let url = buildUrl(path: "/\(dbName)/\(docId)/\(attachmentName)")
		let request = try buildRequest(fromUrl: url, withMethod: .GET)
		return try await authorizedData(request, eventLoopGroup: eventLoopGroup)
	}

	/// Deletes an attachment from a CouchDB document.
	///
	/// - Parameters:
	///   - dbName: The database name.
	///   - docId: The document ID.
	///   - attachmentName: The name of the attachment.
	///   - rev: The current document revision.
	///   - eventLoopGroup: Optional EventLoopGroup for network operations.
	/// - Returns: A CouchUpdateResponse with the new revision.
	/// - Throws: CouchDBClientError on failure.
	///
	/// ### Example Usage:
	/// ```swift
	/// let deleteResponse = try await couchDBClient.deleteAttachment(
	///     dbName: "myDatabase",
	///     docId: "docid",
	///     attachmentName: "image.png",
	///     rev: "currentRev"
	/// )
	/// print("Attachment deleted, new revision: \(deleteResponse.rev)")
	/// ```
	public func deleteAttachment(dbName: String, docId: String, attachmentName: String, rev: String, eventLoopGroup: EventLoopGroup? = nil) async throws -> CouchUpdateResponse {
		let url = buildUrl(path: "/\(dbName)/\(docId)/\(attachmentName)", query: [URLQueryItem(name: "rev", value: rev)])
		let request = try buildRequest(fromUrl: url, withMethod: .DELETE)
		return try await authorizedDecoded(
			CouchUpdateResponse.self,
			request: request,
			eventLoopGroup: eventLoopGroup,
			mapCouchError: { CouchDBClientError.deleteError(error: $0) }
		)
	}
}

// MARK: - Private methods
internal extension CouchDBClient {
	/// Build URL string.
	/// - Parameters:
	///   - path: Path.
	///   - query: URL query.
	/// - Returns: URL string.
	func buildUrl(path: String, query: [URLQueryItem] = []) -> String {
		var components = URLComponents()
		components.scheme = couchProtocol.rawValue
		components.host = couchHost
		components.port = couchPort
		components.path = path

		components.queryItems = query.isEmpty ? nil : query

		if components.url?.absoluteString == nil {
			assertionFailure("url should not be nil")
		}
		return components.url?.absoluteString ?? ""
	}

	/// Create an HTTPClient instance if not provided during init method.
	/// - Parameter eventLoopGroup: NIO's EventLoopGroup object. NIO's shared will be used if nil value provided.
	/// - Returns: HTTP client.
	func createHTTPClientIfNeed(eventLoopGroup: EventLoopGroup? = nil) -> HTTPClient {
		if let httpClient {
			return httpClient
		}

		if let eventLoopGroup = eventLoopGroup {
			return HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
		} else {
			return HTTPClient.shared
		}
	}

	func shutdownHTTPClientIfNeeded(_ httpClient: HTTPClient, eventLoopGroup: EventLoopGroup?) {
		guard eventLoopGroup != nil else {
			return
		}

		DispatchQueue.main.async {
			try? httpClient.syncShutdown()
		}
	}

	func withPreparedClient<T: Sendable>(
		eventLoopGroup: EventLoopGroup? = nil,
		_ operation: @Sendable (HTTPClient) async throws -> T
	) async throws -> T {
		try await authIfNeed(eventLoopGroup: eventLoopGroup)

		let httpClient = createHTTPClientIfNeed(eventLoopGroup: eventLoopGroup)
		defer {
			shutdownHTTPClientIfNeeded(httpClient, eventLoopGroup: eventLoopGroup)
		}

		return try await operation(httpClient)
	}

	func executeAuthorizedRequest(
		_ request: HTTPClientRequest,
		using httpClient: HTTPClient
	) async throws -> HTTPClientResponse {
		var request = request
		if let sessionCookie {
			request.headers.replaceOrAdd(name: "Cookie", value: sessionCookie)
		}
		let response = try await httpClient.execute(request, timeout: .seconds(requestsTimeout))
		if response.status == .unauthorized {
			throw CouchDBClientError.unauthorized
		}
		return response
	}

	func authorizedResponse(
		_ request: HTTPClientRequest,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> HTTPClientResponse {
		try await withPreparedClient(eventLoopGroup: eventLoopGroup) { httpClient in
			try await executeAuthorizedRequest(request, using: httpClient)
		}
	}

	func authorizedBytes(
		_ request: HTTPClientRequest,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> (response: HTTPClientResponse, bytes: ByteBuffer) {
		try await withPreparedClient(eventLoopGroup: eventLoopGroup) { httpClient in
			let response = try await executeAuthorizedRequest(request, using: httpClient)
			let bytes = try await collectResponseBytes(from: response)
			return (response, bytes)
		}
	}

	func authorizedResponseAndData(
		_ request: HTTPClientRequest,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> (response: HTTPClientResponse, data: Data) {
		try await withPreparedClient(eventLoopGroup: eventLoopGroup) { httpClient in
			let response = try await executeAuthorizedRequest(request, using: httpClient)
			let data = try await collectResponseData(from: response)
			return (response, data)
		}
	}

	func authorizedData(
		_ request: HTTPClientRequest,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> Data {
		let result = try await authorizedResponseAndData(
			request,
			eventLoopGroup: eventLoopGroup
		)
		return result.data
	}

	func authorizedDecoded<T: Decodable>(
		_ type: T.Type,
		request: HTTPClientRequest,
		eventLoopGroup: EventLoopGroup? = nil,
		dateDecodingStrategy: JSONDecoder.DateDecodingStrategy? = nil,
		mapCouchError: (CouchDBError) -> CouchDBClientError
	) async throws -> T {
		let data = try await authorizedData(request, eventLoopGroup: eventLoopGroup)
		return try decodeJSON(
			type,
			from: data,
			dateDecodingStrategy: dateDecodingStrategy,
			mapCouchError: mapCouchError
		)
	}

	/// Get authorization cookie in didn't yet. This cookie will be added automatically to requests that require authorization.
	/// API reference: https://docs.couchdb.org/en/stable/api/server/authn.html#session
	/// - Parameter eventLoopGroup: NIO's EventLoopGroup object. NIO's shared will be used if nil value provided.
	/// - Returns: Authorization response.
	@discardableResult
	func authIfNeed(eventLoopGroup: EventLoopGroup? = nil) async throws -> CreateSessionResponse? {
		// already authorized
		if let authData = authData, let sessionCookieExpires = sessionCookieExpires, sessionCookieExpires > Date() {
			return authData
		}

		let httpClient = createHTTPClientIfNeed(eventLoopGroup: eventLoopGroup)

		defer {
			shutdownHTTPClientIfNeeded(httpClient, eventLoopGroup: eventLoopGroup)
		}

		let url = buildUrl(path: "/_session")

		var request = HTTPClientRequest(url: url)
		request.method = .POST
		request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
		var bodyComponents = URLComponents()
		bodyComponents.queryItems = [
			URLQueryItem(name: "name", value: userName),
			URLQueryItem(name: "password", value: userPassword)
		]
		let bodyString = bodyComponents.percentEncodedQuery ?? ""
		request.body = .bytes(ByteBuffer(string: bodyString))

		let response =
			try await httpClient
			.execute(request, timeout: .seconds(requestsTimeout))

		if response.status == .unauthorized {
			throw CouchDBClientError.unauthorized
		}

		var cookie = ""
		response.headers.forEach { (header: (name: String, value: String)) in
			if header.name.lowercased() == "set-cookie" {
				cookie = header.value
			}
		}

		if let httpCookie = HTTPClient.Cookie(header: cookie, defaultDomain: self.couchHost) {
			if httpCookie.expires == nil {
				let expiresString = cookie.split(separator: ";")
					.map({ $0.trimmingCharacters(in: .whitespaces) })
					.first(where: { $0.hasPrefix("Expires=") })?
					.split(separator: "=").last

				if let expiresString = expiresString {
					sessionCookieExpires = Self.parseCookieExpires(String(expiresString))
				}
			} else {
				sessionCookieExpires = httpCookie.expires
			}
		}

		sessionCookie = cookie

		let data = try await collectResponseData(from: response)
		authData = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
		return authData
	}

	func collectResponseBytes(from response: HTTPClientResponse) async throws -> ByteBuffer {
		let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init)
		return try await response.body.collect(upTo: expectedBytes ?? 1024 * 1024 * 10)
	}

	func collectResponseData(from response: HTTPClientResponse) async throws -> Data {
		var bytes = try await collectResponseBytes(from: response)

		guard let data = bytes.readData(length: bytes.readableBytes) else {
			throw CouchDBClientError.noData
		}

		return data
	}

	func decodeJSON<T: Decodable>(
		_ type: T.Type,
		from data: Data,
		dateDecodingStrategy: JSONDecoder.DateDecodingStrategy? = nil,
		mapCouchError: (CouchDBError) -> CouchDBClientError
	) throws -> T {
		let decoder = JSONDecoder()
		if let dateDecodingStrategy {
			decoder.dateDecodingStrategy = dateDecodingStrategy
		}

		do {
			return try decoder.decode(type, from: data)
		} catch let parsingError {
			if let couchdbError = try? decoder.decode(CouchDBError.self, from: data) {
				throw mapCouchError(couchdbError)
			}
			throw parsingError
		}
	}

	func decodeCouchError(from data: Data) throws -> CouchDBError {
		guard let couchdbError = try? JSONDecoder().decode(CouchDBError.self, from: data) else {
			throw CouchDBClientError.unknownResponse
		}
		return couchdbError
	}

	func performGetRequest(
		fromDB dbName: String,
		uri: String,
		queryItems: [URLQueryItem]? = nil,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> (response: HTTPClientResponse, bytes: ByteBuffer) {
		let url = buildUrl(path: "/" + dbName + "/" + uri, query: queryItems ?? [])
		let request = try buildRequest(fromUrl: url, withMethod: .GET)
		let result = try await authorizedBytes(request, eventLoopGroup: eventLoopGroup)
		var bytes = result.bytes

		if result.response.status == .notFound {
			guard let data = bytes.readData(length: bytes.readableBytes) else {
				throw CouchDBClientError.noData
			}

			throw CouchDBClientError.notFound(error: try decodeCouchError(from: data))
		}

		return (result.response, bytes)
	}

	func performFindRequest(
		inDB dbName: String,
		body: HTTPClientRequest.Body,
		eventLoopGroup: EventLoopGroup? = nil
	) async throws -> (response: HTTPClientResponse, bytes: ByteBuffer) {
		let url = buildUrl(path: "/" + dbName + "/_find", query: [])
		var request = try buildRequest(fromUrl: url, withMethod: .POST)
		request.body = body
		return try await authorizedBytes(request, eventLoopGroup: eventLoopGroup)
	}

	func buildRequest(fromUrl url: String, withMethod method: HTTPMethod) throws -> HTTPClientRequest {
		var headers = HTTPHeaders()
		headers.add(name: "Content-Type", value: "application/json")
		if let cookie = sessionCookie {
			headers.add(name: "Cookie", value: cookie)
		}

		var request = HTTPClientRequest(url: url)
		request.method = method
		request.headers = headers
		return request
	}

	static func parseCookieExpires(_ expiresString: String) -> Date? {
		// Common cookie Expires formats seen in the wild.
		let formats = [
			"E, dd MMM yyyy HH:mm:ss zzz",
			"E, dd-MMM-yyyy HH:mm:ss zzz",
			"E, dd-MMM-yyyy HH:mm:ss z"
		]
		for format in formats {
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.timeZone = TimeZone(secondsFromGMT: 0)
			formatter.dateFormat = format
			if let date = formatter.date(from: expiresString) {
				return date
			}
		}
		return nil
	}
}
