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
import XWebView

/* NOTICE:
Because XWVReflection is not public, we have to add XWVReflection.swift
along with XWVScripting.swift to the test target. So we have to use
XWebView.XWVScripting to reference the original XWVScripting protocol
in all of other test cases.
*/

class ClassForMetaObjectTest : NSObject, XWVScripting {
    dynamic var property: String = "normal"
    let readonlyProperty: Int = 0
    let excludedProperty: AnyObject? = nil

    init(argument: AnyObject?) {}
    func defaultMethod() {}
    func method(#argument: AnyObject?) {}
    func method() {}
    func excludedMethod() {}

    class func isSelectorForConstructor(selector: Selector) -> Bool {
        return selector == Selector("initWithArgument:")
    }
    class func isSelectorForDefaultMethod(selector: Selector) -> Bool {
        return selector == Selector("defaultMethod")
    }
    class func isSelectorExcludedFromScript(selector: Selector) -> Bool {
        return selector == Selector("excludedMethod")
    }
    class func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool {
        return String(UTF8String: name) == "excludedProperty"
    }
}

class XWVMetaObjectTest: XCTestCase {
    lazy var typeInfo = XWVMetaObject(plugin: ClassForMetaObjectTest.self)

    func testMembers() {
        XCTAssertTrue(typeInfo["property"] != nil)
        XCTAssertTrue(typeInfo["readonlyProperty"] != nil)
        XCTAssertTrue(typeInfo["methodWithArgument"] != nil)
        XCTAssertTrue(typeInfo["method"] != nil)
        XCTAssertTrue(typeInfo["$constructor"] != nil)
        XCTAssertTrue(typeInfo["$default"] != nil)
        XCTAssertTrue(typeInfo["excludedProperty"] == nil)
        XCTAssertTrue(typeInfo["excludedMethod"] == nil)
    }

    func testMethods() {
        XCTAssertTrue(typeInfo["methodWithArgument"]!.isMethod)
        XCTAssertTrue(typeInfo["method"]!.isMethod)
        XCTAssertTrue(typeInfo["$constructor"]!.isInitializer)
        XCTAssertTrue(typeInfo["$default"]!.isMethod)
    }

    func testProperties() {
        XCTAssertTrue(typeInfo["property"]!.isProperty)
        XCTAssertTrue(typeInfo["readonlyProperty"]!.isProperty)
    }

    func testSelectorOfMethod() {
        XCTAssertTrue(typeInfo["methodWithArgument"]?.selector == Selector("methodWithArgument:"))
        XCTAssertTrue(typeInfo["method"]?.selector == Selector("method"))
        XCTAssertTrue(typeInfo["$constructor"]?.selector == Selector("initWithArgument:"))
        XCTAssertTrue(typeInfo["$default"]?.selector == Selector("defaultMethod"))
    }

    func testGetterOfProperty() {
        XCTAssertTrue(typeInfo["property"]?.getter == Selector("property"))
        XCTAssertTrue(typeInfo["readonlyProperty"]?.getter == Selector("readonlyProperty"))
    }

    func testSetterOfProperty() {
        XCTAssertTrue(typeInfo["property"]?.setter == Selector("setProperty:"))
        XCTAssertTrue(typeInfo["readonlyProperty"]?.setter == Selector())
    }
}
