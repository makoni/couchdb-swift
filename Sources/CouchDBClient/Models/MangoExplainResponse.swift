//
//  MangoExplainResponse.swift
//
//
//  Created by Sergey Armodin on 26.07.2025.
//

import Foundation

/// A struct representing the response from a Mango `_explain` request.
public struct MangoExplainResponse: Codable, Sendable {
	/// The name of the database.
	public let dbname: String

	/// The index that was used for the query.
	public let index: MangoIndex

	/// The selector that was used for the query.
	public let selector: [String: MangoValue]

	/// The options that were used for the query.
	public let opts: [String: MangoValue]

	/// The limit that was used for the query.
	public let limit: Int

	/// The number of results to skip.
	public let skip: Int

	/// The fields to be returned in the result.
	public let fields: [String]

	/// The range that was scanned.
	public let range: [String: MangoValue]
}
