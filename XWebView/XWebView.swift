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
        if objc_getAssociatedObject(self, key) == nil {
            let bundle = NSBundle(forClass: XWVChannel.self)
            if let path = bundle.pathForResource("xwebview", ofType: "js"),
                let source = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: nil) {
                let script = WKUserScript(source: source as String,
                                          injectionTime: WKUserScriptInjectionTime.AtDocumentStart,
                                          forMainFrameOnly: true)
                let xwvplugin = XWVUserScript(webView: self, script: script, namespace: "XWVPlugin")
                objc_setAssociatedObject(self, key, xwvplugin, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
            } else {
                preconditionFailure("FATAL: Internal error")
            }
        }
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
                (obj: AnyObject!, err: NSError!)->Void in
                result = obj
                if error != nil {
                    error.memory = err
                }
                done = true
            }
            while !done {
                let reason = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, Boolean(1))
                if Int(reason) != kCFRunLoopRunHandledSource {
                    break
                }
            }
        } else {
            let condition: NSCondition = NSCondition()
            dispatch_async(dispatch_get_main_queue()) {
                [weak self] in
                self?.evaluateJavaScript(script) {
                    (obj: AnyObject!, err: NSError!)->Void in
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
            println("ERROR: Timeout to evaluate script.")
        }
        return result
    }
}

extension WKWebView {
    // WKWebView can't load file URL on iOS 8.x devices.
    // We have to start an embedded http server for proxy.
    public func loadFileURL(URL: NSURL, allowingReadAccessToURL readAccessURL: NSURL) -> WKNavigation? {
        assert(URL.fileURL && readAccessURL.fileURL)
        let fileManager = NSFileManager.defaultManager()
        var relationship: NSURLRelationship = NSURLRelationship.Other
        fileManager.getRelationship(&relationship, ofDirectoryAtURL: readAccessURL, toItemAtURL: URL, error: nil)

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

    public func loadHTMLString(html: String, baseFileURL baseURL: NSURL) -> WKNavigation? {
        assert(baseURL.fileURL)
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
            objc_setAssociatedObject(self, key, httpd!, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }
        return httpd!.port
    }
}
