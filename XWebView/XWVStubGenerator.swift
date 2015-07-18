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

class XWVStubGenerator {
    let typeInfo: XWVMetaObject
    let channelName: String

    convenience init(channel: XWVChannel) {
        self.init(channelName: channel.name, typeInfo: channel.typeInfo)
    }
    init(channelName: String, typeInfo: XWVMetaObject) {
        self.channelName = channelName
        self.typeInfo = typeInfo
    }

    func generateForNamespace(namespace: String, object: XWVScriptPlugin? = nil) -> String {
        var stub = "(function(exports) {\n"
        for (name, member) in typeInfo {
            if member.isMethod || member.isInitializer {
                stub += "exports.\(name) = \(generateForMethod(name))\n"
            } else if member.isProperty {
                let value = object?.serialize(object?[name]) ?? "undefined"
                stub += "XWVPlugin.defineProperty(exports, '\(name)', \(value), \(member.setter != nil));\n"
            }
        }
        stub += "\n})(XWVPlugin.create(\(channelName), '\(namespace)'"
        if typeInfo["$constructor"] != nil {
            var ctor = namespace.pathExtension.isEmpty ? namespace : namespace.pathExtension
            if let idx = find(ctor, "[") {
                ctor = prefix(ctor, distance(ctor.startIndex, idx))
            }
            stub += ", function \(ctor)(){this.$constructor.apply(this, arguments);}"
        } else if typeInfo["$default"] != nil {
            stub += ", function(){return arguments.callee.$default.apply(arguments.callee, arguments);}"
        }
        stub += "));\n"
        return stub
    }

    private func generateForMethod(name: String) -> String {
        let this = "this"
        var params = split(typeInfo[name]!.selector!.description, allowEmptySlices: true) {$0 == ":"}
        params.removeLast()

        // deal with parameters without external name
        for i in 0..<params.count {
            if params[i].isEmpty {
                params[i] = "$_\(i)"
            }
        }

        let isConstructor = name == "$constructor"
        let isPromise = params.last == "_Promise"
        if isPromise { params.removeLast() }

        let list = ", ".join(params)
        var body = "$invokeNative('" + (isConstructor ? "+" : name) + "', [\(list)"
        if isPromise {
            body = "var _this = \(this);\n    return new Promise(function(resolve, reject) {\n        _this.\(body)"
            body += (list.isEmpty ? "" : ", ") + "{'resolve': resolve, 'reject': reject}]);\n    });"
        } else {
            body = "\(this).\(body)]);"
            if isConstructor {
                body = "if (arguments[\(params.count)] instanceof Function)\n" +
                    "        \(this).$onready = arguments[\(params.count)];\n    " + body
            }
        }
        return "function(\(list)) {\n    \(body)\n}"
    }
}
