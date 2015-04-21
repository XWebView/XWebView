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

class XWVReflection {
    private struct MemberInfo {
        let method = Selector()
        let getter = Selector()
        let setter = Selector()
        var isProperty : Bool { return getter != nil }
        var isReadonly : Bool { return setter == nil }
        var isMethod : Bool { return method != nil }
        init(method: Selector) {
            self.method = method
        }
        init(getter: Selector, setter: Selector) {
            self.getter = getter
            self.setter = setter
        }
    }

    let plugin: AnyClass
    private var members: [String: MemberInfo] = [:]
    private class var exclusion : [Selector] {
        return [Selector(".cxx_construct"), Selector(".cxx_destruct"), Selector("dealloc"), Selector("copy")] +
            self.instanceMethods(forProtocol: XWVScripting.self)
    }

    init(plugin: AnyClass) {
        self.plugin = plugin
        let cls: AnyClass = plugin
        enumerate(self.dynamicType.exclusion) {
            (var name, info) -> Bool in
            if info.isProperty {
                if cls.isKeyExcludedFromScript != nil {
                    if name.withCString(cls.isKeyExcludedFromScript!) {
                        return true
                    }
                }
                if cls.scriptNameForKey != nil {
                    name = name.withCString(cls.scriptNameForKey!)
                }
            } else if info.isMethod {
                if cls.isSelectorExcludedFromScript?(info.method) ?? false {
                    return true
                }
                if cls.isSelectorForDefaultMethod?(info.method) ?? false {
                    name = "$default"
                } else if cls.isSelectorForConstructor?(info.method) ?? false  {
                    name = "$constructor"
                } else if cls.scriptNameForSelector != nil {
                    name = cls.scriptNameForSelector!(info.method)
                } else if let end = find(name, ":") {
                    name = name[name.startIndex ..< end]
                }
            }
            self.members[name] = info
            return true
        }
    }

    // Basic information
    var allMembers: [String] {
        return members.keys.array
    }
    var allMethods: [String] {
        return filter(members.keys.array, {(e)->Bool in return self.hasMethod(e)})
    }
    var allProperties: [String] {
        return filter(members.keys.array, {(e)->Bool in return self.hasProperty(e)})
    }
    func hasMember(name: String) -> Bool {
        return members[name] != nil
    }
    func hasMethod(name: String) -> Bool {
        return (members[name]?.method ?? Selector()) != Selector()
    }
    func hasProperty(name: String) -> Bool {
        return (members[name]?.getter ?? Selector()) != Selector()
    }
    func isReadonly(name: String) -> Bool {
        assert(hasProperty(name))
        return members[name]!.setter == Selector()
    }

    // Fetching selectors
    var constructor: Selector {
        return members["$constructor"]?.method ?? Selector()
    }
    func selector(forMethod name: String) -> Selector {
        return members[name]?.method ?? Selector()
    }
    func getter(forProperty name: String) -> Selector {
        return members[name]?.getter ?? Selector()
    }
    func setter(forProperty name: String) -> Selector {
        return members[name]?.setter ?? Selector()
    }

    private func enumerate(exclusion: [Selector], callback: ((String, MemberInfo)->Bool)) -> Bool {
        // build selector set of exclusion
        // TODO: use the new Set collection type, need Swift 1.2 (XCode 6.3)
        var known = [Selector: Bool]()
        known = exclusion.reduce(known) {
            (var known, sel)->[Selector:Bool] in
            known.updateValue(true, forKey: sel)
            return known
        }

        // enumerate properties
        let properties = class_copyPropertyList(plugin, nil);
        if properties != nil {
            for var prop = properties; prop.memory != nil; prop = prop.successor() {
                let name = String(UTF8String: property_getName(prop.memory))!
                // get getter
                var attr = property_copyAttributeValue(prop.memory, "G")
                let getter = Selector(attr == nil ? name : String(UTF8String: attr)!)
                free(attr)
                if known.indexForKey(getter) != nil {
                    continue
                } else {
                    known[getter] = true
                }
                // get setter if readwrite
                var setter = Selector()
                attr = property_copyAttributeValue(prop.memory, "R")
                if attr == nil {
                    attr = property_copyAttributeValue(prop.memory, "S")
                    if attr == nil {
                        setter = Selector("set\(prefix(name, 1).uppercaseString)\(dropFirst(name)):")
                    } else {
                        setter = Selector(String(UTF8String: attr)!)
                    }
                    if known.indexForKey(setter) != nil {
                        setter = Selector()
                    } else {
                        known[setter] = true
                    }
                }
                free(attr)

                let info = MemberInfo(getter: getter, setter: setter)
                if !callback(name, info) {
                    free(properties)
                    return false
                }
            }
            free(properties)
        }

        // enumerate methods
        let methods = class_copyMethodList(plugin, nil);
        if methods != nil {
            for var method = methods; method.memory != nil; method = method.successor() {
                let sel = method_getName(method.memory)
                if known.indexForKey(sel) != nil {
                    continue
                }
                if !callback(sel.description, MemberInfo(method: sel)) {
                    free(methods)
                    return false
                }
            }
            free(methods)
        }
        return true
    }

    private class func instanceMethods(forProtocol aProtocol: Protocol) -> [Selector] {
        var selectors = [Selector]()
        for (req, inst) in [(true, true), (false, true)] {
            var descriptors = protocol_copyMethodDescriptionList(aProtocol.self, req, inst, nil)
            if descriptors == nil { continue }
            for var desc = descriptors; desc.memory.name != nil; desc = desc.successor() {
                selectors.append(desc.memory.name)
            }
            free(descriptors)
        }
        return selectors
    }
}
