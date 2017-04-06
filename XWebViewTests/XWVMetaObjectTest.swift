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
            @objc func method(argument: Any?) {}
            @objc func _method() {}
        }
        let meta = XWVMetaObject(plugin: TestForMethod.self)
        if let member = meta["method"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(TestForMethod.method as (TestForMethod) -> () -> ()))
            XCTAssertTrue(member.type == "#0a")
        } else {
            XCTFail()
        }
        if let member = meta["methodWithArgument"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(TestForMethod.method(argument:)))
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
            XCTAssertTrue(member.getter == #selector(getter: TestForProperty.property))
            XCTAssertTrue(member.setter == #selector(setter: TestForProperty.property))
        } else {
            XCTFail()
        }
        if let member = meta["readonlyProperty"] {
            XCTAssertTrue(member.isProperty)
            XCTAssertTrue(member.getter == #selector(getter: TestForProperty.readonlyProperty))
            XCTAssertTrue(member.setter == nil)
        } else {
            XCTFail()
        }
        XCTAssertTrue(meta["_property"] == nil)
    }

    func testForPromise() {
        class TestForPromise {
            @objc func method(promiseObject: XWVScriptObject) {}
            @objc func method(argument: Any?, promiseObject: XWVScriptObject) {}
        }
        let meta = XWVMetaObject(plugin: TestForPromise.self)
        if let member = meta["methodWithPromiseObject"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(TestForPromise.method(promiseObject:)))
            XCTAssertTrue(member.type == "#1p")
        } else {
            XCTFail()
        }
        if let member = meta["methodWithArgument"] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(TestForPromise.method(argument:promiseObject:)))
            XCTAssertTrue(member.type == "#2p")
        } else {
            XCTFail()
        }
    }
    func testForExclusion() {
        class TestForExclusion: XWVScripting {
            @objc let property = 0
            @objc func method() {}
            @objc class func isSelectorExcluded(fromScript selector: Selector) -> Bool {
                return selector == #selector(TestForExclusion.method)
            }
            @objc class func isKeyExcluded(fromScript name: UnsafePointer<Int8>) -> Bool {
                return String(cString: name) == "property"
            }
        }
        let meta = XWVMetaObject(plugin: TestForExclusion.self)
        XCTAssertTrue(meta["property"] == nil)
        XCTAssertTrue(meta["method"] == nil)
    }

    func testForSpecialExclusion() {
        class TestForExclusion: XWVScripting {
            @objc deinit {
                print("ensuring deinit is not optimized out")
            }
            @objc func copy() -> Any {
                return TestForExclusion()
            }
            @objc func copy(with zone: NSZone? = nil) -> Any {
                return TestForExclusion()
            }
            @objc func method() {}
        }
        let meta = XWVMetaObject(plugin: TestForExclusion.self)
        XCTAssertTrue(meta["dealloc"] == nil)
        XCTAssertTrue(meta["deinit"] == nil)
        XCTAssertTrue(meta["copy"] == nil)
    }

    func testForFunction() {
        class TestForFunction : XWVScripting {
            @objc func defaultMethod() {}
            @objc class func scriptName(for selector: Selector) -> String? {
                return selector == #selector(TestForFunction.defaultMethod) ? "" : nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForFunction.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(TestForFunction.defaultMethod))
            XCTAssertTrue(member.type == "#0a")
        } else {
            XCTFail()
        }
    }

    func testForFunction2() {
        class TestForFunction : XWVScripting {
            @objc func invokeDefaultMethod(withArguments args: [Any]!) -> Any! {
                return nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForFunction.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isMethod)
            XCTAssertTrue(member.selector == #selector(XWVScripting.invokeDefaultMethod(withArguments:)))
            XCTAssertTrue(member.type == "")
        } else {
            XCTFail()
        }
    }

    func testForConstructor() {
        class TestForConstructor : XWVScripting {
            @objc init(argument: Any?) {}
            @objc class func scriptName(for selector: Selector) -> String? {
                return selector == #selector(TestForConstructor.init(argument:)) ? "" : nil
            }
        }
        let meta = XWVMetaObject(plugin: TestForConstructor.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isInitializer)
            XCTAssertTrue(member.selector == #selector(TestForConstructor.init(argument:)))
            XCTAssertTrue(member.type == "#2p")
        } else {
            XCTFail()
        }
    }

    func testForConstructor2() {
        class TestForConstructor {
            @objc init(byScriptWithArguments: [Any]) {}
        }
        let meta = XWVMetaObject(plugin: TestForConstructor.self)
        if let member = meta[""] {
            XCTAssertTrue(member.isInitializer)
            XCTAssertTrue(member.selector == #selector(TestForConstructor.init(byScriptWithArguments:)))
            XCTAssertTrue(member.type == "#p")
        } else {
            XCTFail()
        }
    }
}
