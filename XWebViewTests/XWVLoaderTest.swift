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

import WebKit
import XCTest
import XWebView

class XWVLoaderTest: XWVTestCase {
    class Plugin: NSObject {
        dynamic var property = 123
    }

    private let namespace = "xwvtest"

    func testLoader() {
        let desc = "loader"
        let script = "if (XWVPlugin.load instanceof Function) fulfill('\(desc)');"
        let expectation = expectationWithDescription(desc)
        loadPlugin(XWVLoader(inventory: XWVInventory()), namespace: "XWVPlugin.load", script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testLoading() {
        let inventory = XWVInventory()
        inventory.registerPlugin(Plugin.self, namespace: namespace)
        let loader = XWVLoader(inventory: inventory)

        let desc = "loading"
        let script = "XWVPlugin.load('\(namespace)').then(function(o){if (o.property==123) fulfill('\(desc)');})"
        let expectation = expectationWithDescription(desc)
        loadPlugin(loader, namespace: "XWVPlugin.load", script: script)
        waitForExpectationsWithTimeout(2, handler: nil)
    }
}
