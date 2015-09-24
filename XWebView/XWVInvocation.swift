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
import ObjectiveC

private let _NSInvocation: AnyClass = NSClassFromString("NSInvocation")!
private let _NSMethodSignature: AnyClass = NSClassFromString("NSMethodSignature")!

public class XWVInvocation {
    public final let target: AnyObject

    public init(target: AnyObject) {
        self.target = target
    }

    public func call(selector: Selector, withArguments arguments: [Any!]) -> Any! {
        let method = class_getInstanceMethod(target.dynamicType, selector)
        if method == nil {
            // TODO: supports forwordingTargetForSelector: of NSObject?
            (target as? NSObject)?.doesNotRecognizeSelector(selector)
            // Not an NSObject, mimic the behavior of NSObject
            let reason = "-[\(target.dynamicType) \(selector)]: unrecognized selector sent to instance \(unsafeAddressOf(target))"
            withVaList([reason]) { NSLogv("%@", $0) }
            NSException(name: NSInvalidArgumentException, reason: reason, userInfo: nil).raise()
        }

        let sig = _NSMethodSignature.signatureWithObjCTypes(method_getTypeEncoding(method))!
        let inv = _NSInvocation.invocationWithMethodSignature(sig)

        // Setup arguments
        assert(arguments.count + 2 <= Int(sig.numberOfArguments), "Too many arguments for calling -[\(target.dynamicType) \(selector)]")
        var args = [[UInt]](count: arguments.count, repeatedValue: [])
        for var i = 0; i < arguments.count; ++i {
            let type = sig.getArgumentTypeAtIndex(i + 2)
            let typeChar = Character(UnicodeScalar(UInt8(type[0])))

            // Convert argument type to adapte requirement of method.
            // Firstly, convert argument to appropriate object type.
            var argument: Any! = self.dynamicType.convertToObjectFromAnyValue(arguments[i])
            assert(argument != nil || arguments[i] == nil, "Can't convert '\(arguments[i].dynamicType)' to object type")
            if typeChar != "@", let obj: AnyObject = argument as? AnyObject {
                // Convert back to scalar type as method requires.
                argument = self.dynamicType.convertFromObject(obj, toObjCType: type)
            }

            if typeChar == "f", let float = argument as? Float {
                // Float type shouldn't be promoted to double if it is not variadic.
                args[i] = [ UInt(unsafeBitCast(float, UInt32.self)) ]
            } else if let val = argument as? CVarArgType {
                // Scalar(except float), pointer and Objective-C object types
                args[i] = val._cVarArgEncoding.map{ UInt(bitPattern: $0) }
            } else if let obj: AnyObject = argument as? AnyObject {
                // Pure swift object type
                args[i] = [ unsafeBitCast(unsafeAddressOf(obj), UInt.self) ]
            } else {
                // Nil or unsupported type
                assert(argument == nil, "Unsupported argument type '\(String(UTF8String: type))'")
                var align: Int = 0
                NSGetSizeAndAlignment(sig.getArgumentTypeAtIndex(i), nil, &align)
                args[i] = [UInt](count: align / sizeof(UInt), repeatedValue: 0)
            }
            args[i].withUnsafeBufferPointer {
                inv.setArgument(UnsafeMutablePointer($0.baseAddress), atIndex: i + 2)
            }
        }

        inv.selector = selector
        inv.invokeWithTarget(target)
        if sig.methodReturnLength == 0 { return Void() }

        // Fetch the return value
        // TODO: Methods with 'ns_returns_retained' attribute cause leak of returned object.
        let buffer = UnsafeMutablePointer<UInt8>.alloc(sig.methodReturnLength)
        inv.getReturnValue(buffer)
        defer {
            buffer.destroy()
            buffer.dealloc(sig.methodReturnLength)
        }
        return bitCast(buffer, toObjCType: sig.methodReturnType)
    }

    public func call(selector: Selector, withArguments arguments: Any!...) -> Any! {
        return call(selector, withArguments: arguments)
    }

    // Helper for Objective-C, accept ObjC 'id' instead of Swift 'Any' type for in/out parameters .
    @objc public func call(selector: Selector, withObjects objects: [AnyObject]?) -> AnyObject! {
        let args: [Any!] = objects?.map{ $0 !== NSNull() ? ($0 as Any) : nil } ?? []
        let result = call(selector, withArguments: args)
        return self.dynamicType.convertToObjectFromAnyValue(result)
    }

    // Syntactic sugar for calling method
    public subscript (selector: Selector) -> (Any!...)->Any! {
        return {
            (args: Any!...)->Any! in
            self.call(selector, withArguments: args)
        }
    }
}

extension XWVInvocation {
    // Property accessor
    public func getProperty(name: String) -> Any! {
        let getter = getterOfName(name)
        assert(getter != Selector(), "Property '\(name)' does not exist")
        return getter != Selector() ? call(getter) : Void()
    }
    public func setValue(value: Any!, forProperty name: String) {
        let setter = setterOfName(name)
        assert(setter != Selector(), "Property '\(name)' " +
                (getterOfName(name) == nil ? "does not exist" : "is readonly"))
        assert(!(value is Void))
        if setter != Selector() {
            call(setter, withArguments: value)
        }
    }

    // Syntactic sugar for accessing property
    public subscript (name: String) -> Any! {
        get {
            return getProperty(name)
        }
        set {
            setValue(newValue, forProperty: name)
        }
    }

    private func getterOfName(name: String) -> Selector {
        var getter = Selector()
        let property = class_getProperty(target.dynamicType, name)
        if property != nil {
            let attr = property_copyAttributeValue(property, "G")
            getter = Selector(attr == nil ? name : String(UTF8String: attr)!)
            free(attr)
        }
        return getter
    }
    private func setterOfName(name: String) -> Selector {
        var setter = Selector()
        let property = class_getProperty(target.dynamicType, name)
        if property != nil {
            var attr = property_copyAttributeValue(property, "R")
            if attr == nil {
                attr = property_copyAttributeValue(property, "S")
                if attr == nil {
                    setter = Selector("set\(String(name.characters.first!).uppercaseString)\(String(name.characters.dropFirst())):")
                } else {
                    setter = Selector(String(UTF8String: attr)!)
                }
            }
            free(attr)
        }
        return setter
    }
}

extension XWVInvocation {
    // Type casting and conversion, reference:
    // https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html

    // Cast bits to specified Objective-C type
    private func bitCast(buffer: UnsafePointer<Void>, toObjCType type: UnsafePointer<Int8>) -> Any? {
        switch Character(UnicodeScalar(UInt8(type[0]))) {
        case "c": return UnsafePointer<CChar>(buffer).memory
        case "i": return UnsafePointer<CInt>(buffer).memory
        case "s": return UnsafePointer<CShort>(buffer).memory
        case "l": return UnsafePointer<Int32>(buffer).memory
        case "q": return UnsafePointer<CLongLong>(buffer).memory
        case "C": return UnsafePointer<CUnsignedChar>(buffer).memory
        case "I": return UnsafePointer<CUnsignedInt>(buffer).memory
        case "S": return UnsafePointer<CUnsignedShort>(buffer).memory
        case "L": return UnsafePointer<UInt32>(buffer).memory
        case "Q": return UnsafePointer<CUnsignedLongLong>(buffer).memory
        case "f": return UnsafePointer<CFloat>(buffer).memory
        case "d": return UnsafePointer<CDouble>(buffer).memory
        case "B": return UnsafePointer<CBool>(buffer).memory
        case "v": assertionFailure("Why cast to Void type?")
        case "*": return UnsafePointer<CChar>(buffer)
        case "@": return UnsafePointer<AnyObject!>(buffer).memory
        case "#": return UnsafePointer<AnyClass!>(buffer).memory
        case ":": return UnsafePointer<Selector>(buffer).memory
        case "^", "?": return COpaquePointer(buffer)
        default:  assertionFailure("Unknown Objective-C type encoding '\(String(UTF8String: type))'")
        }
        return Void()
    }

    // Convert AnyObject to appropriate Objective-C type
    private class func convertFromObject(object: AnyObject, toObjCType type: UnsafePointer<Int8>) -> Any! {
        let num = object as? NSNumber
        switch Character(UnicodeScalar(UInt8(type[0]))) {
        case "c": return num?.charValue
        case "i": return num?.intValue
        case "s": return num?.shortValue
        case "l": return num?.intValue
        case "q": return num?.longLongValue
        case "C": return num?.unsignedCharValue
        case "I": return num?.unsignedIntValue
        case "S": return num?.unsignedShortValue
        case "L": return num?.unsignedIntValue
        case "Q": return num?.unsignedLongLongValue
        case "f": return num?.floatValue
        case "d": return num?.doubleValue
        case "B": return num?.boolValue
        case "v": return Void()
        case "*": return (object as? String)?.nulTerminatedUTF8.withUnsafeBufferPointer{ COpaquePointer($0.baseAddress) }
        case ":": return object is String ? Selector(object as! String) : Selector()
        case "@": return object
        case "#": return object as? AnyClass
        case "^", "?": return (object as? NSValue)?.pointerValue
        default:  assertionFailure("Unknown Objective-C type encoding '\(String(UTF8String: type))'")
        }
        return nil
    }

    // Convert Any value to appropriate Objective-C object
    public class func convertToObjectFromAnyValue(value: Any!) -> AnyObject! {
        if value == nil || value is AnyObject {
            // Some scalar types (Int, UInt, Bool, Float and Double) can be converted automatically by runtime.
            return value as? AnyObject
        }

        if let i8  = value as? Int8   { return NSNumber(char: i8) } else
        if let i16 = value as? Int16  { return NSNumber(short: i16) } else
        if let i32 = value as? Int32  { return NSNumber(int: i32) } else
        if let i64 = value as? Int64  { return NSNumber(longLong: i64) } else
        if let u8  = value as? UInt8  { return NSNumber(unsignedChar: u8) } else
        if let u16 = value as? UInt16 { return NSNumber(unsignedShort: u16) } else
        if let u32 = value as? UInt32 { return NSNumber(unsignedInt: u32) } else
        if let u64 = value as? UInt64 { return NSNumber(unsignedLongLong: u64) } else
        if let us  = value as? UnicodeScalar { return NSNumber(unsignedInt: us.value) } else
        if let sel = value as? Selector { return sel.description } else
        if let ptr = value as? COpaquePointer { return NSValue(pointer: UnsafePointer<Void>(ptr)) }
        //assertionFailure("Can't convert '\(value.dynamicType)' to AnyObject")
        return nil
    }
}

// Additional Swift types which can be represented in C type.
extension Bool: CVarArgType {
    public var _cVarArgEncoding: [Int] {
        return [ Int(self) ]
    }
}
extension UnicodeScalar: CVarArgType {
    public var _cVarArgEncoding: [Int] {
        return [ Int(self.value) ]
    }
}
extension Selector: CVarArgType {
    public var _cVarArgEncoding: [Int] {
        return [ unsafeBitCast(self, Int.self) ]
    }
}
