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
import ObjectiveC

class XWVBindingObject : XWVScriptObject {
    let key = unsafeAddressOf(XWVScriptObject)
    var object: AnyObject!

    init(namespace: String, channel: XWVChannel, object: AnyObject) {
        super.init(namespace: namespace, channel: channel, origin: nil)
        self.object = object
        objc_setAssociatedObject(object, key, self, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        startKVO()
    }

    init?(namespace: String, channel: XWVChannel, arguments: [AnyObject]?) {
        super.init(namespace: namespace, channel: channel, origin: nil)
        let member = channel.typeInfo[""]
        guard member != nil, case .Initializer(let selector, let arity) = member! else {
            print("<XWV> ERROR: Plugin is not a constructor")
            return nil
        }

        var args = arguments?.map(wrapScriptObject) ?? []
        var promise: XWVScriptObject?
        if arity == Int32(args.count) - 1 || arity < 0 {
            promise = args.last as? XWVScriptObject
            args.removeLast()
        }
        if selector == "initByScriptWithArguments:" {
            args = [args]
        }
        object = XWVInvocation(target: channel.typeInfo.plugin).call(Selector("alloc")) as? AnyObject
        object = XWVInvocation(target: object).call(selector, withObjects: args)
        objc_setAssociatedObject(object, key, self, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        startKVO()
        syncProperties()
        promise?.callMethod("resolve", withArguments: [self], completionHandler: nil)
    }
    private func syncProperties() {
        var script = ""
        for (name, member) in channel.typeInfo.filter({ $1.isProperty }) {
            let val: AnyObject! = XWVInvocation(target: object).call(member.getter!, withObjects: nil)
            script += "\(namespace).$properties['\(name)'] = \(serialize(val));\n"
        }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    deinit {
        if (object as? XWVScripting)?.finalizeForScript != nil {
            XWVInvocation(target: object)[Selector("finalizeForScript")]()
        }
        objc_setAssociatedObject(object, key, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        stopKVO()
    }

    // Dispatch operation to plugin object
    func invokeNativeMethod(name: String, withArguments arguments: [AnyObject]) {
        if let selector = channel.typeInfo[name]?.selector {
            var args = arguments.map(wrapScriptObject)
            if object is XWVScripting && name.isEmpty && selector == Selector("invokeDefaultMethodWithArguments:") {
                args = [args];
            }
            if channel.queue != nil {
                dispatch_async(channel.queue) {
                    XWVInvocation(target: object).call(selector, withObjects: args)
                }
            } else {
                // FIXME: Add NSThread support back while migrate to Swift 2.0
                XWVInvocation(target: object).call(selector, withObjects: args)
            }
        }
    }
    func updateNativeProperty(name: String, withValue value: AnyObject) {
        if let setter = channel.typeInfo[name]?.setter {
            let val: AnyObject = wrapScriptObject(value)
            if channel.queue != nil {
                dispatch_async(channel.queue) {
                    XWVInvocation(target: object).call(setter, withObjects: [val])
                }
            } else {
                // FIXME: Add NSThread support back while migrate to Swift 2.0
                XWVInvocation(target: self.object)[name] = val
            }
        }
    }

    // override methods of XWVScriptObject
    override func callMethod(name: String, withArguments arguments: [AnyObject]?, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        if let selector = channel.typeInfo[name]?.selector {
            let result: AnyObject! = XWVInvocation(target: object).call(selector, withObjects: arguments)
            completionHandler?(result, nil)
        } else {
            super.callMethod(name, withArguments: arguments, completionHandler: completionHandler)
        }
    }
    override func callMethod(name: String, withArguments arguments: [AnyObject]?) throws -> AnyObject! {
        if let selector = channel.typeInfo[name]?.selector {
            return XWVInvocation(target: object).call(selector, withObjects: arguments)
        }
        return try super.callMethod(name, withArguments: arguments)
    }
    override func value(forProperty name: String) -> AnyObject? {
        if let getter = channel.typeInfo[name]?.getter {
            return XWVInvocation(target: object).call(getter, withObjects: nil)
        }
        return super.value(forProperty: name)
    }
    override func setValue(value: AnyObject?, forProperty name: String) {
        if channel.typeInfo[name]?.setter != nil {
            XWVInvocation(target: object)[name] = value
        } else {
            assert(channel.typeInfo[name] == nil, "Property '\(name)' is readonly")
            super.setValue(value, forProperty: name)
        }
    }

    // KVO for syncing properties
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard let webView = webView, var prop = keyPath else { return }
        if channel.typeInfo[prop] == nil {
            if let scriptNameForKey = (object.dynamicType as? XWVScripting.Type)?.scriptNameForKey {
                prop = prop.withCString(scriptNameForKey) ?? prop
            }
            assert(channel.typeInfo[prop] != nil)
        }
        let script = "\(namespace).$properties['\(prop)'] = \(serialize(change?[NSKeyValueChangeNewKey]))"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    private func startKVO() {
        guard object is NSObject else { return }
        for (_, member) in channel.typeInfo.filter({ $1.isProperty }) {
            object.addObserver(self, forKeyPath: member.getter!.description, options: NSKeyValueObservingOptions.New, context: nil)
        }
    }
    private func stopKVO() {
        guard object is NSObject else { return }
        for (_, member) in channel.typeInfo.filter({ $1.isProperty }) {
            object.removeObserver(self, forKeyPath: member.getter!.description, context: nil)
        }
    }
}

public extension NSObject {
    var scriptObject: XWVScriptObject? {
        return objc_getAssociatedObject(self, unsafeAddressOf(XWVScriptObject)) as? XWVScriptObject
    }
}
