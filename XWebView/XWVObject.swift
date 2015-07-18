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
import WebKit

public class XWVObject : NSObject {
    public let namespace: String
    public unowned let channel: XWVChannel
    public var webView: WKWebView? { return channel.webView }
    weak var origin: XWVObject!

    init(namespace: String, channel: XWVChannel, origin: XWVObject?) {
        self.namespace = namespace
        self.reference = 0
        self.channel = channel
        super.init()
        self.origin = origin ?? self
    }

    // retain and autorelease
    private let reference: Int
    convenience init(reference: Int, channel: XWVChannel, origin: XWVObject) {
        let namespace = "\(origin.namespace).$references[\(reference)]"
        self.init(namespace: namespace, channel: channel, origin: origin)
    }
    deinit {
        if reference != 0 {
            let script = "\(origin.namespace).$releaseObject(\(reference))"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    func wrapScriptObject(object: AnyObject?) -> AnyObject {
        if let dict = object as? [String: AnyObject] where dict["$sig"] as? NSNumber == 0x5857574F {
            if let num = dict["$ref"] as? NSNumber {
                return XWVScriptObject(reference: num.integerValue, channel: channel, origin: self)
            } else if let namespace = dict["$ns"] as? String {
                return XWVScriptObject(namespace: namespace, channel: channel, origin: self)
            }
        }
        return object ?? NSNull()
    }

    func serialize(object: AnyObject?) -> String {
        var obj: AnyObject? = object
        if let val = obj as? NSValue {
            obj = val as? NSNumber ?? val.nonretainedObjectValue
        }

        if let o = obj as? XWVObject {
            return o.namespace
        } else if let s = obj as? String {
            let d = NSJSONSerialization.dataWithJSONObject([s], options: NSJSONWritingOptions(0), error: nil)
            return dropFirst(dropLast(NSString(data: d!, encoding: NSUTF8StringEncoding) as! String))
        } else if let n = obj as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue.description
            }
            return n.stringValue
        } else if let date = obj as? NSDate {
            return "(new Date(\(date.timeIntervalSince1970 * 1000)))"
        } else if let date = obj as? NSData {
            // TODO: map to Uint8Array object
        } else if let a = obj as? [AnyObject] {
            return "[" + ",".join(a.map(serialize)) + "]"
        } else if let d = obj as? [String: AnyObject] {
            return "{" + ",".join(d.keys.map(){"'\($0)': \(self.serialize(d[$0]!))"}) + "}"
        } else if obj === NSNull() {
            return "null"
        } else if obj == nil {
            return "undefined"
        }
        return "'\(obj!.description)'"
    }
}
