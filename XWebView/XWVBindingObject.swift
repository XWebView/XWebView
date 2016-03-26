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

final class XWVBindingObject : XWVScriptObject {
    unowned let channel: XWVChannel
    var plugin: AnyObject!

    init(namespace: String, channel: XWVChannel, object: AnyObject) {
        self.channel = channel
        self.plugin = object
        super.init(namespace: namespace, webView: channel.webView!)
        bind()
    }

    init?(namespace: String, channel: XWVChannel, arguments: [AnyObject]?) {
        self.channel = channel
        super.init(namespace: namespace, webView: channel.webView!)
        let cls: AnyClass = channel.typeInfo.plugin
        let member = channel.typeInfo[""]
        guard member != nil, case .Initializer(let selector, let arity) = member! else {
            log("!Plugin class \(cls) is not a constructor")
            return nil
        }

        var arguments = arguments?.map(wrapScriptObject) ?? []
        var promise: XWVScriptObject?
        if arity == Int32(arguments.count) - 1 || arity < 0 {
            promise = arguments.last as? XWVScriptObject
            arguments.removeLast()
        }
        if selector == Selector("initByScriptWithArguments:") {
            arguments = [arguments]
        }

        plugin = invoke(cls, selector: #selector(_SpecialSelectors.alloc), withArguments: []) as? AnyObject
        if plugin != nil {
            plugin = performSelector(selector, withObjects: arguments)
        }
        guard plugin != nil else {
            log("!Failed to create instance for plugin class \(cls)")
            return nil
        }

        bind()
        syncProperties()
        promise?.callMethod("resolve", withArguments: [self], completionHandler: nil)
    }

    deinit {
        (plugin as? XWVScripting)?.finalizeForScript?()
        super.callMethod("dispose", withArguments: [true], completionHandler: nil)
        unbind()
    }

    private func bind() {
        // Start KVO
        guard let plugin = plugin as? NSObject else { return }
        channel.typeInfo.filter{ $1.isProperty }.forEach {
            plugin.addObserver(self, forKeyPath: String($1.getter!), options: NSKeyValueObservingOptions.New, context: nil)
        }
    }
    private func unbind() {
        // Stop KVO
        guard plugin is NSObject else { return }
        channel.typeInfo.filter{ $1.isProperty }.forEach {
            plugin.removeObserver(self, forKeyPath: String($1.getter!), context: nil)
        }
    }
    private func syncProperties() {
        let script = channel.typeInfo.filter{ $1.isProperty }.reduce("") {
            let val: AnyObject! = performSelector($1.1.getter!, withObjects: nil)
            return "\($0)\(namespace).$properties['\($1.0)'] = \(serialize(val));\n"
        }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // Dispatch operation to plugin object
    func invokeNativeMethod(name: String, withArguments arguments: [AnyObject]) {
        guard let selector = channel.typeInfo[name]?.selector else { return }

        var args = arguments.map(wrapScriptObject)
        if plugin is XWVScripting && name.isEmpty && selector == #selector(XWVScripting.invokeDefaultMethodWithArguments(_:)) {
            args = [args];
        }
        performSelector(selector, withObjects: args, waitUntilDone: false)
    }
    func updateNativeProperty(name: String, withValue value: AnyObject) {
        guard let setter = channel.typeInfo[name]?.setter else { return }

        let val: AnyObject = wrapScriptObject(value)
        performSelector(setter, withObjects: [val], waitUntilDone: false)
    }

    // override methods of XWVScriptObject
    override func callMethod(name: String, withArguments arguments: [AnyObject]?, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        if let selector = channel.typeInfo[name]?.selector {
            let result: AnyObject! = performSelector(selector, withObjects: arguments)
            completionHandler?(result, nil)
        } else {
            super.callMethod(name, withArguments: arguments, completionHandler: completionHandler)
        }
    }
    override func callMethod(name: String, withArguments arguments: [AnyObject]?) throws -> AnyObject? {
        if let selector = channel.typeInfo[name]?.selector {
            return performSelector(selector, withObjects: arguments)
        }
        return try super.callMethod(name, withArguments: arguments)
    }
    override func value(forProperty name: String) -> AnyObject? {
        if let getter = channel.typeInfo[name]?.getter {
            return performSelector(getter, withObjects: nil)
        }
        return super.value(forProperty: name)
    }
    override func setValue(value: AnyObject?, forProperty name: String) {
        if let setter = channel.typeInfo[name]?.setter {
            performSelector(setter, withObjects: [value ?? NSNull()])
        } else if channel.typeInfo[name] == nil {
            super.setValue(value, forProperty: name)
        } else {
            assertionFailure("Property '\(name)' is readonly")
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
}

extension XWVBindingObject {
    private static var key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    private static var currentBindingObject: XWVBindingObject? {
        let ptr = pthread_getspecific(XWVBindingObject.key)
        guard ptr != nil else { return nil }
        return unsafeBitCast(ptr, XWVBindingObject.self)
    }
    private func performSelector(selector: Selector, withObjects arguments: [AnyObject]?, waitUntilDone wait: Bool = true) -> AnyObject! {
        var result: Any! = ()
        let trampoline: dispatch_block_t = {
            [weak self] in
            guard let plugin = self?.plugin else { return }
            let args: [Any!] = arguments?.map{ $0 is NSNull ? nil : ($0 as Any) } ?? []
            let save = pthread_getspecific(XWVBindingObject.key)
            pthread_setspecific(XWVBindingObject.key, unsafeAddressOf(self!))
            result = castToObjectFromAny(invoke(plugin, selector: selector, withArguments: args))
            pthread_setspecific(XWVBindingObject.key, save)
        }
        if let queue = channel.queue {
            if !wait {
                dispatch_async(queue, trampoline)
            } else if dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(queue) {
                dispatch_sync(queue, trampoline)
            } else {
                trampoline()
            }
        } else if let runLoop = channel.runLoop?.getCFRunLoop() {
            if wait && CFRunLoopGetCurrent() === runLoop {
                trampoline()
            } else {
                CFRunLoopPerformBlock(runLoop, kCFRunLoopDefaultMode, trampoline)
                CFRunLoopWakeUp(runLoop)
                while wait && result is Void {
                    let reason = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 3.0, true)
                    if reason != CFRunLoopRunResult.HandledSource {
                        break
                    }
                }
            }
        }
        return result as? AnyObject
    }
}

public extension XWVScriptObject {
    static var bindingObject: XWVScriptObject? {
        return XWVBindingObject.currentBindingObject
    }
}
