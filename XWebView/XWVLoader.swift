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

public class XWVLoader: NSObject, XWVScripting {
    private let _inventory: XWVInventory

    public init(inventory: XWVInventory) {
        self._inventory = inventory
        super.init()
    }

    func defaultMethod(namespace: String, argument: AnyObject?, promiseObject: XWVScriptObject) {
        if let plugin: AnyClass = _inventory.plugin(forNamespace: namespace), let channel = scriptObject?.channel {
            let initializer = Selector(argument == nil ? "init" : "initWitArgument:")
            let args: [AnyObject]? = argument == nil ? nil : [argument!]
            let object = XWVInvocation.constructOnThread(channel.thread, `class`: plugin, initializer: initializer, arguments: args) as! NSObject!
            if object != nil, let obj = channel.webView?.loadPlugin(object, namespace: namespace) {
                promiseObject.callMethod("resolve", withArguments: [obj], resultHandler: nil)
                return
            }
        }
        promiseObject.callMethod("reject", withArguments: nil, resultHandler: nil)
    }

    public class func scriptNameForSelector(selector: Selector) -> String? {
        return selector == Selector("defaultMethod:argument:promiseObject:") ? "" : nil
    }
}
