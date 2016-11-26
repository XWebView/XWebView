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

class InvocationTarget: NSObject {
    class LeakTest: NSObject {
        let expectation: XCTestExpectation
        init(expectation: XCTestExpectation) {
            self.expectation = expectation
        }
        deinit {
            expectation.fulfill()
        }
    }

    var integer: Int = 123

    func dummy() {}
    func nullable(_ v: Any?) -> Any? { return v }
    func echo(bool b: Bool) -> Bool { return b }
    func echo(int i: Int) -> Int { return i }
    func echo(int8 i8: Int8) -> Int8 { return i8 }
    func echo(int16 i16: Int16) -> Int16 { return i16 }
    func echo(int32 i32: Int32) -> Int32 { return i32 }
    func echo(int64 i64: Int64) -> Int64 { return i64 }
    func echo(uint u: UInt) -> UInt { return u }
    func echo(uint8 u8: UInt8) -> UInt8 { return u8 }
    func echo(uint16 u16: UInt16) -> UInt16 { return u16 }
    func echo(uint32 u32: UInt32) -> UInt32 { return u32 }
    func echo(uint64 u64: UInt64) -> UInt64 { return u64 }
    func echo(float f: Float) -> Float { return f }
    func echo(double d: Double) -> Double { return d }
    func echo(unicode u: UnicodeScalar) -> UnicodeScalar { return u }
    func echo(string s: String) -> String { return s }
    func echo(selector s: Selector) -> Selector { return s }
    func echo(`class` c: AnyClass) -> AnyClass { return c }

    func add(_ a: Int, _ b: Int) -> Int { return a + b }
    func concat(_ a: String, _ b: String) -> String { return a + b }
    func convert(_ num: NSNumber) -> Int { return num.intValue }

    func _new(_ expectation: XCTestExpectation) -> LeakTest {
        return LeakTest(expectation: expectation)
    }
}

class InvocationTests : XCTestCase {
    var target: InvocationTarget!
    var inv: XWVInvocation!
    override func setUp() {
        target = InvocationTarget()
        inv = XWVInvocation(target: target)
    }
    override func tearDown() {
        target = nil
        inv = nil
    }

    #if arch(x86_64) || arch(arm64)
    typealias XInt = Int64
    typealias XUInt = UInt64
    #else
    typealias XInt = Int32
    typealias XUInt = UInt32
    #endif

    func testMethods() {
        XCTAssertTrue(inv[ #selector(InvocationTarget.dummy)]() is Void)
        #if arch(x86_64) || arch(arm64)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(bool:))](Bool(true)) as? Bool == true)
        #else
        // http://stackoverflow.com/questions/26459754/bool-encoding-wrong-from-nsmethodsignature
        XCTAssertTrue(inv[Selector("echoWithBool:")](Bool(true)) as? Int8 == 1)
        #endif
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(int:))](Int(-11)) as? XInt == -11)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(int8:))](Int8(-22)) as? Int8 == -22)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(int16:))](Int16(-33)) as? Int16 == -33)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(int32:))](Int32(-44)) as? Int32 == -44)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(int64:))](Int64(-55)) as? Int64 == -55)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(uint:))](UInt(11)) as? XUInt == 11)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(uint8:))](UInt8(22)) as? UInt8 == 22)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(uint16:))](UInt16(33)) as? UInt16 == 33)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(uint32:))](UInt32(44)) as? UInt32 == 44)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(uint64:))](UInt64(55)) as? UInt64 == 55)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(float:))](Float(12.34)) as? Float == 12.34)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(double:))](Double(-56.78)) as? Double == -56.78)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(unicode:))](UnicodeScalar(78)) as? Int32 == 78)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(string:))]("abc") as? String == "abc")
        let selector = #selector(InvocationTarget.echo(selector:))
        XCTAssertTrue(inv[selector](selector) as? Selector == selector)
        let cls = type(of: self)
        XCTAssertTrue(inv[ #selector(InvocationTarget.echo(class:))](cls) as? AnyClass === cls)

        XCTAssertTrue(inv[ #selector(InvocationTarget.convert(_:))](UInt8(12)) as? XInt == 12)
        XCTAssertTrue(inv[ #selector(InvocationTarget.add(_:_:))](2, 3) as? XInt == 5)
        XCTAssertTrue(inv[ #selector(InvocationTarget.concat(_:_:))]("ab", "cd") as? String == "abcd")
    }

    func testProperty() {
        XCTAssertTrue(inv["integer"] as? XInt == 123)
        inv["integer"] = 321
        XCTAssertTrue(inv["integer"] as? XInt == 321)
    }

    func testNullable() {
        XCTAssertTrue(inv[ #selector(InvocationTarget.nullable(_:))]("abc") as? String == "abc")
        XCTAssertTrue(inv[ #selector(InvocationTarget.nullable(_:))](nil) == nil)
    }

    func testLeak1() {
        autoreleasepool {
            let exp = expectation(description: "leak")
            let obj = inv[ #selector(InvocationTarget._new(_:))](exp) as? InvocationTarget.LeakTest
            XCTAssertEqual(exp, obj!.expectation)
        }
        waitForExpectations(timeout: 3)
    }

    func testLeak2() {
        autoreleasepool {
            let exp = expectation(description: "leak")
            let obj = createInstance(of: InvocationTarget.LeakTest.self, by: #selector(InvocationTarget.LeakTest.init(expectation:)), with: [exp]) as? InvocationTarget.LeakTest
            XCTAssertEqual(exp, obj!.expectation)
        }
        waitForExpectations(timeout: 3)
    }
}
