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

public class XWVChannel : NSObject, WKScriptMessageHandler {
    public let name: String
    public let thread: NSThread!
    public let queue: dispatch_queue_t!
    private(set) public weak var webView: WKWebView?
    var typeInfo: XWVMetaObject!

    private var instances = [Int: XWVBindingObject]()
    private var userScript: XWVUserScript?

    private class var sequenceNumber: UInt {
        struct sequence{
            static var number: UInt = 0
        }
        return ++sequence.number
    }

    public convenience init(name: String?, webView: WKWebView) {
        let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
        self.init(name: name, webView:webView, queue: queue)
    }
    
    public init(name: String?, webView: WKWebView, queue: dispatch_queue_t) {
        self.name = name ?? "\(XWVChannel.sequenceNumber)"
        self.webView = webView
        self.queue = queue
        thread = nil
        webView.prepareForPlugin()
    }
    
    public init(name: String?, webView: WKWebView, thread: NSThread) {
        self.name = name ?? "\(XWVChannel.sequenceNumber)"
        self.webView = webView
        self.thread = thread
        queue = nil
        webView.prepareForPlugin()
    }

    public func bindPlugin(object: AnyObject, toNamespace namespace: String) -> XWVScriptObject? {
        assert(typeInfo == nil, "<XWV> This channel already has a bound object")
        guard let webView = webView else { return nil }
        
        webView.configuration.userContentController.addScriptMessageHandler(self, name: name)
        typeInfo = XWVMetaObject(plugin: object.dynamicType)
        let plugin = XWVBindingObject(namespace: namespace, channel: self, object: object)

        let stub = generateStub(plugin)
        let script = WKUserScript(source: (object as? XWVScripting)?.javascriptStub?(stub) ?? stub,
                                  injectionTime: WKUserScriptInjectionTime.AtDocumentStart,
                                  forMainFrameOnly: true)
        userScript = XWVUserScript(webView: webView, script: script)

        instances[0] = plugin
        return plugin as XWVScriptObject
    }

    public func unbind() {
        assert(typeInfo != nil, "<XWV> Error: can't unbind inexistent plugin.")
        instances.removeAll(keepCapacity: false)
        webView?.configuration.userContentController.removeScriptMessageHandlerForName(name)
    }

    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let body = message.body as? [String: AnyObject], let opcode = body["$opcode"] as? String {
            let target = (body["$target"] as? NSNumber)?.integerValue ?? 0
            if let object = instances[target] {
                if opcode == "-" {
                    if target == 0 {
                        // Dispose plugin
                        unbind()
                        print("<XWV> Plugin was disposed")
                    } else {
                        // Dispose instance
                        let object = instances.removeValueForKey(target)
                        assert(object != nil, "<XWV> Warning: bad instance id was received")
                    }
                } else if let member = typeInfo[opcode] where member.isProperty {
                    // Update property
                    object.updateNativeProperty(opcode, withValue: body["$operand"])
                } else if let member = typeInfo[opcode] where member.isMethod {
                    // Invoke method
                    let args = body["$operand"] as? [AnyObject]
                    object.invokeNativeMethod(opcode, withArguments: args)
                }  // else Unknown opcode
            } else if opcode == "+" {
                // Create instance
                let args = body["$operand"] as? [AnyObject]
                let namespace = "\(instances[0]!.namespace)[\(target)]"
                instances[target] = XWVBindingObject(namespace: namespace, channel: self, arguments: args)
            } // else Unknown opcode
        } else if let obj = instances[0]!.object as? WKScriptMessageHandler {
            // Plugin claims for raw messages
            obj.userContentController(userContentController, didReceiveScriptMessage: message)
        } else {
            // discard unknown message
            print("<XWV> WARNING: Unknown message: \(message.body)")
        }
    }

    private func generateStub(object: XWVBindingObject) -> String {
        func generateMethod(this: String, name: String, prebind: Bool) -> String {
            let stub = "XWVPlugin.invokeNative.bind(\(this), '\(name)')"
            return prebind ? "\(stub);" : "function(){return \(stub).apply(null, arguments);}"
        }

        var base = "null"
        var prebind = true
        if let member = typeInfo[""] {
            if member.isInitializer {
                base = "'\(member.type)'"
                prebind = false
            } else {
                base = generateMethod("arguments.callee", name: "\(member.type)", prebind: false)
            }
        }

        var stub = "(function(exports) {\n"
        for (name, member) in typeInfo {
            if member.isMethod && !name.isEmpty {
                let method = generateMethod(prebind ? "exports" : "this", name: "\(name)\(member.type)", prebind: prebind)
                stub += "exports.\(name) = \(method)\n"
            } else if member.isProperty {
                let value = object.serialize(object[name])
                stub += "XWVPlugin.defineProperty(exports, '\(name)', \(value), \(member.setter != nil));\n"
            }
        }
        stub += "})(XWVPlugin.createPlugin('\(name)', '\(object.namespace)', \(base)));\n\n"
        return stub
    }
}
