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

class XWVInventoryTest: XCTestCase {
    class Plugin : NSObject {
    }
    let namespace = "xwvtest.inventory"
    let inventory = XWVInventory()

    override func setUp() {
        super.setUp()
        inventory.registerPlugin(Plugin.self, namespace: namespace)
    }

    func testRegister() {
        XCTAssertTrue(inventory.registerPlugin(Plugin.self, namespace: "xwvtest.another"))
        XCTAssertFalse(inventory.registerPlugin(Plugin.self, namespace: namespace))
    }

    func testGetClass() {
        XCTAssertTrue(inventory.plugin(forNamespace: namespace) === Plugin.self)
    }
}
