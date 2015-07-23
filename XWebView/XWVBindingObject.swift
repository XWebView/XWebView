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
        objc_setAssociatedObject(object, key, self, UInt(OBJC_ASSOCIATION_ASSIGN))
        startKVO()
    }

    init(namespace: String, channel: XWVChannel, arguments: [AnyObject]?) {
        super.init(namespace: namespace, channel: channel, origin: nil)
        var args = arguments?.map(wrapScriptObject) ?? []
        var selector = Selector()
        var promise: XWVScriptObject?
        if let member = channel.typeInfo[""] where member.isInitializer {
            switch member {
            case let .Initializer(sel, arity):
                selector = sel
                if arity == Int32(args.count) - 1 || arity < 0 {
                    promise = last(args) as? XWVScriptObject
                }
            default: break
            }
        }
        assert(selector != nil)
        if selector == "initByScriptWithArguments:" {
            args = [args]
        }
        object = XWVInvocation.constructOnThread(channel.thread, `class`: channel.typeInfo.plugin, initializer: selector, arguments: args)
        objc_setAssociatedObject(object, key, self, UInt(OBJC_ASSOCIATION_ASSIGN))
        startKVO()
        syncProperties()
        promise?.callMethod("resolve", withArguments: [self], resultHandler: nil)
    }
    private func syncProperties() {
        var script = ""
        for (name, member) in filter(channel.typeInfo, { $1.isProperty }) {
            let val = XWVInvocation.callOnThread(channel.thread, target: object, selector: member.getter!, arguments: nil)
            script += "\(namespace).$properties['\(name)'] = \(serialize(val));\n"
        }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    deinit {
        if (object as? XWVScripting)?.finalizeForScript != nil {
            XWVInvocation.callOnThread(channel.thread, target: object, selector: Selector("finalizeForScript"), arguments: nil)
        }
        objc_setAssociatedObject(object, key, nil, UInt(OBJC_ASSOCIATION_ASSIGN))
        stopKVO()
    }

    // Dispatch operation to plugin object
    func invokeNativeMethod(name: String, withArguments arguments: [AnyObject]?) {
        if let selector = channel.typeInfo[name]?.selector {
            var args = arguments?.map(wrapScriptObject)
            if object is XWVScripting && name.isEmpty && selector == Selector("invokeDefaultMethodWithArguments:") {
                args = [args ?? []];
            }
            if channel.queue != nil {
                dispatch_async(channel.queue) {
                    XWVInvocation.call(object, selector: selector, arguments: args)
                }
            } else {
                XWVInvocation.asyncCallOnThread(channel.thread, target: object, selector: selector, arguments: args)
            }
        }
    }
    func updateNativeProperty(name: String, withValue value: AnyObject!) {
        if let setter = channel.typeInfo[name]?.setter {
            let val: AnyObject = wrapScriptObject(value)
            if channel.queue != nil {
                dispatch_async(channel.queue) {
                    XWVInvocation.call(object, selector: setter, arguments: [val])
                }
            } else {
                XWVInvocation.asyncCallOnThread(channel.thread, target: object, selector: setter, arguments: [val])
            }
        }
    }

    // override methods of XWVScriptObject
    override func callMethod(name: String, withArguments arguments: [AnyObject]?, resultHandler: ((AnyObject!) -> Void)?) {
        if let selector = channel.typeInfo[name]?.selector {
            let result = XWVInvocation.call(object, selector: selector, arguments: arguments)
            resultHandler?(result as? NSNumber ?? result.nonretainedObjectValue)
        } else {
            super.callMethod(name, withArguments: arguments, resultHandler: resultHandler)
        }
    }
    override func callMethod(name: String, withArguments arguments: [AnyObject]?) -> AnyObject! {
        if let selector = channel.typeInfo[name]?.selector {
            let result = XWVInvocation.call(object, selector: selector, arguments: arguments)
            return result as? NSNumber ?? result.nonretainedObjectValue
        }
        return super.callMethod(name, withArguments: arguments)
    }
    override func value(forProperty name: String) -> AnyObject? {
        if let getter = channel.typeInfo[name]?.getter {
            let result = XWVInvocation.call(object, selector: getter, arguments: nil)
            return result as? NSNumber ?? result.nonretainedObjectValue
        }
        return super.value(forProperty: name)
    }
    override func setValue(value: AnyObject?, forProperty name: String) {
        if let setter = channel.typeInfo[name]?.setter {
            XWVInvocation.call(object, selector: setter, arguments: [value!])
        } else {
            assert(channel.typeInfo[name] == nil, "Property '\(name)' is readonly")
            super.setValue(value, forProperty: name)
        }
    }

    // KVO for syncing properties
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        var prop = keyPath
        if channel.typeInfo[prop] == nil {
            if let scriptNameForKey = object.dynamicType.scriptNameForKey {
                prop = scriptNameForKey((prop as NSString).UTF8String) ?? prop
            }
            assert(channel.typeInfo[prop] != nil)
        }
        let script = "\(namespace).$properties['\(prop)'] = \(serialize(change[NSKeyValueChangeNewKey]))"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    private func startKVO() {
        if !(object is NSObject) { return }
        for (name, member) in filter(channel.typeInfo, { $1.isProperty }) {
            object.addObserver(self, forKeyPath: member.getter!.description, options: NSKeyValueObservingOptions.New, context: nil)
        }
    }
    private func stopKVO() {
        if !(object is NSObject) { return }
        for (name, member) in filter(channel.typeInfo, { $1.isProperty }) {
            object.removeObserver(self, forKeyPath: member.getter!.description, context: nil)
        }
    }
}

public extension NSObject {
    var scriptObject: XWVScriptObject? {
        return objc_getAssociatedObject(self, unsafeAddressOf(XWVScriptObject)) as? XWVScriptObject
    }
}
