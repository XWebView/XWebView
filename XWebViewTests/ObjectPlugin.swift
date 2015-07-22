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

class ObjectPlugin : XWVTestCase {
    class Plugin : NSObject {
        dynamic var property = 123
        private var expectation: XCTestExpectation?;
        func method() {
            expectation?.fulfill()
        }
        func method(# argument: AnyObject?) {
            if argument as? String == "Yes" {
                expectation?.fulfill()
            }
        }
        func method(# Integer: Int) {
            if Integer == 789 {
                expectation?.fulfill()
            }
        }
        func method(# callback: XWVScriptObject) {
            callback.call(arguments: nil, resultHandler: nil)
        }
        func method(# promiseObject: XWVScriptObject) {
            promiseObject.callMethod("resolve", withArguments: nil, resultHandler: nil)
        }
        func windowObject() {
            if let test: AnyObject = scriptObject?.windowObject["test"] {
                if (test as? NSNumber)?.integerValue == 234 {
                    expectation?.fulfill()
                }
            }
        }
        init(expectation: XCTestExpectation?) {
            self.expectation = expectation
        }
    }

    let namespace = "xwvtest"

    func testFetchProperty() {
        let desc = "fetchProperty"
        let script = "if (\(namespace).property == 123) fulfill('\(desc)');"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testUpdateProperty() {
        let expectation = expectationWithDescription("updateProperty")
        let object = Plugin(expectation: nil)
        loadPlugin(object, namespace: namespace, script: "\(namespace).property = 321") {
            $0.evaluateJavaScript("\(self.namespace).property") {
                (obj: AnyObject!, err: NSError!)->Void in
                if (obj as? NSNumber)?.integerValue == 321 && object.property == 321 {
                    expectation.fulfill()
                }
            }
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testSyncProperty() {
        let expectation = expectationWithDescription("syncProperty")
        let object = Plugin(expectation: nil)
        loadPlugin(object, namespace: namespace, script: "") {
            object.property = 321
            $0.evaluateJavaScript("\(self.namespace).property") {
                (obj: AnyObject!, err: NSError!)->Void in
                if (obj as? NSNumber)?.integerValue == 321 {
                    expectation.fulfill()
                }
            }
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testCallMethod() {
        let expectation = expectationWithDescription("callMethod")
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: "\(namespace).method()")
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testCallMethodWithArgument() {
        let expectation = expectationWithDescription("callMethodWithArgument")
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: "\(namespace).methodWithArgument('Yes')")
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testCallMethodWithInteger() {
        let expectation = expectationWithDescription("callMethodWithInteger")
        loadPlugin(Plugin(expectation: expectation), namespace: namespace, script: "\(namespace).methodWithInteger(789)")
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testCallMethodWithCallback() {
        let desc = "callMethodWithCallback"
        let script = "\(namespace).methodWithCallback(function(){fulfill('\(desc)');})"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(3, handler: nil)
    }
    func testCallMethodWithPromise() {
        let desc = "callMethodWithPromise"
        let script = "\(namespace).methodWithPromiseObject().then(function(){fulfill('\(desc)');})"
        let expectation = expectationWithDescription(desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectationsWithTimeout(3, handler: nil)
    }
    func testScriptObject() {
        let desc = "scriptObject"
        let expectation = expectationWithDescription(desc)
        let plugin = Plugin(expectation: expectation)
        loadPlugin(plugin as NSObject, namespace: namespace, script: "") {
            (webView)->Void in
            plugin.scriptObject?.callMethod("method", withArguments: nil)
            return
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    func testWindowObject() {
        let desc = "windowObject"
        let expectation = expectationWithDescription(desc)
        let plugin = Plugin(expectation: expectation)
        loadPlugin(plugin as NSObject, namespace: namespace, script: "window.test=234;\(namespace).windowObject()")
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
