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

class XWVScriptingTest : XWVTestCase {
    class Plugin : NSObject, XWVScripting {
        let expectation: XCTestExpectation?
        init(expectation: XCTestExpectation?) {
            self.expectation = expectation
        }
        func rewriteGeneratedStub(stub: String, forKey key: String) -> String {
            switch key {
            case ".global": return stub + "window.stub = true;\n"
            case ".local": return stub + "exports.abc = true;\n"
            default: return stub
            }
        }
        func finalizeForScript() {
            expectation?.fulfill()
        }
        class func isSelectorExcludedFromScript(selector: Selector) -> Bool {
            return selector == #selector(Plugin.init(expectation:))
        }
        class func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool {
            return String(UTF8String: name) == "expectation"
        }
    }

    let namespace = "xwvtest"

    func testRewriteGeneratedStub() {
        let desc = "javascriptStub"
        let script = "if (window.stub && \(namespace).abc) fulfill('\(desc)');"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testFinalizeForScript() {
        let desc = "finalizeForScript"
        let script = "\(namespace).dispose()"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testIsSelectorExcluded() {
        let desc = "isSelectorExcluded"
        let script = "if (\(namespace).initWithExpectation == undefined) fulfill('\(desc)')"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testIsKeyExcluded() {
        let desc = "isKeyExcluded"
        let script = "if (!\(namespace).hasOwnProperty('expectation')) fulfill('\(desc)')"
        _ = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
