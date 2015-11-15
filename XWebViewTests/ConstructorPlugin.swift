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
import XCTest
import XWebView

class ConstructorPlugin : XWVTestCase {
    class Plugin : NSObject, XWVScripting {
        dynamic var property = 123
        private var expectation: XCTestExpectation?;
        init(expectation: XCTestExpectation?) {
            self.expectation = expectation
        }
        init(value: Int) {
            property = value
        }
        func finalizeForScript() {
            if property == 456 {
                scriptObject?.webView?.evaluateJavaScript("fulfill('finalizeForScript')", completionHandler: nil)
            }
        }
        class func scriptNameForSelector(selector: Selector) -> String? {
            return selector == Selector("initWithValue:") ? "" : nil
        }
    }
    class Plugin2 : NSObject, XWVScripting {
        override init() {}
        init(expectation: AnyObject?) {
            (expectation as? XWVScriptObject)?.callMethod("fulfill", withArguments: nil, completionHandler: nil)
        }
        class func scriptNameForSelector(selector: Selector) -> String? {
            return selector == Selector("initWithExpectation:") ? "" : nil
        }
    }

    let namespace = "xwvtest"

    func testConstructor() {
        let desc = "constructor"
        let script = "if (\(namespace) instanceof Function) fulfill('\(desc)')"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testConstruction() {
        let desc = "construction"
        let script = "if (new \(namespace)(456) instanceof Promise) fulfill('\(desc)')"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
/*  func testConstruction2() {
        let desc = "construction2"
        let script = "new \(namespace)(expectation('\(desc)'))"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin2(), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }*/
    func testSyncProperties() {
        let desc = "syncProperties"
        let script = "(new \(namespace)(456)).then(function(o){if (o.property==456) fulfill('\(desc)');})"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testFinalizeForScript() {
        let desc = "finalizeForScript"
        let script = "(new \(namespace)(456)).then(function(o){o.dispose();})"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
