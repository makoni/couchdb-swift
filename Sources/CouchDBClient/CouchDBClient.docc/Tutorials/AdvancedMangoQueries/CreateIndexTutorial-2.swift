// Step 2: Create the MangoIndex object
let indexFields: [[String: String]] = [["type": "asc"], ["age": "asc"]]
let indexDef = IndexDefinition(fields: indexFields)
let mangoIndex = MangoIndex(ddoc: "my-ddoc", name: "my-index", type: "json", def: indexDef)
