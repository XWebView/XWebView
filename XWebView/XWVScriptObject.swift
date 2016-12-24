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
    // asynchronized method calling
    public func construct(arguments: [Any]?, completionHandler: Handler) {
        let expr = "new " + expression(forMethod: nil, arguments: arguments)
        evaluateExpression(expr, completionHandler: completionHandler)
    }
    public func call(arguments: [Any]?, completionHandler: Handler) {
        let expr = expression(forMethod: nil, arguments: arguments)
        evaluateExpression(expr, completionHandler: completionHandler)
    }
    public func callMethod(_ name: String, with arguments: [Any]?, completionHandler: Handler) {
        let expr = expression(forMethod: name, arguments: arguments)
        evaluateExpression(expr, completionHandler: completionHandler)
    }

    // synchronized method calling
    public func construct(arguments: [Any]?) throws -> XWVScriptObject {
        let expr = "new" + expression(forMethod: nil, arguments: arguments)
        guard let result = try evaluateExpression(expr) as? XWVScriptObject else {
            let code = WKError.javaScriptExceptionOccurred.rawValue
            throw NSError(domain: WKErrorDomain, code: code, userInfo: nil)
        }
        return result
    }
    public func call(arguments: [Any]?) throws -> Any {
        return try evaluateExpression(expression(forMethod: nil, arguments: arguments))
    }
    public func callMethod(_ name: String, with arguments: [Any]?) throws -> Any {
        return try evaluateExpression(expression(forMethod: name, arguments: arguments))
    }

    // property manipulation
    public func defineProperty(_ name: String, descriptor: [String:Any]) throws -> Any {
        let expr = "Object.defineProperty(\(namespace), \(name), \(jsonify(descriptor)!))"
        return try evaluateExpression(expr)
    }
    public func deleteProperty(_ name: String) -> Bool {
        let expr = "delete " + expression(forProperty: name)
        let result: Any? = try! evaluateExpression(expr)
        return (result as? NSNumber)?.boolValue ?? false
    }
    public func hasProperty(_ name: String) -> Bool {
        let expr = expression(forProperty: name) + " != undefined"
        let result: Any? = try! evaluateExpression(expr)
        return (result as? NSNumber)?.boolValue ?? false
    }

    // property accessing
    public func value(for name: String) throws -> Any {
        return try evaluateExpression(expression(forProperty: name))
    }
    public func setValue(_ value: Any?, for name:String) {
        guard let json = jsonify(value) else { return }
        let script = expression(forProperty: name) + " = " + json
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    public func value(at index: UInt) throws -> Any {
        return try evaluateExpression("\(namespace)[\(index)]")
    }
    public func setValue(_ value: Any?, at index: UInt) {
        guard let json = jsonify(value) else { return }
        let script = "\(namespace)[\(index)] = \(json)"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // expression generation
    private func expression(forProperty name: String?) -> String {
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
    private func expression(forMethod name: String?, arguments: [Any]?) -> String {
        let args = arguments?.map{jsonify($0) ?? ""} ?? []
        return expression(forProperty: name) + "(" + args.joined(separator: ", ") + ")"
    }
}

extension XWVScriptObject {
    // Subscript as property accessor
    public subscript(name: String) -> Any {
        get {
            return (try? value(for: name)) ?? undefined
        }
        set {
            setValue(newValue, for: name)
        }
    }
    public subscript(index: UInt) -> Any {
        get {
            return (try? value(at: index)) ?? undefined
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
