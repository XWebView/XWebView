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
    public var windowObject: XWVScriptObject {
        return XWVWindowObject(webView: self)
    }

    @discardableResult public func loadPlugin(_ object: AnyObject, namespace: String) -> XWVScriptObject? {
        let channel = XWVChannel(webView: self)
        return channel.bindPlugin(object, toNamespace: namespace)
    }

    func prepareForPlugin() {
        let key = Unmanaged<AnyObject>.passUnretained(XWVChannel.self).toOpaque()
        if objc_getAssociatedObject(self, key) != nil { return }

        let bundle = Bundle(for: XWVChannel.self)
        guard let path = bundle.path(forResource: "xwebview", ofType: "js"),
            let source = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) else {
            die("Failed to read provision script: xwebview.js")
        }
        let time = WKUserScriptInjectionTime.atDocumentStart
        let script = WKUserScript(source: source as String, injectionTime: time, forMainFrameOnly: true)
        let xwvplugin = XWVUserScript(webView: self, script: script, namespace: "XWVPlugin")
        objc_setAssociatedObject(self, key, xwvplugin, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        log("+WKWebView(\(self)) is ready for loading plugins")
    }
}

extension WKWebView {
    // Synchronized evaluateJavaScript
    // It returns nil if script is a statement or its result is undefined.
    // So, Swift cannot map the throwing method to Objective-C method.
    open func evaluateJavaScript(_ script: String) throws -> Any? {
        var result: Any?
        var error: Error?
        var done = false
        let timeout = 3.0
        if Thread.isMainThread {
            evaluateJavaScript(script) {
                (obj: Any?, err: Error?)->Void in
                result = obj
                error = err
                done = true
            }
            while !done {
                let reason = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, timeout, true)
                if reason != CFRunLoopRunResult.handledSource {
                    break
                }
            }
        } else {
            let condition: NSCondition = NSCondition()
            DispatchQueue.main.async() {
                [weak self] in
                self?.evaluateJavaScript(script) {
                    (obj: Any?, err: Error?)->Void in
                    condition.lock()
                    result = obj
                    error = err
                    done = true
                    condition.signal()
                    condition.unlock()
                }
            }
            condition.lock()
            while !done {
                if !condition.wait(until: Date(timeIntervalSinceNow: timeout) as Date) {
                    break
                }
            }
            condition.unlock()
        }
        if error != nil { throw error! }
        if !done {
            log("!Timeout to evaluate script: \(script)")
        }
        return result
    }

    // Wrapper method of synchronized evaluateJavaScript for Objective-C
    open func evaluateJavaScript(_ script: String, error: ErrorPointer) -> Any? {
        var result: Any?
        var err: Error?
        do {
            result = try evaluateJavaScript(script)
        } catch let e as NSError {
            err = e
        }
        error?.pointee = err as NSError?
        return result
    }
}
/*
@available(iOS 9.0, *)
extension WKWebView {
    // Overlay support for loading file URL
    public func loadFileURL(_ URL: URL, overlayURLs: [URL]? = nil) -> WKNavigation? {
        if let count = overlayURLs?.count, count > 0 {
            return loadFileURL(URL, allowingReadAccessTo: URL.baseURL!)
        }

        guard URL.isFileURL && URL.baseURL != nil else {
            fatalError("URL must be a relative file URL.")
        }

        guard let port = startHttpd(rootURL: URL.baseURL!, overlayURLs: overlayURLs) else { return nil }
      
        #if swift(>=2.3)
          let url = URL(string: URL.resourceSpecifier!, relativeTo: URL(string: "http://127.0.0.1:\(port)"))
        #else
          let url = URL(string: URL.resourceSpecifier, relativeTo: URL(string: "http://127.0.0.1:\(port)"))
        #endif
      
        return loadRequest(URLRequest(URL: url!))
    }

    private func startHttpd(rootURL: URL, overlayURLs: [URL]? = nil) -> in_port_t? {
        let key = unsafeAddressOf(XWVHttpServer)
        if let httpd = objc_getAssociatedObject(self, key) as? XWVHttpServer {
            if httpd.rootURL == rootURL && httpd.overlayURLs == overlayURLs ?? [] {
                return httpd.port
            }
            httpd.stop()
        }

        let httpd = XWVHttpServer(rootURL: rootURL, overlayURLs: overlayURLs)
        guard httpd.start() else { return nil }
        objc_setAssociatedObject(self, key, httpd, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        log("+HTTP server is started on port: \(httpd.port)")
        return httpd.port
    }
}*/
