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
    public let ddoc: String
    
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
    }
    
    /// Initializes a new Mango Index.
    /// - Parameters:
    ///   - ddoc: The design document for the index.
    ///   - name: The name of the index.
    ///   - type: The type of the index.
    ///   - def: The definition of the index.
    public init(
        ddoc: String,
        name: String,
        type: String,
        def: IndexDefinition
    ) {
        self.ddoc = ddoc
        self.name = name
        self.type = type
        self.def = def
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
