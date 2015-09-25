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
import WebKit

extension WKWebView {
    public func loadPlugin(object: AnyObject, namespace: String) -> XWVScriptObject? {
        let channel = XWVChannel(name: nil, webView: self)
        return channel.bindPlugin(object, toNamespace: namespace)
    }

    func prepareForPlugin() {
        let key = unsafeAddressOf(XWVChannel)
        if objc_getAssociatedObject(self, key) != nil { return }

        let bundle = NSBundle(forClass: XWVChannel.self)
        guard let path = bundle.pathForResource("xwebview", ofType: "js"),
            let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) else {
            preconditionFailure("FATAL: Internal error")
        }
        let time = WKUserScriptInjectionTime.AtDocumentStart
        let script = WKUserScript(source: source as String, injectionTime: time, forMainFrameOnly: true)
        let xwvplugin = XWVUserScript(webView: self, script: script, namespace: "XWVPlugin")
        objc_setAssociatedObject(self, key, xwvplugin, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension WKWebView {
    // Synchronized evaluateJavaScript
    public func evaluateJavaScript(script: String, error: NSErrorPointer = nil) -> AnyObject? {
        var result: AnyObject?
        var done = false
        let timeout = 3.0
        if NSThread.isMainThread() {
            evaluateJavaScript(script) {
                (obj: AnyObject?, err: NSError?)->Void in
                result = obj
                if error != nil {
                    error.memory = err
                }
                done = true
            }
            while !done {
                let reason = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, true)
                if reason != CFRunLoopRunResult.HandledSource {
                    break
                }
            }
        } else {
            let condition: NSCondition = NSCondition()
            dispatch_async(dispatch_get_main_queue()) {
                [weak self] in
                self?.evaluateJavaScript(script) {
                    (obj: AnyObject?, err: NSError?)->Void in
                    condition.lock()
                    result = obj
                    if error != nil {
                        error.memory = err
                    }
                    done = true
                    condition.signal()
                    condition.unlock()
                }
            }
            condition.lock()
            while !done {
                if !condition.waitUntilDate(NSDate(timeIntervalSinceNow: timeout)) {
                    break
                }
            }
            condition.unlock()
        }
        if !done {
            print("ERROR: Timeout to evaluate script.")
        }
        return result
    }
}

extension WKWebView {
    // WKWebView can't load file URL on iOS 8.x devices.
    // We have to start an embedded http server for proxy.
    // When running on iOS 8.x, we provide the same API as on iOS 9.
    // On iOS 9 and above, we do nothing.

    // Swift 2 doesn't support override +load method of NSObject, override +initialize instead.
    // See http://nshipster.com/swift-objc-runtime/
    private static var initialized: dispatch_once_t = 0
    public override class func initialize() {
        //if #available(iOS 9, *) { return }
        guard self == WKWebView.self else { return }
        dispatch_once(&initialized) {
            let selector = Selector("loadFileURL:allowingReadAccessToURL:")
            let method = class_getInstanceMethod(self, Selector("_loadFileURL:allowingReadAccessToURL:"))
            assert(method != nil)
            if class_addMethod(self, selector, method_getImplementation(method), method_getTypeEncoding(method)) {
                print("iOS 8.x")
                method_exchangeImplementations(
                    class_getInstanceMethod(self, Selector("loadHTMLString:baseURL:")),
                    class_getInstanceMethod(self, Selector("_loadHTMLString:baseURL:"))
                )
            }
        }
    }

    @objc private func _loadFileURL(URL: NSURL, allowingReadAccessToURL readAccessURL: NSURL) -> WKNavigation? {
        precondition(URL.fileURL && readAccessURL.fileURL)
        let fileManager = NSFileManager.defaultManager()
        var relationship: NSURLRelationship = NSURLRelationship.Other
        _ = try? fileManager.getRelationship(&relationship, ofDirectoryAtURL: readAccessURL, toItemAtURL: URL)

        var isDirectory: ObjCBool = false
        if fileManager.fileExistsAtPath(readAccessURL.path!, isDirectory: &isDirectory) &&
            isDirectory && relationship != NSURLRelationship.Other {
            let port = startHttpd(documentRoot: readAccessURL.path!)
            var path = URL.path![readAccessURL.path!.endIndex ..< URL.path!.endIndex]
            if let query = URL.query { path += "?\(query)" }
            if let fragment = URL.fragment { path += "#\(fragment)" }
            let url = NSURL(string: path , relativeToURL: NSURL(string: "http://127.0.0.1:\(port)"))
            return loadRequest(NSURLRequest(URL: url!));
        }
        return nil
    }

    @objc private func _loadHTMLString(html: String, baseURL: NSURL) -> WKNavigation? {
        guard baseURL.fileURL else {
            // call original method implementation
            return _loadHTMLString(html, baseURL: baseURL)
        }

        let fileManager = NSFileManager.defaultManager()
        var isDirectory: ObjCBool = false
        if fileManager.fileExistsAtPath(baseURL.path!, isDirectory: &isDirectory) && isDirectory {
            let port = startHttpd(documentRoot: baseURL.path!)
            let url = NSURL(string: "http://127.0.0.1:\(port)/")
            return loadHTMLString(html, baseURL: url)
        }
        return nil
    }

    private func startHttpd(documentRoot root: String) -> in_port_t {
        let key = unsafeAddressOf(XWVHttpServer)
        var httpd = objc_getAssociatedObject(self, key) as? XWVHttpServer
        if httpd == nil {
            httpd = XWVHttpServer(documentRoot: root)
            httpd!.start()
            objc_setAssociatedObject(self, key, httpd!, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return httpd!.port
    }
}
