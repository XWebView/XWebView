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
    class ObjectForLeakTest {
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

    func add(a: Int, _ b: Int) -> Int { return a + b }
    func concat(a: String, _ b: String) -> String { return a + b }
    func convert(num: NSNumber) -> Int { return num.integerValue }

    func leak(expectation: XCTestExpectation) -> AnyObject {
        return ObjectForLeakTest(expectation: expectation)
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

    func testMethods() {
        XCTAssertTrue(inv[Selector("dummy")]() is Void)
        XCTAssertTrue(inv[Selector("echoWithBool:")](Bool(true)) as? Bool == true)
        XCTAssertTrue(inv[Selector("echoWithInt:")](Int(-11)) as? Int64 == -11)
        XCTAssertTrue(inv[Selector("echoWithInt8:")](Int8(-22)) as? Int8 == -22)
        XCTAssertTrue(inv[Selector("echoWithInt16:")](Int16(-33)) as? Int16 == -33)
        XCTAssertTrue(inv[Selector("echoWithInt32:")](Int32(-44)) as? Int32 == -44)
        XCTAssertTrue(inv[Selector("echoWithInt64:")](Int64(-55)) as? Int64 == -55)
        XCTAssertTrue(inv[Selector("echoWithUint:")](UInt(11)) as? UInt64 == 11)
        XCTAssertTrue(inv[Selector("echoWithUint8:")](UInt8(22)) as? UInt8 == 22)
        XCTAssertTrue(inv[Selector("echoWithUint16:")](UInt16(33)) as? UInt16 == 33)
        XCTAssertTrue(inv[Selector("echoWithUint32:")](UInt32(44)) as? UInt32 == 44)
        XCTAssertTrue(inv[Selector("echoWithUint64:")](UInt64(55)) as? UInt64 == 55)
        XCTAssertTrue(inv[Selector("echoWithFloat:")](Float(12.34)) as? Float == 12.34)
        XCTAssertTrue(inv[Selector("echoWithDouble:")](Double(-56.78)) as? Double == -56.78)
        XCTAssertTrue(inv[Selector("echoWithUnicode:")](UnicodeScalar(78)) as? Int32 == 78)
        XCTAssertTrue(inv[Selector("echoWithString:")]("abc") as? String == "abc")
        let selector = Selector("echoWithSelector:")
        XCTAssertTrue(inv[selector](selector) as? Selector == selector)
        let cls = self.dynamicType
        XCTAssertTrue(inv[Selector("echoWithClass:")](cls) as? AnyClass === cls)

        XCTAssertTrue(inv[Selector("convert:")](UInt8(12)) as? Int64 == 12)
        XCTAssertTrue(inv[Selector("add::")](2, 3) as? Int64 == 5)
        XCTAssertTrue(inv[Selector("concat::")]("ab", "cd") as? String == "abcd")
    }

    func testProperty() {
        XCTAssertTrue(inv["integer"] as? Int64 == 123)
        inv["integer"] = 321
        XCTAssertTrue(inv["integer"] as? Int64 == 321)
    }

    func testLeak() {
        autoreleasepool {
            let expectation = expectationWithDescription("leak")
            let obj = inv.call(Selector("leak:"), withArguments: expectation) as! InvocationTarget.ObjectForLeakTest
            XCTAssertEqual(expectation, obj.expectation)
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
