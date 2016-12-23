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
import WebKit

public class XWVScriptObject : XWVObject {
    // JavaScript object operations
    public func construct(arguments: [Any]?, completionHandler: ((Any?, Error?) -> Void)?) {
        let exp = "new " + scriptForCallingMethod(nil, arguments: arguments)
        evaluateExpression(exp, completionHandler: completionHandler)
    }
    public func call(arguments: [Any]?, completionHandler: ((Any?, Error?) -> Void)?) {
        let exp = scriptForCallingMethod(nil, arguments: arguments)
        evaluateExpression(exp, completionHandler: completionHandler)
    }
    public func callMethod(_ name: String, with arguments: [Any]?, completionHandler: ((Any?, Error?) -> Void)?) {
        let exp = scriptForCallingMethod(name, arguments: arguments)
        evaluateExpression(exp, completionHandler: completionHandler)
    }

    public func construct(arguments: [Any]?) throws -> Any {
        let exp = "new \(scriptForCallingMethod(nil, arguments: arguments))"
        guard let result = try evaluateExpression(exp) else {
            let code = WKError.javaScriptExceptionOccurred.rawValue
            throw NSError(domain: WKErrorDomain, code: code, userInfo: nil)
        }
        return result
    }
    public func call(arguments: [Any]?) throws -> Any? {
        return try evaluateExpression(scriptForCallingMethod(nil, arguments: arguments))
    }
    public func callMethod(_ name: String, with arguments: [Any]?) throws -> Any? {
        return try evaluateExpression(scriptForCallingMethod(name, arguments: arguments))
    }
    public func call(arguments: [Any]?, error: NSErrorPointer) -> Any? {
        return evaluateExpression(scriptForCallingMethod(nil, arguments: arguments), error: error)
    }
    public func callMethod(_ name: String, with arguments: [Any]?, error: NSErrorPointer) -> Any? {
        return evaluateExpression(scriptForCallingMethod(name, arguments: arguments), error: error)
    }

    public func defineProperty(_ name: String, descriptor: [String:Any]) -> Any? {
        let exp = "Object.defineProperty(\(namespace), \(name), \(jsonify(descriptor)!))"
        return try! evaluateExpression(exp)
    }
    public func deleteProperty(_ name: String) -> Bool {
        let result: Any? = try! evaluateExpression("delete \(scriptForFetchingProperty(name))")
        return (result as? NSNumber)?.boolValue ?? false
    }
    public func hasProperty(_ name: String) -> Bool {
        let result: Any? = try! evaluateExpression("\(scriptForFetchingProperty(name)) != undefined")
        return (result as? NSNumber)?.boolValue ?? false
    }

    public func value(for name: String) -> Any? {
        return try! evaluateExpression(scriptForFetchingProperty(name))
    }
    public func setValue(_ value: Any?, for name:String) {
        guard let json = jsonify(value) else { return }
        let script = scriptForFetchingProperty(name) + " = " + json
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    public func value(at index: UInt) -> Any? {
        return try! evaluateExpression("\(namespace)[\(index)]")
    }
    public func setValue(_ value: Any?, at index: UInt) {
        guard let json = jsonify(value) else { return }
        let script = "\(namespace)[\(index)] = \(json)"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func scriptForFetchingProperty(_ name: String?) -> String {
        guard let name = name else {
            return namespace
        }

        if name.isEmpty {
            return "\(namespace)['']"
        } else if let idx = Int(name) {
            return "\(namespace)[\(idx)]"
        } else {
            return "\(namespace).\(name)"
        }
    }
    private func scriptForCallingMethod(_ name: String?, arguments: [Any]?) -> String {
        let args = arguments?.map{jsonify($0) ?? ""} ?? []
        return scriptForFetchingProperty(name) + "(" + args.joined(separator: ", ") + ")"
    }
}

extension XWVScriptObject {
    // Subscript as property accessor
    public subscript(name: String) -> Any? {
        get {
            return value(for: name)
        }
        set {
            setValue(newValue, for: name)
        }
    }
    public subscript(index: UInt) -> Any? {
        get {
            return value(at: index)
        }
        set {
            setValue(newValue, at: index)
        }
    }
}

class XWVWindowObject: XWVScriptObject {
    private let origin: XWVObject
    init(webView: WKWebView) {
        origin = XWVObject(namespace: "XWVPlugin.context", webView: webView)
        super.init(namespace: "window", origin: origin)
    }
}
