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
    NSError(domain: WKErrorDomain, code: WKError.webViewInvalidated.rawValue, userInfo: nil)

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
        webView.asyncEvaluateJavaScript(script, completionHandler: nil)
    }

    // Evaluate JavaScript expression
    public func evaluateExpression(_ expression: String) throws -> Any {
        guard let webView = webView else {
            throw webViewInvalidated
        }
        let result = try webView.syncEvaluateJavaScript(scriptForRetaining(expression))
        return wrapScriptObject(result)
    }
    public typealias Handler = ((Any?, Error?) -> Void)?
    public func evaluateExpression(_ expression: String, completionHandler: Handler) {
        guard let webView = webView else {
            completionHandler?(nil, webViewInvalidated)
            return
        }
        guard let completionHandler = completionHandler else {
            webView.asyncEvaluateJavaScript(expression, completionHandler: nil)
            return
        }
        webView.asyncEvaluateJavaScript(scriptForRetaining(expression)) {
            [weak self](result: Any?, error: Error?)->Void in
            if let error = error {
                completionHandler(nil, error)
            } else if let result = result {
                completionHandler(self?.wrapScriptObject(result) ?? result, nil)
            } else {
                completionHandler(undefined, error)
            }
        }
    }
    private func scriptForRetaining(_ script: String) -> String {
        guard let origin = origin else { return script }
        return "\(origin.namespace).$retainObject(\(script))"
    }

    func wrapScriptObject(_ object: Any) -> Any {
        guard let origin = origin else { return object }
        if let dict = object as? [String: Any], dict["$sig"] as? NSNumber == 0x5857574F {
            if let num = dict["$ref"] as? NSNumber, num != 0 {
                return XWVScriptObject(reference: num.intValue, origin: origin)
            } else if let namespace = dict["$ns"] as? String {
                return XWVScriptObject(namespace: namespace, origin: origin)
            }
        }
        return object
    }
}

extension XWVObject : CustomJSONStringable {
    public var jsonString: String? {
        return namespace
    }
}
