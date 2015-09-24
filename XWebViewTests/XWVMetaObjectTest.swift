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

import XCTest
@testable import XWebView

class XWVMetaObjectTest: XCTestCase {
    func testForMethod() {
        class TestForMethod {
            @objc init() {}
            @objc func method() {}
            @objc func method(argument argument: AnyObject?) {}
            @objc func _method() {}
        }
        let meta = XWVMetaObject(plugin: TestForMethod.self)
        if let member = meta["method"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("method"))
            XCTAssertTrue(member.type == "#0a")
        } else {
            XCTFail()
        }
        if let member = meta["methodWithArgument"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("methodWithArgument:"))
            XCTAssertTrue(member.type == "#1a")
        } else {
            XCTFail()
        }
        XCTAssertTrue(meta["init"] == nil)
        XCTAssertTrue(meta["_method"] == nil)
    }

    func testForProperty() {
        class TestForProperty {
            @objc var property = 0
            @objc let readonlyProperty = 0
            @objc var _property = 0
        }
        let meta = XWVMetaObject(plugin: TestForProperty.self)
        if let member = meta["property"] {
            XCTAssertTrue(member.isProperty)
            XCTAssertTrue(member.getter == Selector("property"))
            XCTAssertTrue(member.setter == Selector("setProperty:"))
        } else {
            XCTFail()
        }
        if let member = meta["readonlyProperty"] {
            XCTAssertTrue(member.isProperty)
            XCTAssertTrue(member.getter == Selector("readonlyProperty"))
            XCTAssertTrue(member.setter == Selector())
        } else {
            XCTFail()
        }
        XCTAssertTrue(meta["_property"] == nil)
    }

    func testForPromise() {
        class TestForPromise {
            @objc func method(promiseObject promiseObject: XWVScriptObject) {}
            @objc func method(argument argument: AnyObject?, promiseObject: XWVScriptObject) {}
        }
        let meta = XWVMetaObject(plugin: TestForPromise.self)
        if let member = meta["methodWithPromiseObject"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("methodWithPromiseObject:"))
            XCTAssertTrue(member.type == "#1p")
        } else {
            XCTFail()
        }
        if let member = meta["methodWithArgument"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("methodWithArgument:promiseObject:"))
            XCTAssertTrue(member.type == "#2p")
        } else {
            XCTFail()
        }
    }
    func testForExclusion() {
        class TestForExclusion: XWVScripting {
            @objc let property = 0
            @objc func method() {}
            @objc class func isSelectorExcludedFromScript(selector: Selector) -> Bool {
                return selector == Selector("method")
            }
            @objc class func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool {
                return String(UTF8String: name) == "property"
            }
        }
        let meta = XWVMetaObject(plugin: TestForExclusion.self)
        XCTAssertTrue(meta["property"] == nil)
        XCTAssertTrue(meta["method"] == nil)
    }

    func testForFunction() {
        class TestForFunction : XWVScripting {
            @objc func defaultMethod() {}
            @objc class func scriptNameForSelector(selector: Selector) -> String? {
                return selector == Selector("defaultMethod") ? "" : nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForFunction.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("defaultMethod"))
            XCTAssertTrue(member.type == "#0a")
        } else {
            XCTFail()
        }
    }

    func testForFunction2() {
        class TestForFunction : XWVScripting {
            @objc func invokeDefaultMethodWithArguments(args: [AnyObject]!) -> AnyObject! {
                return nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForFunction.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == Selector("invokeDefaultMethodWithArguments:"))
            XCTAssertTrue(member.type == "")
        } else {
            XCTFail()
        }
    }

    func testForConstructor() {
        class TestForConstructor : XWVScripting {
            @objc init(argument: AnyObject?) {}
            @objc class func scriptNameForSelector(selector: Selector) -> String? {
                return selector == Selector("initWithArgument:") ? "" : nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForConstructor.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isInitializer)
            XCTAssertTrue(member.selector == Selector("initWithArgument:"))
            XCTAssertTrue(member.type == "#2p")
        } else {
            XCTFail()
        }
    }

    func testForConstructor2() {
        class TestForConstructor {
            @objc init(byScriptWithArguments: [AnyObject]) {}
        }
        let meta = XWVMetaObject(plugin: TestForConstructor.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isInitializer)
            XCTAssertTrue(member.selector == Selector("initByScriptWithArguments:"))
            XCTAssertTrue(member.type == "#p")
        } else {
            XCTFail()
        }
    }
}
