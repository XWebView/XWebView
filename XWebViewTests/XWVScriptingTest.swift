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
        func rewriteStub(_ stub: String, forKey key: String) -> String {
            switch key {
            case ".global": return stub + "window.stub = true;\n"
            case ".local": return stub + "exports.abc = true;\n"
            default: return stub
            }
        }
        func finalizeForScript() {
            expectation?.fulfill()
        }
        class func isSelectorExcluded(fromScript selector: Selector) -> Bool {
            return selector == #selector(Plugin.init(expectation:))
        }
        class func isKeyExcluded(fromScript name: UnsafePointer<Int8>) -> Bool {
            return String(cString: name) == "expectation"
        }
    }

    let namespace = "xwvtest"

    func testRewriteStub() {
        let desc = "javascriptStub"
        let script = "if (window.stub && \(namespace).abc) fulfill('\(desc)');"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations()
    }

    func testFinalizeForScript() {
        let desc = "finalizeForScript"
        let script = "\(namespace).dispose()"
        let expectation = super.expectation(description: desc)
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: script)
        waitForExpectations()
    }
    func testIsSelectorExcluded() {
        let desc = "isSelectorExcluded"
        let script = "if (\(namespace).initWithExpectation == undefined) fulfill('\(desc)')"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations()
    }
    func testIsKeyExcluded() {
        let desc = "isKeyExcluded"
        let script = "if (!\(namespace).hasOwnProperty('expectation')) fulfill('\(desc)')"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations()
    }
}
