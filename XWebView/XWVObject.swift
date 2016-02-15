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

private let webViewInvalidated =
    NSError(domain: WKErrorDomain, code: WKErrorCode.WebViewInvalidated.rawValue, userInfo: nil)

public class XWVObject : NSObject {
    public let namespace: String
    private(set) public weak var webView: WKWebView?
    private weak var origin: XWVObject?
    private let reference: Int

    // initializer for plugin object.
    init(namespace: String, webView: WKWebView) {
        self.namespace = namespace
        self.webView = webView
        reference = 0
        super.init()
        origin = self
    }

    // initializer for script object with global namespace.
    init(namespace: String, origin: XWVObject) {
        self.namespace = namespace
        self.origin = origin
        webView = origin.webView
        reference = 0
        super.init()
    }

    // initializer for script object which is retained on script side.
    init(reference: Int, origin: XWVObject) {
        self.reference = reference
        self.origin = origin
        webView = origin.webView
        namespace = "\(origin.namespace).$references[\(reference)]"
        super.init()
    }

    deinit {
        guard let webView = webView else { return }
        let script: String
        if origin === self {
            script = "delete \(namespace)"
        } else if reference != 0, let origin = origin {
            script = "\(origin.namespace).$releaseObject(\(reference))"
        } else {
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // Evaluate JavaScript expression
    public func evaluateExpression(expression: String) throws -> AnyObject? {
        guard let webView = webView else {
            throw webViewInvalidated
        }
        return wrapScriptObject(try webView.evaluateJavaScript(scriptForRetaining(expression)))
    }
    public func evaluateExpression(expression: String, error: NSErrorPointer) -> AnyObject? {
        guard let webView = webView else {
            if error != nil { error.memory = webViewInvalidated }
            return nil
        }
        return wrapScriptObject(webView.evaluateJavaScript(scriptForRetaining(expression), error: error))
    }
    public func evaluateExpression(expression: String, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        guard let webView = webView else {
            completionHandler?(nil, webViewInvalidated)
            return
        }
        guard let completionHandler = completionHandler else {
            webView.evaluateJavaScript(expression, completionHandler: nil)
            return
        }
        webView.evaluateJavaScript(scriptForRetaining(expression)) {
            [weak self](result: AnyObject?, error: NSError?)->Void in
            completionHandler(self?.wrapScriptObject(result) ?? result, error)
        }
    }
    private func scriptForRetaining(script: String) -> String {
        guard let origin = origin else { return script }
        return "\(origin.namespace).$retainObject(\(script))"
    }

    func wrapScriptObject(object: AnyObject!) -> AnyObject! {
        guard let origin = origin else { return object }
        if let dict = object as? [String: AnyObject] where dict["$sig"] as? NSNumber == 0x5857574F {
            if let num = dict["$ref"] as? NSNumber where num != 0 {
                return XWVScriptObject(reference: num.integerValue, origin: origin)
            } else if let namespace = dict["$ns"] as? String {
                return XWVScriptObject(namespace: namespace, origin: origin)
            }
        }
        return object
    }

    func serialize(object: AnyObject?) -> String {
        var obj: AnyObject? = object
        if let val = obj as? NSValue {
            obj = val as? NSNumber ?? val.nonretainedObjectValue
        }

        if let o = obj as? XWVObject {
            return o.namespace
        } else if let s = obj as? String {
            let d = try? NSJSONSerialization.dataWithJSONObject([s], options: NSJSONWritingOptions(rawValue: 0))
            let json = NSString(data: d!, encoding: NSUTF8StringEncoding)!
            return json.substringWithRange(NSMakeRange(1, json.length - 2))
        } else if let n = obj as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue.description
            }
            return n.stringValue
        } else if let date = obj as? NSDate {
            return "(new Date(\(date.timeIntervalSince1970 * 1000)))"
        } else if let _ = obj as? NSData {
            // TODO: map to Uint8Array object
        } else if let a = obj as? [AnyObject] {
            return "[" + a.map(serialize).joinWithSeparator(", ") + "]"
        } else if let d = obj as? [String: AnyObject] {
            return "{" + d.keys.map{"'\($0)': \(self.serialize(d[$0]!))"}.joinWithSeparator(", ") + "}"
        } else if obj === NSNull() {
            return "null"
        } else if obj == nil {
            return "undefined"
        }
        return "'\(obj!.description)'"
    }
}
