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
    class Plugin : NSObject, XWVScripting {
        @objc dynamic var property = 123
        private var expectation: XCTestExpectation?
        init(expectation: XCTestExpectation?) {
            self.expectation = expectation
        }
        @objc func defaultMethod() {
            expectation?.fulfill()
        }
        class func scriptName(for selector: Selector) -> String? {
            return selector == #selector(Plugin.defaultMethod) ? "" : nil
        }
    }

    let namespace = "xwvtest"

    func testDefaultMethod() {
        let desc = "defaultMethod"
        let script = "if (\(namespace) instanceof Function) fulfill('\(desc)')"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations()
    }
    func testCallDefaultMethod() {
        let exp = expectation(description: "callDefaultMethod")
        loadPlugin(Plugin(expectation: exp), namespace: namespace, script: "\(namespace)()")
        waitForExpectations()
    }
    func testPropertyOfDefaultMethod() {
        let desc = "propertyOfDefaultMethod"
        let script = "if (\(namespace).property == 123) fulfill('\(desc)');"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations()
    }
}
