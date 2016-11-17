/*
 Copyright 2015 XWebView

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

import Foundation

// JSON Array
func jsonify<T: Collection>(_ array: T) -> String where T.Index == Int {
    return "[" + array.map(jsonify).joined(separator: ", ") + "]"
}

// JSON Object
func jsonify<T: Collection, V>(_ object: T) -> String where T.Iterator.Element == (key: String, value: V) {
    return "{" + object.map(jsonify).joined(separator: ", ") + "}"
}
private func jsonify<T>(_ pair: (key: String, value: T)) -> String {
    return jsonify(pair.key) + ":" + jsonify(pair.value)
}

// JSON Number
func jsonify<T: Integer>(_ integer: T) -> String {
    return String(describing: integer)
}
func jsonify<T: FloatingPoint>(_ float: T) -> String {
    return String(describing: float)
}

// JSON Boolean
func jsonify(_ bool: Bool) -> String {
    return String(describing: bool)
}

// JSON String
func jsonify(_ string: String) -> String {
    return string.unicodeScalars.reduce("\"") { $0 + $1.jsonEscaped } + "\""
}
func jsonify(_ char: Character) -> String {
    return jsonify(String(char))
}
private extension UnicodeScalar {
    var jsonEscaped: String {
        switch value {
        case 0...7:      fallthrough
        case 11, 14, 15: return "\\u000" + String(value, radix: 16)
        case 16...31:    fallthrough
        case 127...159:  return "\\u00" + String(value, radix: 16)
        case 8:          return "\\b"
        case 12:         return "\\f"
        case 39:         return "'"
        default:         return escaped(asASCII: false)
        }
    }
}

func jsonify(_ value: NSObject) -> String {
    switch (value) {
    case _ as NSNull:
        return "null"
    case let s as NSString:
        return jsonify(String(s))
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return n.boolValue.description
        }
        return n.stringValue
    case let d as Data:
        return d.withUnsafeBytes {
            (ptr: UnsafePointer<UInt8>) -> String in
            jsonify(UnsafeBufferPointer<UInt8>(start: ptr, count: d.count))
        }
	case let a as [Any?]:
		return jsonify(a)
	case let d as [String : Any?]:
		return jsonify(d)
    default:
        //fatalError("Unsupported type \(type(of: value))")
        print("Unsupported type \(type(of: value))")
        return "undefined"
    }
}

func jsonify(_ value: Any!) -> String {
    switch (value) {
    case nil:                    return "undefined"
    case let b as Bool:          return jsonify(b)
    case let i as Int:           return jsonify(i)
    case let i as Int8:          return jsonify(i)
    case let i as Int16:         return jsonify(i)
    case let i as Int32:         return jsonify(i)
    case let i as Int64:         return jsonify(i)
    case let u as UInt:          return jsonify(u)
    case let u as UInt8:         return jsonify(u)
    case let u as UInt16:        return jsonify(u)
    case let u as UInt32:        return jsonify(u)
    case let u as UInt64:        return jsonify(u)
    case let f as Float:         return jsonify(f)
    case let f as Double:        return jsonify(f)
    case let s as String:        return jsonify(s)
    case let v as NSObject:      return jsonify(v)
    case is Void:                return "undefined"
    case let o as Optional<Any>:
        guard case let .some(v) = o else { return "null" }
        fatalError("Unsupported type \(type(of: v)) (of value \(v))")
    }
}
