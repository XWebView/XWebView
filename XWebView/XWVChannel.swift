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

    private var instances = [Int: XWVScriptPlugin]()
    private var userScript: WKUserScript?

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
        assert(typeInfo == nil)
        webView?.configuration.userContentController.addScriptMessageHandler(self, name: name)
        typeInfo = XWVMetaObject(plugin: object.dynamicType)
        let plugin = XWVScriptPlugin(namespace: namespace, channel: self, object: object)
        let stub = XWVStubGenerator(channel: self).generateForNamespace(namespace, object: plugin)
        userScript = webView?.injectScript((object as? XWVScripting)?.javascriptStub?(stub) ?? stub)
        instances[0] = plugin
        return plugin as XWVScriptObject
    }

    public func unbind() {
        assert(typeInfo != nil)
        if webView?.URL != nil {
            webView!.evaluateJavaScript("delete \(instances[0]!.namespace);", completionHandler:nil)
        }
        if userScript != nil {
            webView?.configuration.userContentController.removeUserScript(userScript!)
        }
        instances.removeAll(keepCapacity: false)
        webView?.configuration.userContentController.removeScriptMessageHandlerForName(name)
    }

    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let body = message.body as? [String: AnyObject], let opcode = body["$opcode"] as? String {
            let target = (body["$target"] as? NSNumber)?.integerValue ?? 0
            if let object = instances[target] {
                if opcode == "-" {
                    if target == 0 {
                        // Destroy plugin
                        unbind()
                    } else {
                        // Destroy instance
                        let object = instances.removeValueForKey(target)
                        assert(object != nil)
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
                instances[target] = XWVScriptPlugin(namespace: namespace, channel: self, arguments: args)
            } // else Unknown opcode
        } else if let obj = instances[0]!.object as? WKScriptMessageHandler {
            // Plugin claims for raw messages
            obj.userContentController(userContentController, didReceiveScriptMessage: message)
        } else {
            // discard unknown message
            println("WARNING: Unknown message: \(message.body)")
        }
    }
}
