//
//  MangoQueryTests.swift
//  
//
//  Created by Sergey Armodin on 26.07.2025.
//

import Testing
@testable import CouchDBClient
import Foundation

@Suite("Mango Query Tests")
struct MangoQueryTests {
    @Test("MangoQuery encoding")
    func testMangoQueryEncoding() throws {
        let query = MangoQuery(
            selector: [
                "type": .string("user"),
                "age": .dictionary(["$gt": .int(30)])
            ],
            fields: ["name", "email"],
            sort: [["name": "asc"]],
            limit: 10,
            skip: 0,
            useIndex: "my-index"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(query)
        
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
        #expect(json != nil)
        
        let selector = json?["selector"] as? [String: Any]
        #expect(selector != nil)
        #expect(selector?["type"] as? String == "user")
        
        let age = selector?["age"] as? [String: Any]
        #expect(age != nil)
        #expect(age?["$gt"] as? Int == 30)
        
        let fields = json?["fields"] as? [String]
        #expect(fields != nil)
        #expect(fields == ["name", "email"])
        
        let sort = json?["sort"] as? [[String: String]]
        #expect(sort != nil)
        #expect(sort?.first?["name"] == "asc")
        
        #expect(json?["limit"] as? Int == 10)
        #expect(json?["skip"] as? Int == 0)
        #expect(json?["use_index"] as? String == "my-index")
    }
    
    @Test("MangoIndex encoding")
    func testMangoIndexEncoding() throws {
        let index = MangoIndex(
            ddoc: "my-ddoc",
            name: "my-index",
            type: "json",
            def: IndexDefinition(fields: [["name": "asc"]])
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(index)
        
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["ddoc"] as? String == "my-ddoc")
        #expect(json?["name"] as? String == "my-index")
        #expect(json?["type"] as? String == "json")
        
        let def = json?["def"] as? [String: Any]
        #expect(def != nil)
        
        let fields = def?["fields"] as? [[String: String]]
        #expect(fields != nil)
        #expect(fields?.first?["name"] == "asc")
    }
}