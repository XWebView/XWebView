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
import XCTest
import XWebView

class XWebViewTests: XWVTestCase {
    class Plugin : NSObject {
    }

    func testLoadPlugin() {
        if webview.loadPlugin(Plugin(), namespace: "xwvtest") == nil {
            XCTFail("testLoadPlugin Failed")
        }
    }

    func testLoadFileURL() {
        _ = expectationWithDescription("loadFileURL")
        let bundle = NSBundle(identifier:"org.xwebview.XWebViewTests")
        if let root = bundle?.bundleURL.URLByAppendingPathComponent("www") {
            let url = root.URLByAppendingPathComponent("webviewTest.html")
            XCTAssert(url.checkResourceIsReachableAndReturnError(nil), "HTML file not found")
            webview.loadFileURL(url, allowingReadAccessToURL: root)
            waitForExpectationsWithTimeout(2, handler: nil)
        }
    }

    func testLoadFileURLWithOverlay() {
        _ = expectationWithDescription("loadFileURLWithOverlay")
        let bundle = NSBundle(identifier:"org.xwebview.XWebViewTests")
        if let root = bundle?.bundleURL.URLByAppendingPathComponent("www") {
            // create overlay file in library directory
            let library = try! NSFileManager.defaultManager().URLForDirectory(
                NSSearchPathDirectory.LibraryDirectory,
                inDomain: NSSearchPathDomainMask.UserDomainMask,
                appropriateForURL: nil,
                create: true)
            var url = library.URLByAppendingPathComponent("webviewTest.html")
            let content = "<html><script type='text/javascript'>fulfill('loadFileURLWithOverlay');</script></html>"
            try! content.writeToURL(url, atomically: false, encoding: NSUTF8StringEncoding)

            url = NSURL(string: "webviewTest.html", relativeToURL: root)!
            webview.loadFileURL(url, overlayURLs: [library])
            waitForExpectationsWithTimeout(2, handler: nil)
        }
    }

    func testLoadHTMLStringWithBaseURL() {
        _ = expectationWithDescription("loadHTMLStringWithBaseURL")
        let bundle = NSBundle(identifier:"org.xwebview.XWebViewTests")
        if let baseURL = bundle?.bundleURL.URLByAppendingPathComponent("www") {
            XCTAssert(baseURL.checkResourceIsReachableAndReturnError(nil), "Directory not found")
            webview.loadHTMLString("<html><img id='image' onload='fulfill(\"loadHTMLStringWithBaseURL\")' src='image.png'></html>", baseURL: baseURL)
            waitForExpectationsWithTimeout(2, handler: nil)
        }
    }
}
