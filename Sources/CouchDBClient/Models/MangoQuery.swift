//
//  MangoQuery.swift
//  
//
//  Created by Sergey Armodin on 26.07.2025.
//

import Foundation

/// A struct representing a Mango Query for CouchDB.
///
/// Use this struct to build complex queries to retrieve documents from a CouchDB database.
///
/// ### Example Usage:
/// ```swift
/// let query = MangoQuery(
///     selector: [
///         "type": .string("user"),
///         "age": .comparison(.greaterThan(.int(30)))
///     ],
///     fields: ["name", "email"],
///     sort: [["name": "asc"]],
///     limit: 10,
///     skip: 0
/// )
/// ```
public struct MangoQuery: Codable, Sendable {
    /// The selector defines the criteria for selecting documents.
    public let selector: [String: MangoValue]
    
    /// An array of field names to be returned in the result.
    public let fields: [String]?
    
    /// An array of sort definitions.
    public let sort: [[String: String]]?
    
    /// The maximum number of results to return.
    public let limit: Int?
    
    /// The number of results to skip.
    public let skip: Int?
    
    /// The name of the index to use for the query.
    public let useIndex: String?

    enum CodingKeys: String, CodingKey {
        case selector
        case fields
        case sort
        case limit
        case skip
        case useIndex = "use_index"
    }
    
    /// Initializes a new Mango Query.
    /// - Parameters:
    ///   - selector: The selector to use for the query.
    ///   - fields: The fields to return in the result.
    ///   - sort: The sort order for the results.
    ///   - limit: The maximum number of results to return.
    ///   - skip: The number of results to skip.
    ///   - useIndex: The name of the index to use.
    public init(
        selector: [String: MangoValue],
        fields: [String]? = nil,
        sort: [[String: String]]? = nil,
        limit: Int? = nil,
        skip: Int? = nil,
        useIndex: String? = nil
    ) {
        self.selector = selector
        self.fields = fields
        self.sort = sort
        self.limit = limit
        self.skip = skip
        self.useIndex = useIndex
    }
}

/// An enum representing the possible values in a Mango query selector.
public indirect enum MangoValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([MangoValue])
    case arrayOfDictionaries([[String: MangoValue]])
    case dictionary([String: MangoValue])
    case comparison(MangoComparison)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .arrayOfDictionaries(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .comparison(let cmp):
            try container.encode(cmp)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([MangoValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([[String: MangoValue]].self) {
            self = .arrayOfDictionaries(value)
        } else if let value = try? container.decode([String: MangoValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode(MangoComparison.self) {
            self = .comparison(value)
        } else {
            throw DecodingError.typeMismatch(MangoValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported MangoValue type"))
        }
    }
}

public indirect enum MangoComparison: Codable, Sendable {
    case equal(MangoValue)
    case greaterThan(MangoValue)
    case lessThan(MangoValue)
    case greaterThanOrEqual(MangoValue)
    case lessThanOrEqual(MangoValue)
    case notEqual(MangoValue)

    enum CodingKeys: String, CodingKey {
        case eq = "$eq"
        case gt = "$gt"
        case lt = "$lt"
        case gte = "$gte"
        case lte = "$lte"
        case ne = "$ne"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .equal(let value):
            try container.encode(value, forKey: .eq)
        case .greaterThan(let value):
            try container.encode(value, forKey: .gt)
        case .lessThan(let value):
            try container.encode(value, forKey: .lt)
        case .greaterThanOrEqual(let value):
            try container.encode(value, forKey: .gte)
        case .lessThanOrEqual(let value):
            try container.encode(value, forKey: .lte)
        case .notEqual(let value):
            try container.encode(value, forKey: .ne)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(MangoValue.self, forKey: .eq) {
            self = .equal(value)
        } else if let value = try? container.decode(MangoValue.self, forKey: .gt) {
            self = .greaterThan(value)
        } else if let value = try? container.decode(MangoValue.self, forKey: .lt) {
            self = .lessThan(value)
        } else if let value = try? container.decode(MangoValue.self, forKey: .gte) {
            self = .greaterThanOrEqual(value)
        } else if let value = try? container.decode(MangoValue.self, forKey: .lte) {
            self = .lessThanOrEqual(value)
        } else if let value = try? container.decode(MangoValue.self, forKey: .ne) {
            self = .notEqual(value)
        } else {
            throw DecodingError.typeMismatch(MangoComparison.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported MangoComparison type"))
        }
    }
}
