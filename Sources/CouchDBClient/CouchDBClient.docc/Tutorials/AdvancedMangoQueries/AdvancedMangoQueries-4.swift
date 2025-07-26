// Advanced Mango Queries Step 4: Index Usage
let selector: [String: MangoValue] = [
    "type": .string("user"),
    "age": .dictionary(["$gt": .int(30)])
]
let sort: [[String: String]] = [["name": "asc"]]
let limit = 10
let skip = 0
let fields = ["name", "email"]
let useIndex = "my-index"
