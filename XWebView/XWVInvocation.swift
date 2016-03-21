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

public class XWVInvocation: NSObject {
    public final let target: AnyObject
    private let thread: NSThread?

    public init(target: AnyObject, thread: NSThread? = nil) {
        self.target = target
        self.thread = thread
    }

    public class func construct(`class`: AnyClass, initializer: Selector, withArguments arguments: [Any!] = []) -> AnyObject? {
        guard let obj = invoke(`class`, selector: Selector("alloc"), withArguments: []) as? AnyObject else {
            return nil
        }
        return invoke(obj, selector: initializer, withArguments: arguments) as? AnyObject
    }

    public func call(selector: Selector, withArguments arguments: [Any!] = []) -> Any! {
        return invoke(target, selector: selector, withArguments: arguments, onThread: thread)
    }
    // No callback support, so return value is expected to lose.
    public func asyncCall(selector: Selector, withArguments arguments: [Any!] = []) {
        invoke(target, selector: selector, withArguments: arguments, onThread: thread, waitUntilDone: false)
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
            call(setter, withArguments: [value])
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

// Notice: The target method must strictly obey the Cocoa convention.
// Do NOT call method with explicit family control or parameter attribute of ARC.
// See: http://clang.llvm.org/docs/AutomaticReferenceCounting.html
private let _NSMethodSignature: AnyClass = NSClassFromString("NSMethodSignature")!
private let _NSInvocation: AnyClass = NSClassFromString("NSInvocation")!

class MethodSignatureTrick : NSObject {
    private static var initialized: dispatch_once_t = 0
    override class func initialize() {
        dispatch_once(&initialized) {
            let sel = #selector(signatureWithObjCTypes(_:))
            let method = class_getClassMethod(_NSMethodSignature, sel)
            let imp = method_getImplementation(method)
            method_setImplementation(class_getClassMethod(self, sel), imp)

            let numberOfArgumentsSel = #selector(numberOfArguments)
            let numberOfArgumentsMethod = class_getInstanceMethod(_NSInvocation, numberOfArgumentsSel)
            let numberOfArgumentsImp = method_getImplementation(numberOfArgumentsMethod)
            method_setImplementation(numberOfArgumentsMethod, numberOfArgumentsImp)

            let getArgumentTypeAtIndexSel = #selector(getArgumentTypeAtIndex(_:))
            let getArgumentTypeAtIndexMethod = class_getInstanceMethod(_NSInvocation, getArgumentTypeAtIndexSel)
            let getArgumentTypeAtIndexImp = method_getImplementation(getArgumentTypeAtIndexMethod)
            method_setImplementation(getArgumentTypeAtIndexMethod, getArgumentTypeAtIndexImp)

            let methodReturnLengthSel = #selector(methodReturnLength)
            let methodReturnLengthMethod = class_getInstanceMethod(_NSInvocation, methodReturnLengthSel)
            let methodReturnLengthImp = method_getImplementation(methodReturnLengthMethod)
            method_setImplementation(methodReturnLengthMethod, methodReturnLengthImp)

            let methodReturnTypeSel = #selector(methodReturnType)
            let methodReturnTypeMethod = class_getInstanceMethod(_NSInvocation, methodReturnTypeSel)
            let methodReturnTypeImp = method_getImplementation(methodReturnTypeMethod)
            method_setImplementation(methodReturnTypeMethod, methodReturnTypeImp)
        }
    }

    dynamic class func signatureWithObjCTypes(type: UnsafePointer<Int8>) -> MethodSignatureTrick {
        assertionFailure("unreachable")
        return MethodSignatureTrick()
    }

    dynamic func numberOfArguments() -> Int {
        assertionFailure("unreachable")
        return 0
    }

    dynamic func methodReturnLength() -> Int {
        assertionFailure("unreachable")
        return 0
    }

    dynamic func methodReturnType() -> UnsafePointer<Int8> {
        assertionFailure("unreachable")
        return nil
    }

    dynamic func getArgumentTypeAtIndex(index: Int) -> UnsafePointer<Int8> {
        assertionFailure("unreachable")
        return nil
    }
}

class InvocationTrick : NSObject {
    private static var initialized: dispatch_once_t = 0
    override class func initialize() {
        dispatch_once(&initialized) {
            let sel = #selector(invocationWithMethodSignature(_:))
            let method = class_getClassMethod(_NSInvocation, sel)
            let imp = method_getImplementation(method)
            method_setImplementation(class_getClassMethod(self, sel), imp)

            let setArgumentAtIndexSel = #selector(setArgument(_:atIndex:))
            let setArgumentAtIndexMethod = class_getInstanceMethod(_NSInvocation, setArgumentAtIndexSel)
            let setArgumentAtIndexImp = method_getImplementation(setArgumentAtIndexMethod)
            method_setImplementation(setArgumentAtIndexMethod, setArgumentAtIndexImp)

            let selectorSel = #selector(setSelector(_:))
            let selectorMethod = class_getInstanceMethod(_NSInvocation, selectorSel)
            let selectorImp = method_getImplementation(selectorMethod)
            method_setImplementation(selectorMethod, selectorImp)

            let invokeWithTargetSel = #selector(invokeWithTarget(_:))
            let invokeWithTargetMethod = class_getInstanceMethod(_NSInvocation, invokeWithTargetSel)
            let invokeWithTargetImp = method_getImplementation(invokeWithTargetMethod)
            method_setImplementation(invokeWithTargetMethod, invokeWithTargetImp)

            let retainArgumentsSel = #selector(retainArguments)
            let retainArgumentsMethod = class_getInstanceMethod(_NSInvocation, retainArgumentsSel)
            let retainArgumentsImp = method_getImplementation(retainArgumentsMethod)
            method_setImplementation(retainArgumentsMethod, retainArgumentsImp)

            let getReturnValueSel = #selector(getReturnValue(_:))
            let getReturnValueMethod = class_getInstanceMethod(_NSInvocation, getReturnValueSel)
            let getReturnValueImp = method_getImplementation(getReturnValueMethod)
            method_setImplementation(getReturnValueMethod, getReturnValueImp)
         }
    }

    dynamic class func invocationWithMethodSignature(sig: NSObject?) -> InvocationTrick {
        assertionFailure("unreachable")
        return InvocationTrick()
    }

    dynamic func setArgument(argument: UnsafePointer<Int8>, atIndex index: Int) {
        assertionFailure("unreachable")

    }

    dynamic func setSelector(selector: Selector) {
        assertionFailure("unreachable")
    }

    dynamic func invokeWithTarget(target: AnyObject) {
        assertionFailure("unreachable")
    }

    dynamic func retainArguments() {
        assertionFailure("unreachable")
    }

    dynamic func getReturnValue(buffer: UnsafeMutablePointer<UInt8>) {
        assertionFailure("unreachable")
    }
}

public func invoke(target: AnyObject, selector: Selector, withArguments arguments: [Any!], onThread thread: NSThread? = nil, waitUntilDone wait: Bool = true) -> Any! {
    let method = class_getInstanceMethod(target.dynamicType, selector)
    if method == nil {
        // TODO: supports forwordingTargetForSelector: of NSObject?
        (target as? NSObject)?.doesNotRecognizeSelector(selector)
        // Not an NSObject, mimic the behavior of NSObject
        let reason = "-[\(target.dynamicType) \(selector)]: unrecognized selector sent to instance \(unsafeAddressOf(target))"
        withVaList([reason]) { NSLogv("%@", $0) }
        NSException(name: NSInvalidArgumentException, reason: reason, userInfo: nil).raise()
    }

    let sig = MethodSignatureTrick.signatureWithObjCTypes(method_getTypeEncoding(method))
    let inv = InvocationTrick.invocationWithMethodSignature(sig)

    // Setup arguments
    assert(arguments.count + 2 <= Int(sig.numberOfArguments()), "Too many arguments for calling -[\(target.dynamicType) \(selector)]")
    var args = [[Int]](count: arguments.count, repeatedValue: [])
    for var i = 0; i < arguments.count; ++i {
        let type = sig.getArgumentTypeAtIndex(i + 2)
        let typeChar = Character(UnicodeScalar(UInt8(type[0])))

        // Convert argument type to adapte requirement of method.
        // Firstly, convert argument to appropriate object type.
        var argument: Any! = castToObjectFromAny(arguments[i])
        assert(argument != nil || arguments[i] == nil, "Can't convert '\(arguments[i].dynamicType)' to object type")
        if typeChar != "@", let obj: AnyObject = argument as? AnyObject {
            // Convert back to scalar type as method requires.
            argument = castToAnyFromObject(obj, withObjCType: type)
        }

        if typeChar == "f", let float = argument as? Float {
            // Float type shouldn't be promoted to double if it is not variadic.
            args[i] = [ Int(unsafeBitCast(float, Int32.self)) ]
        } else if let val = argument as? CVarArgType {
            // Scalar(except float), pointer and Objective-C object types
            args[i] = val._cVarArgEncoding
        } else if let obj: AnyObject = argument as? AnyObject {
            // Pure swift object type
            args[i] = [ unsafeBitCast(unsafeAddressOf(obj), Int.self) ]
        } else {
            // Nil or unsupported type
            assert(argument == nil, "Unsupported argument type '\(String(UTF8String: type))'")
            var align: Int = 0
            NSGetSizeAndAlignment(sig.getArgumentTypeAtIndex(i), nil, &align)
            args[i] = [Int](count: align / sizeof(Int), repeatedValue: 0)
        }
        args[i].withUnsafeBufferPointer {
            inv.setArgument(UnsafeMutablePointer($0.baseAddress), atIndex: i + 2)
        }
    }

    if selector.family == .init_ {
        // Self should be consumed for method belongs to init famlily
        _ = Unmanaged.passRetained(target)
    }
    inv.setSelector(selector)

    if thread == nil || (thread == NSThread.currentThread() && wait) {
        inv.invokeWithTarget(target)
    } else {
        let selector = Selector("invokeWithTarget:")
        inv.retainArguments()
        inv.performSelector(selector, onThread: thread!, withObject: target, waitUntilDone: wait)
        guard wait else { return Void() }
    }
    if sig.methodReturnLength() == 0 { return Void() }

    // Fetch the return value
    let buffer = UnsafeMutablePointer<UInt8>.alloc(sig.methodReturnLength())
    inv.getReturnValue(buffer)
    defer {
        if sig.methodReturnType()[0] == 0x40 && selector.returnsRetained {
            // To balance the retained return value
            Unmanaged.passUnretained(UnsafePointer<AnyObject>(buffer).memory).release()
        }
        buffer.dealloc(sig.methodReturnLength())
    }
    return castToAnyFromBytes(buffer, withObjCType: sig.methodReturnType())
}


// Convert byte array to specified Objective-C type
// See: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
private func castToAnyFromBytes(bytes: UnsafePointer<Void>, withObjCType type: UnsafePointer<Int8>) -> Any! {
    switch Character(UnicodeScalar(UInt8(type[0]))) {
    case "c": return UnsafePointer<CChar>(bytes).memory
    case "i": return UnsafePointer<CInt>(bytes).memory
    case "s": return UnsafePointer<CShort>(bytes).memory
    case "l": return UnsafePointer<Int32>(bytes).memory
    case "q": return UnsafePointer<CLongLong>(bytes).memory
    case "C": return UnsafePointer<CUnsignedChar>(bytes).memory
    case "I": return UnsafePointer<CUnsignedInt>(bytes).memory
    case "S": return UnsafePointer<CUnsignedShort>(bytes).memory
    case "L": return UnsafePointer<UInt32>(bytes).memory
    case "Q": return UnsafePointer<CUnsignedLongLong>(bytes).memory
    case "f": return UnsafePointer<CFloat>(bytes).memory
    case "d": return UnsafePointer<CDouble>(bytes).memory
    case "B": return UnsafePointer<CBool>(bytes).memory
    case "v": assertionFailure("Why cast to Void type?")
    case "*": return UnsafePointer<CChar>(bytes)
    case "@": return UnsafePointer<AnyObject!>(bytes).memory
    case "#": return UnsafePointer<AnyClass!>(bytes).memory
    case ":": return UnsafePointer<Selector>(bytes).memory
    case "^": return UnsafePointer<COpaquePointer>(bytes).memory
    default:  assertionFailure("Unknown Objective-C type encoding '\(String(UTF8String: type))'")
    }
    return Void()
}

// Convert AnyObject to specified Objective-C type
private func castToAnyFromObject(object: AnyObject, withObjCType type: UnsafePointer<Int8>) -> Any! {
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
    case "^": return (object as? NSValue)?.pointerValue
    default:  assertionFailure("Unknown Objective-C type encoding '\(String(UTF8String: type))'")
    }
    return nil
}

// Convert Any value to appropriate Objective-C object
public func castToObjectFromAny(value: Any!) -> AnyObject! {
    if value == nil || value is AnyObject {
        // Some scalar types (Int, UInt, Bool, Float and Double) can be converted automatically by runtime.
        return value as? AnyObject
    }

    if let v = value as? Int8           { return NSNumber(char: v) } else
    if let v = value as? Int16          { return NSNumber(short: v) } else
    if let v = value as? Int32          { return NSNumber(int: v) } else
    if let v = value as? Int64          { return NSNumber(longLong: v) } else
    if let v = value as? UInt8          { return NSNumber(unsignedChar: v) } else
    if let v = value as? UInt16         { return NSNumber(unsignedShort: v) } else
    if let v = value as? UInt32         { return NSNumber(unsignedInt: v) } else
    if let v = value as? UInt64         { return NSNumber(unsignedLongLong: v) } else
    if let v = value as? UnicodeScalar  { return NSNumber(unsignedInt: v.value) } else
    if let s = value as? Selector       { return s.description } else
    if let p = value as? COpaquePointer { return NSValue(pointer: UnsafePointer<Void>(p)) }
    assert(value is Void, "Can't convert '\(value.dynamicType)' to AnyObject")
    return nil
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

private extension Selector {
    enum Family : Int8 {
        case none        = 0
        case alloc       = 97
        case copy        = 99
        case mutableCopy = 109
        case init_       = 105
        case new         = 110
    }
    static var prefixes : [[CChar]] = [
        /* alloc */       [97, 108, 108, 111, 99],
        /* copy */        [99, 111, 112, 121],
        /* mutableCopy */ [109, 117, 116, 97, 98, 108, 101, 67, 111, 112, 121],
        /* init */        [105, 110, 105, 116],
        /* new */         [110, 101, 119]
    ]
    var family: Family {
        // See: http://clang.llvm.org/docs/AutomaticReferenceCounting.html#id34
        var s = unsafeBitCast(self, UnsafePointer<Int8>.self)
        while s.memory == 0x5f { ++s }  // skip underscore
        for p in Selector.prefixes {
            let lowercase: Range<CChar> = 97...122
            let l = p.count
            if strncmp(s, p, l) == 0 && !lowercase.contains(s.advancedBy(l).memory) {
                return Family(rawValue: s.memory)!
            }
        }
        return .none
    }
    var returnsRetained: Bool {
        return family != .none
    }
}
