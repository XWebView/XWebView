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

@objc public class XWVInventory {
    private struct Provider {
        let bundle: NSBundle
        let className: String
    }
    private var plugins = [String: Provider]()

    public init() {
    }
    public init(directory: String) {
        scanPlugin(inDirectory: directory)
    }
    public init(bundle: NSBundle) {
        scanPlugin(inBundle: bundle)
    }

    public func scanPlugin(inDirectory directory: String) -> Bool {
        let fm = NSFileManager.defaultManager()
        if fm.fileExistsAtPath(directory) == true {
            for i in fm.contentsOfDirectoryAtPath(directory, error: nil)! {
                let name = i as! String
                if name.pathExtension == "framework" {
                    let bundlePath = directory.stringByAppendingPathComponent(name)
                    if let bundle = NSBundle(path: bundlePath) {
                        scanPlugin(inBundle: bundle)
                    }
                }
            }
            return true
        }
        return false
    }

    public func scanPlugin(inBundle bundle: NSBundle) -> Bool {
        if let info = bundle.objectForInfoDictionaryKey("XWebViewPlugins") as? NSDictionary {
            let e = info.keyEnumerator()
            while let namespace = e.nextObject() as? String {
                if let className = info[namespace] as? String {
                    if plugins[namespace] == nil {
                        plugins[namespace] = Provider(bundle: bundle, className: className)
                    } else {
                        println("WARNING: namespace '\(namespace)' conflicts")
                    }
                } else {
                    println("WARNING: bad class name '\(info[namespace])'")
                }
            }
            return true
        }
        return false
    }

    public func registerPlugin(plugin: AnyClass, namespace: String) -> Bool {
        if plugins[namespace] == nil {
            let bundle = NSBundle(forClass: plugin)
            var className = plugin.description()
            className = className.pathExtension.isEmpty ? className : className.pathExtension
            plugins[namespace] = Provider(bundle: bundle, className: className)
            return true
        }
        return false
    }

    public func plugin(forNamespace namespace: String) -> AnyClass? {
        if let provider = plugins[namespace] {
            // Load bundle
            if !provider.bundle.loaded {
                var error: NSError?
                if !provider.bundle.loadAndReturnError(&error) {
                    println("ERROR: load bundle '\(provider.bundle.bundlePath)' failed")
                    return nil
                }
            }

            var cls: AnyClass? = provider.bundle.classNamed(provider.className)
            if cls != nil {
                // FIXME: Never reach here because the bundle in build directory was loaded in simulator.
                return cls
            }
            // FIXME: workaround the problem
            // Try to get the class with the barely class name (for objective-c written class)
            cls = NSClassFromString(provider.className)
            if cls == nil {
                // Try to get the class with its framework name as prefix (for classes written in Swift)
                let swiftClassName = (provider.bundle.executablePath?.lastPathComponent)! + "." + provider.className
                cls = NSClassFromString(swiftClassName)
            }
            if cls == nil {
                println("ERROR: plugin class '\(provider.className)' not found in bundle '\(provider.bundle.bundlePath)'")
                return nil;
            }
            return cls
        }
        println("ERROR: namespace '\(namespace)' has no registered plugin class")
        return nil
    }
}
