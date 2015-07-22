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

class FunctionPlugin : XWVTestCase {
    class Plugin : NSObject, XWebView.XWVScripting {
        dynamic var property = 123
        private var expectation: XCTestExpectation?
        init(expectation: XCTestExpectation?) {
            self.expectation = expectation
        }
        func defaultMethod() {
            expectation?.fulfill()
        }
        class func scriptNameForSelector(selector: Selector) -> String? {
            return selector == Selector("defaultMethod") ? "" : nil
        }
    }

    let namespace = "xwvtest"

    func testDefaultMethod() {
        let desc = "defaultMethod"
        let script = "if (\(namespace) instanceof Function) fulfill('\(desc)')"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testCallDefaultMethod() {
        let expectation = expectationWithDescription("callDefaultMethod")
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: "\(namespace)()")
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testPropertyOfDefaultMethod() {
        let desc = "propertyOfDefaultMethod"
        let script = "if (\(namespace).property == 123) fulfill('\(desc)');"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
