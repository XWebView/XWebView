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
        func method(argument: Any?) {
            if argument as? String == "Yes" {
                expectation?.fulfill()
            }
        }
        func method(Integer: Int) {
            if Integer == 789 {
                expectation?.fulfill()
            }
        }
        func method(callback: XWVScriptObject) {
            callback.call(arguments: nil, completionHandler: nil)
        }
        func method(promiseObject: XWVScriptObject) {
            promiseObject.callMethod("resolve", with: nil, completionHandler: nil)
        }
        func method1() {
            guard let bindingObject = XWVScriptObject.bindingObject else { return }
            property = 456
            //if (bindingObject["property"] as? NSNumber)?.intValue == 456 {
            if bindingObject["property"] as? Int64 == 456 {
                expectation?.fulfill()
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
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testUpdateProperty() {
        let exp = expectation(description: "updateProperty")
        let object = Plugin(expectation: nil)
        loadPlugin(object, namespace: namespace, script: "\(namespace).property = 321") {
            $0.evaluateJavaScript("\(self.namespace).property") {
                (obj: Any?, err: Error?)->Void in
                //if (obj as? NSNumber)?.intValue == 321 && object.property == 321 {
                if obj as? Bool == true && object.property == 321 {
                    exp.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testSyncProperty() {
        let exp = expectation(description: "syncProperty")
        let object = Plugin(expectation: nil)
        loadPlugin(object, namespace: namespace, script: "") {
            object.property = 321
            $0.evaluateJavaScript("\(self.namespace).property") {
                (obj: Any?, err: Error?)->Void in
                //if (obj as? NSNumber)?.intValue == 321 {
                if obj as? Bool == true {
                    exp.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 2, handler: nil)
    }

    func testCallMethod() {
        let exp = expectation(description: "callMethod")
        loadPlugin(Plugin(expectation: exp), namespace: namespace, script: "\(namespace).method()")
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testCallMethodWithArgument() {
        let exp = expectation(description: "callMethodWithArgument")
        loadPlugin(Plugin(expectation: exp), namespace: namespace, script: "\(namespace).methodWithArgument('Yes')")
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testCallMethodWithInteger() {
        let exp = expectation(description: "callMethodWithInteger")
        loadPlugin(Plugin(expectation: exp), namespace: namespace, script: "\(namespace).methodWithInteger(789)")
        waitForExpectations(timeout: 2, handler: nil)
    }
    func testCallMethodWithCallback() {
        let desc = "callMethodWithCallback"
        let script = "\(namespace).methodWithCallback(function(){fulfill('\(desc)');})"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 3, handler: nil)
    }
    func testCallMethodWithPromise() {
        let desc = "callMethodWithPromise"
        let script = "\(namespace).methodWithPromiseObject().then(function(){fulfill('\(desc)');})"
        _ = expectation(description: desc)
        loadPlugin(Plugin(expectation: nil), namespace: namespace, script: script)
        waitForExpectations(timeout: 3, handler: nil)
    }
    func testScriptObject() {
        let desc = "scriptObject"
        let exp = expectation(description: desc)
        let plugin = Plugin(expectation: exp)
        loadPlugin(plugin, namespace: namespace, script: "\(namespace).method1();")
        waitForExpectations(timeout: 2, handler: nil)
    }
}
