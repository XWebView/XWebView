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

@objc protocol NSMethodSignatureProtocol {
    static func signature(objCTypes: UnsafePointer<CChar>) -> NSMethodSignatureProtocol
    func getArgumentType(atIndex idx: UInt) -> UnsafePointer<CChar>
    var numberOfArguments: UInt { get }
    var frameLength: UInt { get }
    var methodReturnType: UnsafePointer<CChar> { get }
    var methodReturnLength: UInt { get }
    func isOneWay() -> ObjCBool
}
@objc protocol NSInvocationProtocol {
    static func invocation(methodSignature: AnyObject) -> NSInvocationProtocol
    var selector: Selector { get set }
    var target: AnyObject { get set }
    func setArgument(_ argumentLocation: UnsafeMutableRawPointer, atIndex idx: Int)
    func getArgument(_ argumentLocation: UnsafeMutableRawPointer, atIndex idx: Int)
    var argumentsRetained: ObjCBool { get }
    func retainArguments()
    func setReturnValue(_ retLoc: UnsafeMutableRawPointer)
    func getReturnValue(_ retLoc: UnsafeMutableRawPointer)
    func invoke()
    func invoke(target: AnyObject)
    var methodSignature: NSMethodSignatureProtocol { get }
}

var NSMethodSignature: NSMethodSignatureProtocol.Type = {
    class_addProtocol(objc_lookUpClass("NSMethodSignature"), NSMethodSignatureProtocol.self)
    return objc_lookUpClass("NSMethodSignature") as! NSMethodSignatureProtocol.Type
}()
var NSInvocation: NSInvocationProtocol.Type = {
    class_addProtocol(objc_lookUpClass("NSInvocation"), NSInvocationProtocol.self)
    return objc_lookUpClass("NSInvocation") as! NSInvocationProtocol.Type
}()

@discardableResult public func invoke(_ selector: Selector, of target: AnyObject, with arguments: [Any?] = [], on thread: Thread? = nil, waitUntilDone wait: Bool = true) -> Any! {
    guard let method = class_getInstanceMethod(Swift.type(of: target), selector) else {
        target.doesNotRecognizeSelector?(selector)
        fatalError("Unrecognized selector -[\(target) \(selector)]")
    }

    let sig = NSMethodSignature.signature(objCTypes: method_getTypeEncoding(method)!)
    let inv = NSInvocation.invocation(methodSignature: sig)

    // Setup arguments
    precondition(arguments.count + 2 <= Int(method_getNumberOfArguments(method)),
                 "Too many arguments for calling -[\(Swift.type(of: target)) \(selector)]")
    var args = [[Int]](repeating: [], count: arguments.count)
    for i in 0 ..< arguments.count {
        if let arg: Any = arguments[i] {
            let code = sig.getArgumentType(atIndex: UInt(i) + 2)
            let type = ObjCType(code: code)
            if type == .object {
                let obj: AnyObject = _bridgeAnythingToObjectiveC(arg)
                _autorelease(obj)
                args[i] = _encodeBitsAsWords(obj)
            } else if type == .clazz, let cls = arg as? AnyClass {
                args[i] = _encodeBitsAsWords(cls)
            } else if type == .float, let float = arg as? Float {
                // prevent to promot float type to double
                args[i] = _encodeBitsAsWords(float)
            } else if var val = arg as? CVarArg {
                if (Swift.type(of: arg) as? AnyClass)?.isSubclass(of: NSNumber.self) == true {
                    // argument is an NSNumber object
                    if let v = (arg as! NSNumber).value(as: type) {
                        val = v
                    }
                }
                args[i] = val._cVarArgEncoding
            } else {
                let type = String(cString: code)
                fatalError("Unable to convert argument \(i) from Swift type \(Swift.type(of: arg)) to ObjC type '\(type)'")
            }
        } else {
            // nil
            args[i] = [Int(0)]
        }

        args[i].withUnsafeBufferPointer {
            inv.setArgument(UnsafeMutablePointer(mutating: $0.baseAddress!), atIndex: i + 2)
        }
    }

    if selector.family == .init_ {
        // Self should be consumed for method belongs to init famlily
        _ = Unmanaged.passRetained(target)
    }
    inv.selector = selector

    if thread == nil || (thread == Thread.current && wait) {
        inv.invoke(target: target)
    } else {
        let selector = #selector(NSInvocationProtocol.invoke(target:))
        inv.retainArguments()
        (inv as! NSObject).perform(selector, on: thread!, with: target, waitUntilDone: wait)
        guard wait else { return Void() }
    }
    if sig.methodReturnLength == 0 { return Void() }

    // Fetch the return value
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(sig.methodReturnLength))
    inv.getReturnValue(buffer)
    let type = ObjCType(code: sig.methodReturnType)
    defer {
        if type == .object && selector.returnsRetained {
            // To balance the retained return value
            let obj = UnsafeRawPointer(buffer).load(as: AnyObject.self)
            Unmanaged.passUnretained(obj).release()
        }
        buffer.deallocate(capacity: Int(sig.methodReturnLength))
    }
    return type.loadValue(from: buffer)
}

public func createInstance(of class: AnyClass, by initializer: Selector = #selector(NSObject.init), with arguments: [Any?] = []) -> AnyObject? {
    guard let obj = invoke(#selector(NSProxy.alloc), of: `class`) else {
        return nil
    }
    return invoke(initializer, of: obj as AnyObject, with: arguments) as AnyObject
}

// See: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
private enum ObjCType : CChar {
    case char      = 0x63 // 'c'
    case int       = 0x69 // 'i'
    case short     = 0x73 // 's'
    case long      = 0x6c // 'l'
    case longlong  = 0x71 // 'q'
    case uchar     = 0x43 // 'C'
    case uint      = 0x49 // 'I'
    case ushort    = 0x53 // 'S'
    case ulong     = 0x4c // 'L'
    case ulonglong = 0x51 // 'Q'
    case float     = 0x66 // 'f'
    case double    = 0x64 // 'd'
    case bool      = 0x42 // 'B'
    case void      = 0x76 // 'v'
    case string    = 0x2a // '*'
    case object    = 0x40 // '@'
    case clazz     = 0x23 // '#'
    case selector  = 0x3a // ':'
    case pointer   = 0x5e // '^'
    case unknown   = 0x3f // '?'

    init(code: UnsafePointer<CChar>) {
        var val = code.pointee
        if val == 0x72 {
            // skip const qualifier
            val = code.successor().pointee
        }
        guard let type = ObjCType(rawValue: val) else {
            fatalError("Unknown ObjC type code: \(String(cString: code))")
        }
        self = type
    }

    func loadValue(from pointer: UnsafeRawPointer) -> Any! {
        switch self {
        case .char:      return pointer.load(as: CChar.self)
        case .int:       return pointer.load(as: CInt.self)
        case .short:     return pointer.load(as: CShort.self)
        case .long:      return pointer.load(as: Int32.self)
        case .longlong:  return pointer.load(as: CLongLong.self)
        case .uchar:     return pointer.load(as: CUnsignedChar.self)
        case .uint:      return pointer.load(as: CUnsignedInt.self)
        case .ushort:    return pointer.load(as: CUnsignedShort.self)
        case .ulong:     return pointer.load(as: UInt32.self)
        case .ulonglong: return pointer.load(as: CUnsignedLongLong.self)
        case .float:     return pointer.load(as: CFloat.self)
        case .double:    return pointer.load(as: CDouble.self)
        case .bool:      return pointer.load(as: CBool.self)
        case .void:      return Void()
        case .string:    return pointer.load(as: UnsafePointer<CChar>.self)
        case .object:    return pointer.load(as: AnyObject!.self)
        case .clazz:     return pointer.load(as: AnyClass!.self)
        case .selector:  return pointer.load(as: Selector!.self)
        case .pointer:   return pointer.load(as: OpaquePointer.self)
        case .unknown:   fatalError("Unknown ObjC type")
        }
    }
}

private extension NSNumber {
    func value(as type: ObjCType) -> CVarArg? {
        switch type {
        case .bool:      return self.boolValue
        case .char:      return self.int8Value
        case .int:       return self.int32Value
        case .short:     return self.int16Value
        case .long:      return self.int32Value
        case .longlong:  return self.int64Value
        case .uchar:     return self.uint8Value
        case .uint:      return self.uint32Value
        case .ushort:    return self.uint16Value
        case .ulong:     return self.uint32Value
        case .ulonglong: return self.uint64Value
        case .float:     return self.floatValue
        case .double:    return self.doubleValue
        default:         return nil
        }
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
        var s = unsafeBitCast(self, to: UnsafePointer<Int8>.self)
        while s.pointee == 0x5f { s += 1 }  // skip underscore
        for p in Selector.prefixes {
            let lowercase = CChar(97)...CChar(122)
            let l = p.count
            if strncmp(s, p, l) == 0 && !lowercase.contains(s.advanced(by: l).pointee) {
                return Family(rawValue: s.pointee)!
            }
        }
        return .none
    }
    var returnsRetained: Bool {
        return family != .none
    }
}

// Additional Swift types which can be represented in C type.
extension CVarArg {
    public var _cVarArgEncoding: [Int] {
        return _encodeBitsAsWords(self)
    }
}
extension Bool: CVarArg {
    public var _cVarArgEncoding: [Int] {
        return _encodeBitsAsWords(self)
    }
}
extension UnicodeScalar: CVarArg {}
extension Selector: CVarArg {}
extension UnsafeRawPointer: CVarArg {}
extension UnsafeMutableRawPointer: CVarArg {}
extension UnsafeBufferPointer: CVarArg {}
extension UnsafeMutableBufferPointer: CVarArg {}


///////////////////////////////////////////////////////////////////////////////

public class XWVInvocation {
    public final let target: AnyObject
    private let thread: Thread?

    public init(target: AnyObject, thread: Thread? = nil) {
        self.target = target
        self.thread = thread
    }

    @discardableResult public func call(_ selector: Selector, with arguments: [Any?] = []) -> Any! {
        return invoke(selector, of: target, with: arguments, on: thread)
    }
    // No callback support, so return value is expected to lose.
    public func asyncCall(_ selector: Selector, with arguments: [Any?] = []) {
        invoke(selector, of: target, with: arguments, on: thread, waitUntilDone: false)
    }

    // Syntactic sugar for calling method
    public subscript (selector: Selector) -> (Any?...)->Any! {
        return {
            (args: Any?...)->Any! in
            self.call(selector, with: args)
        }
    }
}

extension XWVInvocation {
    // Property accessor
    public func value(of name: String) -> Any! {
        guard let getter = getter(of: name) else {
            assertionFailure("Property '\(name)' does not exist")
            return Void()
        }
        return call(getter)
    }
    public func setValue(_ value: Any!, to name: String) {
        guard let setter = setter(of: name) else {
            assertionFailure("Property '\(name)' " +
                (getter(of: name) == nil ? "does not exist" : "is readonly"))
            return
        }
        precondition(!(value is Void))
        call(setter, with: [value])
    }

    // Syntactic sugar for accessing property
    public subscript (name: String) -> Any! {
        get {
            return value(of: name)
        }
        set {
            setValue(newValue, to: name)
        }
    }

    private func getter(of name: String) -> Selector? {
        guard let property = class_getProperty(type(of: target), name) else {
            return nil
        }
        guard let attr = property_copyAttributeValue(property, "G") else {
            return Selector(name)
        }

        // The property defines a custom getter selector name.
        let getter = Selector(String(cString: attr))
        free(attr)
        return getter
    }
    private func setter(of name: String) -> Selector? {
        guard let property = class_getProperty(type(of: target), name) else {
            return nil
        }

        var setter: Selector? = nil
        var attr = property_copyAttributeValue(property, "R")
        if attr == nil {
            attr = property_copyAttributeValue(property, "S")
            if attr == nil {
                setter = Selector("set\(String(name[name.startIndex]).uppercased())\(String(name.characters.dropFirst())):")
            } else {
                // The property defines a custom setter selector name.
                setter = Selector(String(cString: attr!))
            }
        }
        free(attr)
        return setter
    }
}
