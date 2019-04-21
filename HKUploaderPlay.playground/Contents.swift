import UIKit

let samples: [[String: Any]] = [
    ["type": "food",
     "time": "0",
     "origin": [
        "id": "B7A2DC7D_00",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "1",
     "origin": [
        "id": "B7A2DC7D_01",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "2",
     "origin": [
        "id": "B7A2DC7D_02",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "3",
     "origin": [
        "id": "B7A2DC7D_03",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "4",
     "origin": [
        "id": "B7A2DC7D_04",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "5",
     "origin": [
        "id": "B7A2DC7D_05",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "6",
     "origin": [
        "id": "B7A2DC7D_06",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "7",
     "origin": [
        "id": "B7A2DC7D_07",
        "name": "com.apple.HealthKit"
        ]
    ],
    ["type": "food",
     "time": "8",
     "origin": [
        "id": "B7A2DC7D_08",
        "name": "com.apple.HealthKit"
        ]
    ],
]

let response: [String: Any] = [
    "code":"value-out-of-range",
    "title":"value is out of range",
    "detail":"value 691200000 is not between 0 and 604800000",
    "source":["pointer":"/2/duration"],
    "meta":["type":"basal","deliveryType":"temp"]
]

let response2: [String: Any] = [
 "errors":
    [
        ["code":"value-out-of-range",
         "title":"value is out of range",
         "detail":"value 691200000 is not between 0 and 604800000",
         "source":["pointer":"/3/duration"],
         "meta":["type":"basal","deliveryType":"temp"]
        ],
        ["code":"value-out-of-range",
         "title":"value is out of range",
         "detail":"value 691200000 is not between 0 and 604800000",
         "source":["pointer":"/8/duration"],
         "meta":["type":"basal","deliveryType":"temp"]
        ]
    ]
]

var badSamples: [Int] = []
var messageParseError = false
func parseErrorDict(_ errDict: Any) {
    guard let errDict = errDict as? [String: Any] else {
        NSLog("Error message source field is not valid!")
        messageParseError = true
        return
    }
    guard let errStr = errDict["pointer"] as? String else {
        NSLog("Error message source pointer missing or invalid!")
        messageParseError = true
        return
    }
    print("next error is \(errStr)")
    guard errStr.count >= 2 else {
        NSLog("Error message pointer string too short!")
        messageParseError = true
        return
    }
    let parser = Scanner(string: errStr)
    parser.scanLocation = 1
    var index: Int = -1
    guard parser.scanInt(&index) else {
        NSLog("Unable to find index in error message!")
        messageParseError = true
        return
    }
    print("index of next bad sample is: \(index)")
    badSamples.append(index)
}

func parseErrResponse(_ response: [String: Any]) {
    if let errorArray = response["errors"] as? [[String: Any]] {
        for errorDict in errorArray {
            if let source = errorDict["source"] {
                parseErrorDict(source)
            }
        }
    } else {
        if let source = response["source"] as? [String: Any] {
            parseErrorDict(source)
        }
    }
}

print("Parsing response with single error...")
parseErrResponse(response)
print("Parsing response with 2 errors...")
parseErrResponse(response2)
print("bad samples found: \(badSamples.count)")

if badSamples.count > 0 {
    let remainingSamples = samples
        .enumerated()
        .filter {!badSamples.contains($0.offset)}
        .map{ $0.element}
    print("original count: \(samples.count)")
    print("remaining count: \(remainingSamples.count)")
    print("remaining samples: \(remainingSamples)")
}

