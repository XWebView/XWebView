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
    class Plugin0 : NSObject, XWVScripting {
        init(expectation: Any?) {
            if let e = expectation as? XWVScriptObject {
                e.callMethod("fulfill", with: nil, completionHandler: nil)
            }
        }
        class func scriptName(for selector: Selector) -> String? {
            return selector == #selector(Plugin0.init(expectation:)) ? "" : nil
        }
    }
    class Plugin1 : NSObject, XWVScripting {
        dynamic var property: Int
        init(value: Int) {
            property = value
        }
        class func scriptName(for selector: Selector) -> String? {
            return selector == #selector(Plugin1.init(value:)) ? "" : nil
        }
    }
    class Plugin2 : NSObject, XWVScripting {
        private let expectation: XWVScriptObject?
        init(expectation: Any?) {
            self.expectation = expectation as? XWVScriptObject
        }
        func finalizeForScript() {
            expectation?.callMethod("fulfill", with: nil, completionHandler: nil)
        }
        class func scriptName(for selector: Selector) -> String? {
            return selector == #selector(Plugin2.init(expectation:)) ? "" : nil
        }
    }

    let namespace = "xwvtest"

    func testConstructor() {
        let desc = "constructor"
        let script = "if (\(namespace) instanceof Function) fulfill('\(desc)')"
        _ = expectation(description: desc)
        loadPlugin(Plugin0(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testConstruction() {
        let desc = "construction"
        let script = "new \(namespace)(expectation('\(desc)'))"
        _ = expectation(description: desc)
        loadPlugin(Plugin0(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testSyncProperties() {
        let desc = "syncProperties"
        let script = "(new \(namespace)(456)).then(function(o){if (o.property==456) fulfill('\(desc)');})"
        _ = expectation(description: desc)
        loadPlugin(Plugin1(value: 123), namespace: namespace, script: script)
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testFinalizeForScript() {
        let desc = "finalizeForScript"
        let script = "(new \(namespace)(expectation('\(desc)'))).then(function(o){o.dispose();})"
        _ = expectation(description: desc)
        loadPlugin(Plugin2(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 2, handler: nil)
    }
}
