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

    init?(namespace: String, channel: XWVChannel, arguments: [Any]?) {
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
        if selector == #selector(_InitSelector.init(byScriptWithArguments:)) {
            arguments = [arguments]
        }

        plugin = invoke(#selector(NSProxy.alloc), of: cls) as AnyObject
        if plugin != nil {
            plugin = performSelector(selector, with: arguments) as AnyObject!
        }
        guard plugin != nil else {
            log("!Failed to create instance for plugin class \(cls)")
            return nil
        }

        bind()
        syncProperties()
        promise?.callMethod("resolve", with: [self], completionHandler: nil)
    }

    deinit {
        (plugin as? XWVScripting)?.finalizeForScript?()
        super.callMethod("dispose", with: [true], completionHandler: nil)
        unbind()
    }

    private func bind() {
        // Start KVO
        guard let plugin = plugin as? NSObject else { return }
        channel.typeInfo.filter{ $1.isProperty }.forEach {
            plugin.addObserver(self, forKeyPath: String(describing: $1.getter!), options: NSKeyValueObservingOptions.new, context: nil)
        }
    }
    private func unbind() {
        // Stop KVO
        guard plugin is NSObject else { return }
        channel.typeInfo.filter{ $1.isProperty }.forEach {
            plugin.removeObserver(self, forKeyPath: String(describing: $1.getter!), context: nil)
        }
    }
    private func syncProperties() {
        let script = channel.typeInfo.filter{ $1.isProperty }.reduce("") {
            let val: Any! = performSelector($1.1.getter!, with: nil)
            guard let json = jsonify(val) else { return "" }
            return "\($0)\(namespace).$properties['\($1.0)'] = \(json);\n"
        }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // Dispatch operation to plugin object
    func invokeNativeMethod(name: String, with arguments: [Any]) {
        guard let selector = channel.typeInfo[name]?.selector else { return }

        var args = arguments.map(wrapScriptObject)
        if plugin is XWVScripting && name.isEmpty && selector == #selector(XWVScripting.invokeDefaultMethod(withArguments:)) {
            args = [args];
        }
        _ = performSelector(selector, with: args, waitUntilDone: false)
    }
    func updateNativeProperty(name: String, with value: Any) {
        guard let setter = channel.typeInfo[name]?.setter else { return }

        let val: Any = wrapScriptObject(value)
        _ = performSelector(setter, with: [val], waitUntilDone: false)
    }

    // override methods of XWVScriptObject
    override func callMethod(_ name: String, with arguments: [Any]?, completionHandler: ((Any?, Error?) -> Void)?) {
        if let selector = channel.typeInfo[name]?.selector {
            let result: Any! = performSelector(selector, with: arguments)
            completionHandler?(result, nil)
        } else {
            super.callMethod(name, with: arguments, completionHandler: completionHandler)
        }
    }
    override func callMethod(_ name: String, with arguments: [Any]?) throws -> Any? {
        if let selector = channel.typeInfo[name]?.selector {
            return performSelector(selector, with: arguments)
        }
        return try super.callMethod(name, with: arguments)
    }
    override func value(for name: String) -> Any? {
        if let getter = channel.typeInfo[name]?.getter {
            return performSelector(getter, with: nil)
        }
        return super.value(for: name)
    }
    override func setValue(_ value: Any?, for name: String) {
        if let setter = channel.typeInfo[name]?.setter {
            _ = performSelector(setter, with: [value ?? NSNull()])
        } else if channel.typeInfo[name] == nil {
            super.setValue(value, for: name)
        } else {
            assertionFailure("Property '\(name)' is readonly")
        }
    }

    // KVO for syncing properties
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = webView, var prop = keyPath, let change = change,
              let json = jsonify(change[NSKeyValueChangeKey.newKey]) else {
            return
        }
        if channel.typeInfo[prop] == nil {
            if let scriptNameForKey = (type(of: object) as? XWVScripting.Type)?.scriptName(forKey:) {
                prop = prop.withCString(scriptNameForKey) ?? prop
            }
            assert(channel.typeInfo[prop] != nil)
        }
        let script = "\(namespace).$properties['\(prop)'] = \(json)"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

extension XWVBindingObject {
    private static var key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    fileprivate static var currentBindingObject: XWVBindingObject? {
        let ptr = pthread_getspecific(XWVBindingObject.key)
        guard ptr != nil else { return nil }
        return unsafeBitCast(ptr, to: XWVBindingObject.self)
    }
    fileprivate func performSelector(_ selector: Selector, with arguments: [Any]?, waitUntilDone wait: Bool = true) -> Any! {
        var result: Any! = ()
        let trampoline : () -> Void = {
            [weak self] in
            guard let plugin = self?.plugin else { return }
            let args: [Any?] = arguments?.map{ $0 is NSNull ? nil : ($0 as Any) } ?? []
            let save = pthread_getspecific(XWVBindingObject.key)
            pthread_setspecific(XWVBindingObject.key, Unmanaged<XWVBindingObject>.passUnretained(self!).toOpaque())
            result = invoke(selector, of: plugin, with: args)
            pthread_setspecific(XWVBindingObject.key, save)
        }
        if let queue = channel.queue {
            if !wait {
                queue.async(execute: trampoline)
            } else if String(cString: __dispatch_queue_get_label(nil)) != queue.label {
                queue.sync(execute: trampoline)
            } else {
                trampoline()
            }
        } else if let runLoop = channel.runLoop?.getCFRunLoop() {
            if wait && CFRunLoopGetCurrent() === runLoop {
                trampoline()
            } else {
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, trampoline)
                CFRunLoopWakeUp(runLoop)
                while wait && result is Void {
                    let reason = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 3.0, true)
                    if reason != CFRunLoopRunResult.handledSource {
                        break
                    }
                }
            }
        }
        return result
    }
}

public extension XWVScriptObject {
    static var bindingObject: XWVScriptObject? {
        return XWVBindingObject.currentBindingObject
    }
}
