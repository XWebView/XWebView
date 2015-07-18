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

@objc public protocol XWVScripting : class {
    optional func javascriptStub(stub: String) -> String
    optional func finalizeForScript()

    optional static func isSelectorForConstructor(selector: Selector) -> Bool
    optional static func isSelectorForDefaultMethod(selector: Selector) -> Bool

    optional static func scriptNameForKey(name: UnsafePointer<Int8>) -> String?
    optional static func scriptNameForSelector(selector: Selector) -> String?
    optional static func isSelectorExcludedFromScript(selector: Selector) -> Bool
    optional static func isKeyExcludedFromScript(name: UnsafePointer<Int8>) -> Bool
}
