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


class XWVScriptPlugin : XWVScriptObject {
    let key = unsafeAddressOf(XWVScriptObject)
    var object: NSObject!

    init(namespace: String, channel: XWVChannel, object: NSObject) {
        super.init(namespace: namespace, channel: channel, origin: nil)
        self.object = object
        objc_setAssociatedObject(object, key, self, UInt(OBJC_ASSOCIATION_ASSIGN))
        startKVO()
    }

    init(namespace: String, channel: XWVChannel, arguments: [AnyObject]!) {
        super.init(namespace: namespace, channel: channel, origin: nil)
        let args = arguments.map(wrapScriptObject)
        object = XWVInvocation.constructOnThread(channel.thread, `class`: channel.typeInfo.plugin, initializer: channel.typeInfo.constructor, arguments: args) as! NSObject
        objc_setAssociatedObject(object, key, self, UInt(OBJC_ASSOCIATION_ASSIGN))
        startKVO()
        setupInstance()
    }
    private func setupInstance() {
        var script = ""
        for name in channel.typeInfo.allProperties {
            let getter = channel.typeInfo.getter(forProperty: name)
            let val = XWVInvocation.callOnThread(channel.thread, target:object, selector: getter, arguments: nil)
            script += "\(namespace)['\(name)'] = \(serialize(val));\n"
        }
        script += "if (\(namespace)['$onready'] instanceof Function) {\n" +
            "    \(namespace).$onready();\n" +
            "    delete \(namespace).$onready;\n" +
        "}\n"
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
    func invokeNativeMethod(name: String!, withArguments arguments: [AnyObject]?) {
        let args = arguments?.map(wrapScriptObject)
        let selector = channel.typeInfo.selector(forMethod: name)
        if channel.queue != nil {
            dispatch_async(channel.queue) {
                XWVInvocation.call(object, selector: selector, arguments: args)
            }
        } else {
            XWVInvocation.asyncCallOnThread(channel.thread, target: object, selector: selector, arguments: args)
        }
    }
    func updateNativeProperty(name: String!, withValue value: AnyObject!) {
        let val: AnyObject = wrapScriptObject(value)
        let setter = channel.typeInfo.setter(forProperty: name)
        if channel.queue != nil {
            dispatch_async(channel.queue) {
                XWVInvocation.call(object, selector: setter, arguments: [val])
            }
        } else {
            XWVInvocation.asyncCallOnThread(channel.thread, target: object, selector: setter, arguments: [val])
        }
    }

    // override methods of XWVScriptObject
    override func callMethod(name: String, withArguments arguments: [AnyObject]?, resultHandler: ((AnyObject!) -> Void)?) {
        if channel.typeInfo.hasMethod(name) {
            invokeNativeMethod(name, withArguments: arguments)
            resultHandler?(nil)
        } else {
            super.callMethod(name, withArguments: arguments, resultHandler: resultHandler)
        }
    }
    override func callMethod(name: String, withArguments arguments: [AnyObject]?) -> AnyObject! {
        if channel.typeInfo.hasMethod(name) {
            invokeNativeMethod(name, withArguments: arguments)
            return nil
        }
        return super.callMethod(name, withArguments: arguments)
    }
    override func value(forProperty name: String) -> AnyObject? {
        let getter = channel.typeInfo.getter(forProperty: name)
        if getter != Selector() {
            let result = XWVInvocation.call(object, selector: getter, arguments: nil)
            return result.isObject ? result.nonretainedObjectValue : (result.isNumber ? result : nil)
        }
        return super.value(forProperty: name)
    }
    override func setValue(value: AnyObject?, forProperty name: String) {
        let setter = channel.typeInfo.setter(forProperty: name)
        if setter != Selector() {
            XWVInvocation.call(object, selector: setter, arguments: [value!])
        } else {
            assert(!channel.typeInfo.hasProperty(name), "Property '\(name)' is readonly")
            super.setValue(value, forProperty: name)
        }
    }

    // KVO for syncing properties
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        var prop = keyPath
        if !channel.typeInfo.hasProperty(prop) {
            if object.dynamicType.scriptNameForKey != nil {
                prop = object.dynamicType.scriptNameForKey!((prop as NSString).UTF8String)
            } else {
                for name in channel.typeInfo.allProperties {
                    if channel.typeInfo.getter(forProperty: name).description == prop {
                        prop = name
                        break
                    }
                }
            }
            assert(channel.typeInfo.hasProperty(prop))
        }
        let script = "\(namespace).$properties['\(prop)'] = \(serialize(change[NSKeyValueChangeNewKey]))"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    private func startKVO() {
        for prop in channel.typeInfo.allProperties {
            let key = channel.typeInfo.getter(forProperty: prop).description
            object.addObserver(self, forKeyPath: key, options: NSKeyValueObservingOptions.New, context: nil)
        }
    }
    private func stopKVO() {
        for prop in channel.typeInfo.allProperties {
            let key = channel.typeInfo.getter(forProperty: prop).description
            object.removeObserver(self, forKeyPath: key, context: nil)
        }
    }
}

public extension NSObject {
    var scriptObject: XWVScriptObject? {
        return objc_getAssociatedObject(self, unsafeAddressOf(XWVScriptObject)) as? XWVScriptObject
    }
}
