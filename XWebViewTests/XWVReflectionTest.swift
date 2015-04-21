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
/* FIXME: Add XWVRefelection.swift to XWebViewTest target cause swiftc crash
class ClassForReflectionTest : NSObject, XWVScripting {
    dynamic var normalProperty: String = "normal"
    let constProperty: Int = 0
    let nonExistingProperty: AnyObject? = nil

    init(argument: AnyObject?) {
    }

    func defaultMethod() {
    }

    func method(#argument: AnyObject?) {
    }

    func method() {
    }

    func nonExistingMethod() {
    }

    class func isSelectorForConstructor(selector: Selector) -> Bool {
        return selector == Selector("initWithArgument:")
    }
    class func isSelectorForDefaultMethod(selector: Selector) -> Bool {
        return selector == Selector("defaultMethod")
    }
    class func isSelectorExcludedFromScript(selector: Selector) -> Bool {
        return selector == Selector("nonExistingMethod") || selector == Selector("init")
    }
    class func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool {
        return String(UTF8String: name)! == "nonExistingProperty"
    }
}

class XWVReflectionTest: XCTestCase {
    lazy var typeInfo = XWVReflection(plugin: ClassForReflectionTest.self)

    func testAllMembers() {
        let allMembers = typeInfo.allMembers
        XCTAssertEqual(allMembers.count, 6)
        XCTAssertTrue(contains(allMembers, "normalProperty"))
        XCTAssertTrue(contains(allMembers, "constProperty"))
        XCTAssertTrue(contains(allMembers, "methodWithArgument"))
        XCTAssertTrue(contains(allMembers, "method"))
        XCTAssertTrue(contains(allMembers, "$constructor"))
        XCTAssertTrue(contains(allMembers, "$function"))
    }

    func testAllMethods() {
        let allMethods = typeInfo.allMethods
        XCTAssertEqual(allMethods.count, 4)
        XCTAssertTrue(contains(allMethods, "methodWithArgument"))
        XCTAssertTrue(contains(allMethods, "method"))
        XCTAssertTrue(contains(allMethods, "$constructor"))
        XCTAssertTrue(contains(allMethods, "$function"))
    }

    func testAllProperties() {
        let allProperties = typeInfo.allProperties
        XCTAssertEqual(allProperties.count, 2)
        XCTAssertTrue(contains(allProperties, "normalProperty"))
        XCTAssertTrue(contains(allProperties, "constProperty"))
    }

    func testHasMember() {
        XCTAssertTrue(typeInfo.hasMember("normalProperty"))
        XCTAssertTrue(typeInfo.hasMember("constProperty"))
        XCTAssertTrue(typeInfo.hasMember("methodWithArgument"))
        XCTAssertTrue(typeInfo.hasMember("method"))
        XCTAssertTrue(typeInfo.hasMember("$constructor"))
        XCTAssertTrue(typeInfo.hasMember("$function"))
        XCTAssertFalse(typeInfo.hasMember("nonExistingMethod"))
        XCTAssertFalse(typeInfo.hasMember("nonExistingProperty"))
    }

    func testHasMethod() {
        XCTAssertTrue(typeInfo.hasMethod("methodWithArgument"))
        XCTAssertTrue(typeInfo.hasMethod("method"))
        XCTAssertTrue(typeInfo.hasMember("$constructor"))
        XCTAssertTrue(typeInfo.hasMember("$function"))
        XCTAssertFalse(typeInfo.hasMethod("nonExistingMethod"))
    }

    func testHasProperty() {
        XCTAssertTrue(typeInfo.hasProperty("normalProperty"))
        XCTAssertTrue(typeInfo.hasProperty("constProperty"))
        XCTAssertFalse(typeInfo.hasProperty("nonExistingProperty"))
    }

    func testIsReadonly() {
        XCTAssertTrue(typeInfo.isReadonly("constProperty"))
        XCTAssertFalse(typeInfo.isReadonly("normalProperty"))
    }

    func testConstructor() {
        XCTAssertEqual(typeInfo.constructor, Selector("newInstance"))
    }

    func testSelectorOfMethod() {
        XCTAssertEqual(typeInfo.selector(forMethod: "methodWithArgument"), Selector("methodWithArgument:"))
        XCTAssertEqual(typeInfo.selector(forMethod: "method"), Selector("method"))
        XCTAssertEqual(typeInfo.selector(forMethod: "$constructor"), Selector("newInstance"))
        XCTAssertEqual(typeInfo.selector(forMethod: "$function"), Selector("function"))
        XCTAssertEqual(typeInfo.selector(forMethod: "nonExistMethod"), Selector())
    }

    func testGetterOfProperty() {
        XCTAssertEqual(typeInfo.getter(forProperty: "normalProperty"), Selector("normalProperty"))
        XCTAssertEqual(typeInfo.getter(forProperty: "constProperty"), Selector("constProperty"))
        XCTAssertEqual(typeInfo.getter(forProperty: "nonExistingProperty"), Selector())
    }

    func testSetterOfProperty() {
        XCTAssertEqual(typeInfo.setter(forProperty: "normalProperty"), Selector("setNormalProperty:"))
        XCTAssertEqual(typeInfo.setter(forProperty: "constProperty"), Selector())
        XCTAssertEqual(typeInfo.setter(forProperty: "nonExistingProperty"), Selector())
    }
}*/
