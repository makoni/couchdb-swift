// Advanced Mango Queries Step 2: Sorting, Limit, and Skip
let selector: [String: MangoValue] = [
    "type": .string("user"),
    "age": .dictionary(["$gt": .int(30)])
]
let sort: [[String: String]] = [["name": "asc"]]
let limit = 10
let skip = 0
