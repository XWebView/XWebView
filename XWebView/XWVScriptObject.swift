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

public class XWVScriptObject : XWVObject {
    // Evaluate JavaScript string
    public func evaluateScript(script: String) -> AnyObject? {
        if let result: AnyObject = channel.evaluateJavaScript("\(origin.namespace).$retainIfNeeded(\(script))") {
            return wrapScriptObject(result)
        }
        return nil
    }

    public func evaluateScript(script: String, onSuccess handler: ((AnyObject!)->Void)?) {
        if handler == nil {
            channel.evaluateJavaScript(script, nil)
        } else {
            channel.evaluateJavaScript("\(origin.namespace).$retainIfNeeded(\(script))") {
                [weak self](result: AnyObject!, error: NSError!)->Void in
                if self != nil && result != nil {
                    handler!(self?.wrapScriptObject(result!))
                }
            }
        }
    }

    // JavaScript object operations
    public func construct(# arguments: [AnyObject]?, resultHandler: ((AnyObject!)->Void)?) {
        let script = "new " + scriptForCallingMethod(nil, arguments: arguments)
        evaluateScript(script, onSuccess: resultHandler)
    }
    public func call(# arguments: [AnyObject]?, resultHandler: ((AnyObject!)->Void)?) {
        let script = scriptForCallingMethod(nil, arguments: arguments)
        evaluateScript(script, onSuccess: resultHandler)
    }
    public func callMethod(name: String, withArguments arguments: [AnyObject]?, resultHandler: ((AnyObject!)->Void)?) {
        let script = scriptForCallingMethod(name, arguments: arguments)
        evaluateScript(script, onSuccess: resultHandler)
    }

    public func construct(# arguments: [AnyObject]?) -> AnyObject! {
        return evaluateScript("new \(scriptForCallingMethod(nil, arguments: arguments))")
    }
    public func call(# arguments: [AnyObject]?) -> AnyObject! {
        return evaluateScript(scriptForCallingMethod(nil, arguments: arguments))
    }
    public func callMethod(name: String, withArguments arguments: [AnyObject]?) -> AnyObject! {
        return evaluateScript(scriptForCallingMethod(name, arguments: arguments))
    }

    public func defineProperty(name: String, descriptor: [String:AnyObject]) {
        let script = "Object.defineProperty(\(namespace), \(name), \(serialize(descriptor)))"
        evaluateScript(script, onSuccess: nil)
    }
    public func deleteProperty(name: String) -> Bool {
        let result: AnyObject? = evaluateScript("delete \(scriptForFetchingProperty(name))")
        return (result as? NSNumber)?.boolValue ?? false
    }
    public func hasProperty(name: String) -> Bool {
        let result: AnyObject? = evaluateScript("\(scriptForFetchingProperty(name)) != undefined")
        return (result as? NSNumber)?.boolValue ?? false
    }

    public func value(forProperty name: String) -> AnyObject? {
        return evaluateScript(scriptForFetchingProperty(name))
    }
    public func setValue(value: AnyObject?, forProperty name:String) {
        evaluateScript(scriptForUpdatingProperty(name, value: value), onSuccess: nil)
    }
    public func value(atIndex index: UInt) -> AnyObject? {
        return evaluateScript("\(namespace)[\(index)]")
    }
    public func setValue(value: AnyObject?, atIndex index: UInt) {
        evaluateScript("\(namespace)[\(index)] = \(serialize(value))", onSuccess: nil)
    }

    private func scriptForFetchingProperty(name: String!) -> String {
        if name == nil {
            return namespace
        } else if name.isEmpty {
            return "\(namespace)['']"
        } else if let idx = name.toInt() {
            return "\(namespace)[\(idx)]"
        } else {
            return "\(namespace).\(name)"
        }
    }
    private func scriptForUpdatingProperty(name: String!, value: AnyObject?) -> String {
        return scriptForFetchingProperty(name) + " = " + serialize(value)
    }
    private func scriptForCallingMethod(name: String!, arguments: [AnyObject]?) -> String {
        let args = arguments?.map(serialize) ?? []
        return scriptForFetchingProperty(name) + "(" + ", ".join(args) + ")"
    }
}

extension XWVScriptObject {
    // Subscript support
    public subscript(name: String) -> AnyObject? {
        get {
            return value(forProperty: name)
        }
        set {
            setValue(newValue, forProperty: name)
        }
    }
    public subscript(index: UInt) -> AnyObject? {
        get {
            return value(atIndex: index)
        }
        set {
            setValue(newValue, atIndex: index)
        }
    }
}

extension XWVScriptObject {
    // DOM objects
    public var windowObject: XWVScriptObject {
        return XWVScriptObject(namespace: "window", channel: self.channel, origin: self.origin)
    }
    public var documentObject: XWVScriptObject {
        return XWVScriptObject(namespace: "document", channel: self.channel, origin: self.origin)
    }
}
