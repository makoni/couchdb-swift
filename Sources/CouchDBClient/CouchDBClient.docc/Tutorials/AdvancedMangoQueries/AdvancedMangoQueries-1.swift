// Advanced Mango Queries Step 1: Building Selectors
let selector: [String: MangoValue] = [
    "type": .string("user"),
    "age": .dictionary(["$gt": .int(30)])
]
