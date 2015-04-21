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
    public let id: String
    public let thread: NSThread
    private(set) public weak var webView: WKWebView?
    var typeInfo: XWVReflection!

    private var instances: [Int: XWVScriptPlugin] = [:]
    private var userScript: WKUserScript?

    public init(channelID: String?, webView: WKWebView, thread: NSThread? = nil) {
        struct seq{
            static var num: UInt32 = 0
        }
        self.id = channelID ?? "\(++seq.num)"

        self.thread = thread ?? webView.pluginThread
        super.init()
        if (self.thread === webView.pluginThread) && !self.thread.executing {
            self.thread.start()
        }

        self.webView = webView
        webView.configuration.userContentController.addScriptMessageHandler(self, name: "\(self.id)")
    }
    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandlerForName("\(id)")
    }

    public func bindPlugin(object: NSObject, toNamespace namespace: String) -> XWVScriptObject? {
        assert(typeInfo == nil)
        typeInfo = XWVReflection(plugin: object.dynamicType)
        let plugin = XWVScriptPlugin(namespace: namespace, channel: self, object: object)
        let stub = XWVStubGenerator(reflection: typeInfo).generate(id, namespace: namespace, object: plugin)
        userScript = webView?.injectScript((object as? XWVScripting)?.javascriptStub?(stub) ?? stub)
        instances[0] = plugin
        return plugin as XWVScriptObject
    }

    public func unbind() {
        assert(typeInfo != nil)
        if webView?.URL != nil {
            evaluateJavaScript("delete \(instances[0]!.namespace);", completionHandler:nil)
        }
        if userScript != nil {
            webView?.configuration.userContentController.removeUserScript(userScript!)
        }
        instances.removeAll(keepCapacity: false)
    }

    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage: WKScriptMessage) {
        let body = didReceiveScriptMessage.body as [String: AnyObject]
        let target = (body["$target"] as? NSNumber)?.integerValue ?? 0
        if let opcode = body["$opcode"] as? String {
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
                } else if typeInfo.hasProperty(opcode) {
                    // Update property
                    object.updateNativeProperty(opcode, withValue: body["$operand"])
                } else if typeInfo.hasMethod(opcode) {
                    // Invoke method
                    let args = body["$operand"] as? [AnyObject]
                    object.invokeNativeMethod(opcode, withArguments: args)
                }  // else Unknown opcode
            } else if opcode == "+" {
                // Create instance
                let args = body["$operand"] as [AnyObject]?
                let namespace = "\(instances[0]!.namespace)[\(target)]"
                instances[target] = XWVScriptPlugin(namespace: namespace, channel: self, arguments: args)
            } // else Unknown opcode
        } else {
            // discard unknown message
            println("WARNING: Unknown message: \(body)")
        }
    }


    public func evaluateJavaScript(script: String, completionHandler: ((AnyObject!, NSError!)->Void)?) {
        if NSThread.isMainThread() {
            webView?.evaluateJavaScript(script, completionHandler: completionHandler)
        } else {
            dispatch_async(dispatch_get_main_queue()) {
                [weak self] in
                self?.webView?.evaluateJavaScript(script, completionHandler: completionHandler)
                return
            }
        }
    }

    // Synchronized evaluateJavaScript
    private let condition: NSCondition = NSCondition()
    private var result: AnyObject!
    public func evaluateJavaScript(script: String) -> AnyObject? {
        assert(!NSThread.isMainThread(), "Wrong thread")

        weak var weakSelf = self
        dispatch_async(dispatch_get_main_queue()) {
            [weak self] in
            self?.webView?.evaluateJavaScript(script) {
                [weak self] (result: AnyObject!, error: NSError!)->Void in
                if self != nil {
                    self?.condition.lock()
                    self?.result = result
                    self?.condition.signal()
                    self?.condition.unlock()
                }
            }
            return
        }

        var obj: AnyObject?
        condition.lock()
        condition.wait()
        if let src = result as? NSObject {
            obj = src.copy()
        }
        condition.unlock()
        return obj
    }
}
