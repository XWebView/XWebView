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

class XWVMetaObject {
    enum Member {
        case Method(selector: Selector, arity: Int32)
        case Property(getter: Selector, setter: Selector?)
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
                return selector
            case let .Initializer(selector, _):
                return selector
            default:
                return nil
            }
        }
        var getter: Selector? {
            if case .Property(let getter, _) = self {
                return getter
            }
            return nil
        }
        var setter: Selector? {
            if case .Property(_, let setter) = self {
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
    fileprivate var members = [String: Member]()
    private static let exclusion: Set<Selector> = {
        var methods = instanceMethods(forProtocol: XWVScripting.self)
        methods.remove(#selector(XWVScripting.invokeDefaultMethod(withArguments:)))
        return methods.union([
//            #selector(NSObject.deinit),
            #selector(NSObject.copy)
        ])
    }()

    init(plugin: AnyClass) {
        self.plugin = plugin
        _ = enumerate(excluding: type(of: self).exclusion) {
            (name, member) -> Bool in
            var name = name
            var member = member
            switch member {
            case let .Method(selector, _):
                if let cls = plugin as? XWVScripting.Type {
                    if cls.isSelectorExcluded?(fromScript: selector) ?? false {
                        return true
                    }
                    if selector == #selector(XWVScripting.invokeDefaultMethod(withArguments:)) {
                        member = .Method(selector: selector, arity: -1)
                        name = ""
                    } else {
                        name = cls.scriptName?(for: selector) ?? name
                    }
                } else if name.characters.first == "_" {
                    return true
                }

            case .Property(_, _):
                if let cls = plugin as? XWVScripting.Type {
                    if let isExcluded = cls.isKeyExcluded(fromScript:), name.withCString(isExcluded) {
                        return true
                    }
                    if let scriptNameForKey = cls.scriptName(forKey:) {
                        name = name.withCString(scriptNameForKey) ?? name
                    }
                } else if name.characters.first == "_" {
                    return true
                }

            case let .Initializer(selector, _):
                if selector == #selector(_InitSelector.init(byScriptWithArguments:)) {
                    member = .Initializer(selector: selector, arity: -1)
                    name = ""
                } else if let cls = plugin as? XWVScripting.Type {
                    name = cls.scriptName?(for: selector) ?? name
                }
                if !name.isEmpty {
                    return true
                }
            }
            assert(members.index(forKey: name) == nil, "Plugin class \(plugin) has a conflict in member name '\(name)'")
            members[name] = member
            return true
        }
    }

    private func enumerate(excluding selectors: Set<Selector>, callback: (String, Member)->Bool) -> Bool {
        var known = selectors

        // enumerate properties
        let propertyList = class_copyPropertyList(plugin, nil)
        if var prop = propertyList {
            defer { free(propertyList) }
            while prop.pointee != nil {
                let name = String(cString: property_getName(prop.pointee))
                // get getter
                var attr = property_copyAttributeValue(prop.pointee, "G")
                let getter = Selector(attr == nil ? name : String(cString: attr!))
                free(attr)
                if known.contains(getter) {
                    prop = prop.successor()
                    continue
                }
                known.insert(getter)

                // get setter if readwrite
                var setter: Selector? = nil
                attr = property_copyAttributeValue(prop.pointee, "R")
                if attr == nil {
                    attr = property_copyAttributeValue(prop.pointee, "S")
                    if attr == nil {
                        setter = Selector("set\(String(name[name.startIndex]).uppercased())\(String(name.characters.dropFirst())):")
                    } else {
                        setter = Selector(String(cString: attr!))
                    }
                    if known.contains(setter!) {
                        setter = nil
                    } else {
                        known.insert(setter!)
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
        if var method = methodList {
            defer { free(methodList) }
            while method.pointee != nil {
                if let sel = method_getName(method.pointee), !known.contains(sel) && !sel.description.hasPrefix(".") {
                    let arity = Int32(method_getNumberOfArguments(method.pointee)) - 2
                    let member: Member
                    if sel.description.hasPrefix("init") {
                        member = Member.Initializer(selector: sel, arity: arity)
                    } else {
                        member = Member.Method(selector: sel, arity: arity)
                    }
                    var name = sel.description
                    if let end = name.characters.index(of: ":") {
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

    subscript (name: String) -> Member? {
        return members[name]
    }
}

extension XWVMetaObject: Collection {
    // IndexableBase
    typealias Index = DictionaryIndex<String, Member>
    typealias SubSequence = Slice<Dictionary<String, Member>>
    var startIndex: Index {
        return members.startIndex
    }
    var endIndex: Index {
        return members.endIndex
    }
    subscript (_ i: Index) -> (String, Member) {
        return members[i]
    }
    subscript (_ range: Range<Index>) -> SubSequence {
        return members[range]
    }
    func index(after i: Index) -> Index {
        return members.index(after: i)
    }
}

private func instanceMethods(forProtocol aProtocol: Protocol) -> Set<Selector> {
    var selectors = Set<Selector>()
    for (req, inst) in [(true, true), (false, true)] {
        let methodList = protocol_copyMethodDescriptionList(aProtocol.self, req, inst, nil)
        if var desc = methodList {
            while desc.pointee.name != nil {
                selectors.insert(desc.pointee.name)
                desc = desc.successor()
            }
            free(methodList)
        }
    }
    return selectors
}
