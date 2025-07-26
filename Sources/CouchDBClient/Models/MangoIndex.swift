//
//  MangoIndex.swift
//
//
//  Created by Sergey Armodin on 26.07.2025.
//

import Foundation

/// A struct representing a Mango Index for CouchDB.
public struct MangoIndex: Codable, Sendable {
	/// The design document where the index is stored.
	public let ddoc: String?

	/// The name of the index.
	public let name: String

	/// The type of the index (e.g., "json").
	public let type: String

	/// The definition of the index.
	public let def: IndexDefinition

	enum CodingKeys: String, CodingKey {
		case ddoc
		case name
		case type
		case def
		case index
	}

	/// Initializes a new Mango Index.
	/// - Parameters:
	///   - ddoc: The design document for the index.
	///   - name: The name of the index.
	///   - type: The type of the index.
	///   - def: The definition of the index.
	public init(
		ddoc: String? = nil,
		name: String,
		type: String,
		def: IndexDefinition
	) {
		self.ddoc = ddoc
		self.name = name
		self.type = type
		self.def = def
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		// CouchDB can return null for ddoc, so decodeIfPresent and allow nil
		self.ddoc = try container.decodeIfPresent(String.self, forKey: .ddoc)
		self.name = try container.decode(String.self, forKey: .name)
		self.type = try container.decode(String.self, forKey: .type)
		// For decoding, try 'def' first, then fallback to 'index'
		if let def = try? container.decode(IndexDefinition.self, forKey: .def) {
			self.def = def
		} else {
			self.def = try container.decode(IndexDefinition.self, forKey: .index)
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(ddoc, forKey: .ddoc)
		try container.encode(name, forKey: .name)
		try container.encode(type, forKey: .type)
		// For encoding, use 'index' key
		try container.encode(def, forKey: .index)
	}
}

/// A struct representing the definition of a Mango Index.
public struct IndexDefinition: Codable, Sendable {
	/// The fields to be indexed.
	public let fields: [[String: String]]

	enum CodingKeys: String, CodingKey {
		case fields
	}

	/// Initializes a new Index Definition.
	/// - Parameter fields: The fields to be indexed.
	public init(fields: [[String: String]]) {
		self.fields = fields
	}
}

/// A struct representing the response when listing indexes.
public struct MangoIndexesResponse: Codable, Sendable {
	/// The total number of indexes.
	public let totalRows: Int

	/// The array of indexes.
	public let indexes: [MangoIndex]

	enum CodingKeys: String, CodingKey {
		case totalRows = "total_rows"
		case indexes
	}
}

/// A struct representing the response from CouchDB when creating a Mango index.
public struct MangoCreateIndexResponse: Codable, Sendable {
	/// Indicates whether the operation was successful.
	public let result: String  // e.g., "created" or "exists"
	/// The name of the index.
	public let name: String?
	/// The design document where the index is stored.
	public let id: String?
}
