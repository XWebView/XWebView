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

import WebKit

extension WKWebView {
    public func loadPlugin(object: AnyObject, namespace: String) -> XWVScriptObject? {
        let channel = XWVChannel(name: nil, webView: self)
        return channel.bindPlugin(object, toNamespace: namespace)
    }

    func injectScript(code: String) -> WKUserScript {
        let script = WKUserScript(
            source: code,
            injectionTime: WKUserScriptInjectionTime.AtDocumentStart,
            forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        if self.URL != nil {
            evaluateJavaScript(code) { (obj, err)->Void in
                if err != nil {
                    println("ERROR: Failed to inject JavaScript API.\n\(err)")
                }
            }
        }
        return script
    }

    func prepareForPlugin() {
        let key = unsafeAddressOf(XWVChannel)
        if objc_getAssociatedObject(self, key) == nil {
            let bundle = NSBundle(forClass: XWVChannel.self)
            if let path = bundle.pathForResource("xwebview", ofType: "js"),
                let code = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: nil) {
                    let script = injectScript(code as String)
                    objc_setAssociatedObject(self, key, script, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
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
    // WKWebView can't load file URL on device. We have to start an embedded http server for proxy.
    // Upstream WebKit has solved this issue. This function should be removed once WKWebKit adopts the fix.
    // See: https://bugs.webkit.org/show_bug.cgi?id=137153
    public func loadFileURL(URL: NSURL, allowingReadAccessToURL readAccessURL: NSURL) -> WKNavigation? {
        if (!URL.fileURL || !readAccessURL.fileURL) {
            let url = URL.fileURL ? readAccessURL : URL
            NSException.raise(NSInvalidArgumentException, format: "%@ is not a file URL", arguments: getVaList([url]))
        }

        let fileManager = NSFileManager.defaultManager()
        var relationship: NSURLRelationship = NSURLRelationship.Other
        var isDirectory: ObjCBool = false
        if (!fileManager.fileExistsAtPath(readAccessURL.path!, isDirectory: &isDirectory) || !isDirectory || !fileManager.getRelationship(&relationship, ofDirectoryAtURL: readAccessURL, toItemAtURL: URL, error: nil) || relationship == NSURLRelationship.Other) {
            return nil
        }

        let key = unsafeAddressOf(XWVHttpServer)
        var httpd = objc_getAssociatedObject(self, key) as? XWVHttpServer
        if httpd == nil {
            httpd = XWVHttpServer(documentRoot: readAccessURL.path)
            httpd!.start()
            objc_setAssociatedObject(self, key, httpd!, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }

        let target = URL.path!.substringFromIndex(advance(URL.path!.startIndex, count(readAccessURL.path!)))
        let url = NSURL(scheme: "http", host: "127.0.0.1:\(httpd!.port)", path: target)
        return loadRequest(NSURLRequest(URL: url!));
    }
    
    // WKWebView can't load HTML String on device with baseURL. Same problem
    // descripted above
    public func loadHTMLString(html: String, allowingReadAccessToBaseURL baseURL: NSURL?) -> WKNavigation? {
        if baseURL == nil {
            return loadHTMLString(html, baseURL: nil)
        } else {
            let fileManager = NSFileManager.defaultManager()
            var isDirectory: ObjCBool = false
            if !fileManager.fileExistsAtPath(baseURL!.path!, isDirectory: &isDirectory) || !isDirectory {
                return nil
            }
            
            let key = unsafeAddressOf(XWVHttpServer)
            var httpd = objc_getAssociatedObject(self, key) as? XWVHttpServer
            if httpd == nil {
                httpd = XWVHttpServer(documentRoot: baseURL!.path)
                httpd!.start()
                objc_setAssociatedObject(self, key, httpd!, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
            }
            
            let url = NSURL(string: "http://127.0.0.1:\(httpd!.port)/")
            return loadHTMLString(html, baseURL: url)
        }
    }
}

extension WKUserContentController {
    public func removeUserScript(script: WKUserScript) {
        let scripts = userScripts
        removeAllUserScripts()
        for i in scripts {
            if i !== script {
                addUserScript(i as! WKUserScript)
            }
        }
    }
}
