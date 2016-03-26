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

class XWVMetaObject: CollectionType {
    enum Member {
        case Method(selector: Selector, arity: Int32)
        case Property(getter: Selector, setter: Selector)
        case Initializer(selector: Selector, arity: Int32)

        var isMethod: Bool {
            if case .Method = self { return true }
            return false
        }
        var isProperty: Bool {
            if case .Property = self { return true }
            return false
        }
        var isInitializer: Bool {
            if case .Initializer = self { return true }
            return false
        }
        var selector: Selector? {
            switch self {
            case let .Method(selector, _):
                assert(selector != Selector())
                return selector
            case let .Initializer(selector, _):
                assert(selector != Selector())
                return selector
            default:
                return nil
            }
        }
        var getter: Selector? {
            if case .Property(let getter, _) = self {
                assert(getter != Selector())
                return getter
            }
            return nil
        }
        var setter: Selector? {
            if case .Property(let getter, let setter) = self {
                assert(getter != Selector())
                return setter
            }
            return nil
        }
        var type: String {
            let promise: Bool
            let arity: Int32
            switch self {
            case let .Method(selector, a):
                promise = selector.description.hasSuffix(":promiseObject:") ||
                          selector.description.hasSuffix("PromiseObject:")
                arity = a
            case let .Initializer(_, a):
                promise = true
                arity = a < 0 ? a: a + 1
            default:
                promise = false
                arity = -1
            }
            if !promise && arity < 0 {
                return ""
            }
            return "#" + (arity >= 0 ? "\(arity)" : "") + (promise ? "p" : "a")
        }
    }

    let plugin: AnyClass
    private var members = [String: Member]()
    private static let exclusion: Set<Selector> = {
        var methods = instanceMethods(forProtocol: XWVScripting.self)
        methods.remove(#selector(XWVScripting.invokeDefaultMethodWithArguments(_:)))
        return methods.union([
            #selector(_SpecialSelectors.dealloc),
            #selector(NSObject.copy as ()->AnyObject)
        ])
    }()

    init(plugin: AnyClass) {
        self.plugin = plugin
        enumerateExcluding(self.dynamicType.exclusion) {
            (name, member) -> Bool in
            var name = name
            var member = member
            switch member {
            case let .Method(selector, _):
                if let cls = plugin as? XWVScripting.Type {
                    if cls.isSelectorExcludedFromScript?(selector) ?? false {
                        return true
                    }
                    if selector == #selector(XWVScripting.invokeDefaultMethodWithArguments(_:)) {
                        member = .Method(selector: selector, arity: -1)
                        name = ""
                    } else {
                        name = cls.scriptNameForSelector?(selector) ?? name
                    }
                } else if name.characters.first == "_" {
                    return true
                }

            case .Property(_, _):
                if let cls = plugin as? XWVScripting.Type {
                    if let isExcluded = cls.isKeyExcludedFromScript where name.withCString(isExcluded) {
                        return true
                    }
                    if let scriptNameForKey = cls.scriptNameForKey {
                        name = name.withCString(scriptNameForKey) ?? name
                    }
                } else if name.characters.first == "_" {
                    return true
                }

            case let .Initializer(selector, _):
                if selector == Selector("initByScriptWithArguments:") {
                    member = .Initializer(selector: selector, arity: -1)
                    name = ""
                } else if let cls = plugin as? XWVScripting.Type {
                    name = cls.scriptNameForSelector?(selector) ?? name
                }
                if !name.isEmpty {
                    return true
                }
            }
            assert(members.indexForKey(name) == nil, "Plugin class \(plugin) has a conflict in member name '\(name)'")
            members[name] = member
            return true
        }
    }

    private func enumerateExcluding(selectors: Set<Selector>, @noescape callback: ((String, Member)->Bool)) -> Bool {
        var known = selectors

        // enumerate properties
        let propertyList = class_copyPropertyList(plugin, nil)
        if propertyList != nil, var prop = Optional(propertyList) {
            defer { free(propertyList) }
            while prop.memory != nil {
                let name = String(UTF8String: property_getName(prop.memory))!
                // get getter
                var attr = property_copyAttributeValue(prop.memory, "G")
                let getter = Selector(attr == nil ? name : String(UTF8String: attr)!)
                free(attr)
                if known.contains(getter) {
                    prop = prop.successor()
                    continue
                }
                known.insert(getter)

                // get setter if readwrite
                var setter = Selector()
                attr = property_copyAttributeValue(prop.memory, "R")
                if attr == nil {
                    attr = property_copyAttributeValue(prop.memory, "S")
                    if attr == nil {
                        setter = Selector("set\(String(name.characters.first!).uppercaseString)\(String(name.characters.dropFirst())):")
                    } else {
                        setter = Selector(String(UTF8String: attr)!)
                    }
                    if known.contains(setter) {
                        setter = Selector()
                    } else {
                        known.insert(setter)
                    }
                }
                free(attr)

                let info = Member.Property(getter: getter, setter: setter)
                if !callback(name, info) {
                    return false
                }
                prop = prop.successor()
            }
        }

        // enumerate methods
        let methodList = class_copyMethodList(plugin, nil)
        if methodList != nil, var method = Optional(methodList) {
            defer { free(methodList) }
            while method.memory != nil {
                let sel = method_getName(method.memory)
                if !known.contains(sel) && !sel.description.hasPrefix(".") {
                    let arity = Int32(method_getNumberOfArguments(method.memory) - 2)
                    let member: Member
                    if sel.description.hasPrefix("init") {
                        member = Member.Initializer(selector: sel, arity: arity)
                    } else {
                        member = Member.Method(selector: sel, arity: arity)
                    }
                    var name = sel.description
                    if let end = name.characters.indexOf(":") {
                        name = name[name.startIndex ..< end]
                    }
                    if !callback(name, member) {
                        return false
                    }
                }
                method = method.successor()
            }
        }
        return true
    }
}

extension XWVMetaObject {
    // SequenceType
    typealias Generator = DictionaryGenerator<String, Member>
    func generate() -> Generator {
        return members.generate()
    }

    // CollectionType
    typealias Index = DictionaryIndex<String, Member>
    var startIndex: Index {
        return members.startIndex
    }
    var endIndex: Index {
        return members.endIndex
    }
    subscript (position: Index) -> (String, Member) {
        return members[position]
    }
    subscript (name: String) -> Member? {
        return members[name]
    }
}

private func instanceMethods(forProtocol aProtocol: Protocol) -> Set<Selector> {
    var selectors = Set<Selector>()
    for (req, inst) in [(true, true), (false, true)] {
        let methodList = protocol_copyMethodDescriptionList(aProtocol.self, req, inst, nil)
        if methodList != nil, var desc = Optional(methodList) {
            while desc.memory.name != nil {
                selectors.insert(desc.memory.name)
                desc = desc.successor()
            }
            free(methodList)
        }
    }
    return selectors
}
