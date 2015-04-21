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

public extension WKWebView {
    private struct key {
        static let thread = UnsafePointer<Void>(bitPattern: Selector("pluginThread").hashValue)
        static let httpd = UnsafePointer<Void>(bitPattern: Selector("pluginHTTPD").hashValue)
    }
    public var pluginThread: NSThread {
        get {
            if objc_getAssociatedObject(self, key.thread) == nil {
                prepareForPlugin()
                let thread = XWVThread()
                objc_setAssociatedObject(self, key.thread, thread, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
                return thread
            }
            return objc_getAssociatedObject(self, key.thread) as NSThread
        }
        set(thread) {
            if objc_getAssociatedObject(self, key.thread) == nil {
                prepareForPlugin()
            }
            objc_setAssociatedObject(self, key.thread, thread, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }
    }

    public func loadPlugin(object: NSObject, namespace: String) -> XWVScriptObject? {
        let channel = XWVChannel(channelID: nil, webView: self, thread: nil)
        return channel.bindPlugin(object, toNamespace: namespace)
    }

    internal func injectScript(code: String) -> WKUserScript {
        let script = WKUserScript(
            source: code,
            injectionTime: WKUserScriptInjectionTime.AtDocumentStart,
            forMainFrameOnly: false)
        configuration.userContentController.addUserScript(script)
        if self.URL != nil {
            evaluateJavaScript(code, completionHandler: { (obj, err)->Void in
                if err != nil {
                    println("ERROR: Failed to inject JavaScript API.\n\(err)")
                }
            })
        }
        return script
    }

    private func prepareForPlugin() {
        let bundle = NSBundle(forClass: XWVChannel.self)
        if let path = bundle.pathForResource("xwebview", ofType: "js") {
            if let code = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: nil) {
                injectScript(code)
            } else {
                NSException.raise("EncodingError", format: "'%@.js' should be UTF-8 encoding.", arguments: getVaList([path]))
            }
        }
    }

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

        var httpd = objc_getAssociatedObject(self, key.httpd) as? XWVHttpServer
        if httpd == nil {
            httpd = XWVHttpServer(documentRoot: readAccessURL.path)
            if !pluginThread.executing {
                pluginThread.start()
            }
            httpd!.start(pluginThread)
            objc_setAssociatedObject(self, key.httpd, httpd!, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }

        let target = URL.path!.substringFromIndex(advance(URL.path!.startIndex, countElements(readAccessURL.path!)))
        let url = NSURL(scheme: "http", host: "127.0.0.1:\(httpd!.port)", path: target)
        return loadRequest(NSURLRequest(URL: url!));
    }
}

extension WKUserContentController {
    func removeUserScript(script: WKUserScript) {
        let scripts = userScripts
        removeAllUserScripts()
        for i in scripts {
            if i !== script {
                addUserScript(i as WKUserScript)
            }
        }
    }
}
