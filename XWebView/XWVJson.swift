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
public func jsonify<T: Collection>(_ array: T) -> String?
        where T.Index: BinaryInteger {
    // TODO: filter out values with negative index
    return "[" + array.map{jsonify($0) ?? ""}.joined(separator: ",") + "]"
}

// JSON Object
public func jsonify<T: Collection, V>(_ object: T) -> String?
        where T.Iterator.Element == (key: String, value: V) {
    return "{" + object.flatMap(jsonify).joined(separator: ",") + "}"
}
private func jsonify<T>(_ pair: (key: String, value: T)) -> String? {
    guard let val = jsonify(pair.value) else { return nil }
    return jsonify(pair.key)! + ":" + val
}

// JSON Number
public func jsonify<T: BinaryInteger>(_ integer: T) -> String? {
    return String(describing: integer)
}
public func jsonify<T: FloatingPoint>(_ float: T) -> String? {
    return String(describing: float)
}

// JSON Boolean
public func jsonify(_ bool: Bool) -> String? {
    return String(describing: bool)
}

// JSON String
public func jsonify(_ string: String) -> String? {
    return string.unicodeScalars.reduce("\"") { $0 + $1.jsonEscaped } + "\""
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


@objc public protocol ObjCJSONStringable {
    var jsonString: String? { get }
}
public protocol CustomJSONStringable {
    var jsonString: String? { get }
}

extension CustomJSONStringable where Self: RawRepresentable {
    public var jsonString: String? {
        return jsonify(rawValue)
    }
}

public func jsonify(_ value: Any?) -> String? {
    guard let value = value else { return "null" }

    switch (value) {
    case is Void:
        return "undefined"
    case is NSNull:
        return "null"
    case let s as String:
        return jsonify(s)
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return n.boolValue.description
        }
        return n.stringValue
    case let a as Array<Any?>:
        return jsonify(a)
    case let d as Dictionary<String, Any?>:
        return jsonify(d)
    case let s as CustomJSONStringable:
        return s.jsonString
    case let o as ObjCJSONStringable:
        return o.jsonString
    case let d as Data:
        return d.withUnsafeBytes {
            (base: UnsafePointer<UInt8>) -> String? in
            jsonify(UnsafeBufferPointer<UInt8>(start: base, count: d.count))
        }
    default:
        let mirror = Mirror(reflecting: value)
        guard let style = mirror.displayStyle else { return nil }
        switch style {
        case .optional:  // nested optional
            return jsonify(mirror.children.first?.value)
        case .collection, .set, .tuple:  // array-like type
            return jsonify(mirror.children.map{$0.value})
        case .class, .dictionary, .struct:
            return "{" + mirror.children.flatMap(jsonify).joined(separator: ",") + "}"
        case .enum:
            return jsonify(String(describing: value))
        }
    }
}
private func jsonify(_ child: Mirror.Child) -> String? {
    if let key = child.label {
        return jsonify((key: key, value: child.value))
    }

    let m = Mirror(reflecting: child.value)
    guard m.children.count == 2, m.displayStyle == .tuple,
        let key = m.children.first!.value as? String else {
        return nil
    }
    let val = m.children[m.children.index(after: m.children.startIndex)].value
    return jsonify((key: key, value: val))
}
