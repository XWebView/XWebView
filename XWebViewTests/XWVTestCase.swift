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
import XCTest
import XWebView

extension XCTestExpectation : XWVScripting {
    public class func isSelectorExcludedFromScript(selector: Selector) -> Bool {
        return selector != #selector(XCTestExpectation.fulfill) &&
               selector != #selector(NSObject.description as () -> String)
    }
    public class func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool {
        return true
    }
}

class XWVTestCase : XCTestCase, WKNavigationDelegate {
    var webview: WKWebView!
    private let namespaceForExpectation = "xwvexpectations"
    private var onReady: ((WKWebView)->Void)?

    override func setUp() {
        super.setUp()
        let source = "function fulfill(name){\(namespaceForExpectation)[name].fulfill();}\n" +
                     "function expectation(name){return \(namespaceForExpectation)[name];}\n"
        let script = WKUserScript(
            source: source,
            injectionTime: WKUserScriptInjectionTime.atDocumentStart,
            forMainFrameOnly: true)
        webview = WKWebView(frame: CGRect.zero, configuration: WKWebViewConfiguration())
        webview.configuration.userContentController.addUserScript(script)
        webview.navigationDelegate = self
    }
    override func tearDown() {
        webview = nil
        super.tearDown()
    }

    override func expectation(description: String) -> XCTestExpectation {
        let e = super.expectation(description: description)
        webview.loadPlugin(e, namespace: "\(namespaceForExpectation).\(description)")
        return e
    }
    override func waitForExpectations(timeout: TimeInterval = 9, handler: XCWaitCompletionHandler? = nil) {
        super.waitForExpectations(timeout: timeout, handler: handler)
    }

    func loadPlugin(_ object: NSObject, namespace: String, script: String) {
        loadPlugin(object, namespace: namespace, script: script, onReady: nil)
    }
    func loadPlugin(_ object: NSObject, namespace: String, script: String, onReady: ((WKWebView)->Void)?) {
        self.onReady = onReady
        webview.loadPlugin(object, namespace: namespace)
        let html = "<html><script type='text/javascript'>\(script)</script></html>"
        webview.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?(webView)
    }
}

class XWVTestCaseTest : XWVTestCase {
    class Plugin : NSObject {
    }
    func testXWVTestCase() {
        let desc = "selftest"
        _ = expectation(description: desc)
        loadPlugin(Plugin(), namespace: "xwvtest", script: "fulfill('\(desc)');")
        waitForExpectations()
    }
}
