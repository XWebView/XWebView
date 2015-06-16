# XWebView - eXtensible WebView for iOS

[![Build Status](https://travis-ci.org/XWebView/XWebView.svg?branch=master)](https://travis-ci.org/XWebView/XWebView)

## Introduction

XWebView is an extensible WebView which is built on top of [WKWebView](https://developer.apple.com/library/ios/documentation/WebKit/Reference/WKWebView_Ref/), the modern WebKit framework debuted in iOS 8.0. It provides fast Web runtime with carefully designed plugin API for developing sophisticated iOS native or hybrid applications.

Plugins written in Objective-C or Swift programming language can be automatically exposed in JavaScript context. With capabilities offered by plugins, Web apps can look and behave exactly like native apps. They will be no longer a second-class citizen on iOS platform.

## Features

Basically, plugins are native classes which can export their interfaces to a JavaScript environment. Calling methods and accessing properties of a plugin object in JavaScript result in same operations to the native plugin object. If you know the [Apache Cordova](https://cordova.apache.org/), you may have the concept of plugins. Well, XWebView does more in simpler form.

Unlike Cordova, you needn't to write JavaScript stubs for XWebView plugins commonly. The generated stubs are suitable for most cases. Stubs are generated dynamically in runtime by type information which is provided by compiler. You still have opportunity to override stubs for special cases.

The form of XWebView plugin API is similar to the [scripting API of WebKit](https://developer.apple.com/library/mac/documentation/AppleApplications/Conceptual/SafariJSProgTopics/Tasks/ObjCFromJavaScript.html) which is only available on OS X. Although the JavaScript context of WKWebView is not accessible on iOS, the communication is bridged through [message passing](https://developer.apple.com/library/mac/documentation/WebKit/Reference/WKUserContentController_Ref/index.html#//apple_ref/occ/instm/WKUserContentController/addScriptMessageHandler:name:) under the hood.

Besides mapping to an ordinary JavaScript object, a plugin object can also be mapped to a JavaScript function. Calling of the function results in an invocation of a certain native method of the plugin object.

Further more, JavaScript constructor is also supported. A plugin can have multiple instances. In this case, an initializer is mapped to the function of constructor. Meanwhile, principal object of the plugin is created as the prototype of constructor. Each instance has a pair of native and JavaScript object which share the same life cycle and states.

XWebView is designed for embedding. It's easy to adopt since it's an extension of WKWebView class. Basically, creating and loading plugin objects are the only additional steps you need to handle. Additionally, XWebView offers 2 threading modes for plugin: Grand Central Dispatch(GCD) and NSThread.

The project lacks documentation currently, so dig more from the code :-)

## System Requirements:

* Development:
  * Xcode 6.3+
  * iOS SDK 8.0+
* Deployment:
  * iOS 8.0+

## Quick Start

Here is a `HelloWorld` example to demonstrate the essential features of XWebView. 

1. Create an project

  Create an iOS application project called `HelloWorld` with the "Single View Application" template in a working directory, and use language "Swift" for convenience.

2. Use [CocoaPods](https://cocoapods.org/) to install XWebView

  Close the project you just created. In the root directory of the project, create a file named `Podfile` which contains only 3 lines:

  ```
  platform :ios, '8.1'
  use_frameworks!
  pod 'XWebView', '~> 0.9.2'
  ```

  Then run `pod install` in terminal to setup a workspace for you. When finished, open the `HelloWorld.xcworkspace` created by CocoaPods.

3. Modify the ViewController

  In the `ViewController.swift` file, find the `viewDidLoad()` method and add few lines:

  ```swift
  // Do any additional setup after loading the view, typically from a nib.
  let webview = WKWebView(frame: view.frame, configuration: WKWebViewConfiguration())
  view.addSubview(webview)
  webview.loadPlugin(HelloWorld(), namespace: "helloWorld")
  let root = NSBundle.mainBundle().resourceURL!
  let url = root.URLByAppendingPathComponent("index.html")
  webview.loadFileURL(url, allowingReadAccessToURL: root)
  ````

  Don't forget to import WebKit and XWebView frameworks.

4. Write a plugin

  In `HelloWorld` group, create a Swift source file named `HelloWorld.swift`. It's a simple class.

  ````swift
  import Foundation
  import UIKit

  class HelloWorld : NSObject {
      func show(text: AnyObject?) {
          let title = text as? String
          dispatch_async(dispatch_get_main_queue()) {
              let alert = UIAlertView(title: title, message: nil, delegate: nil, cancelButtonTitle: "OK")
              alert.show()
          }
      }
  }
  ````

5. Lastly, the HTML.

  Create an HTML file named `index.html` also in the `HelloWorld` group. The content is straightforward.

  ```html
  <html>
    <head>
      <meta name='viewport' content='width=device-width' />
    </head>
    <body>
      <br />
      <input type='button' value='Hello' onclick='helloWorld.show("Hello, world!");' />
    </body>
  </html>
  ```

6. Go, go, go!

  Build and run the application.

  ![helloworld](https://cloud.githubusercontent.com/assets/486820/7409665/d69297f6-ef5a-11e4-9377-f320a084909a.png)

There is a [sample App](https://github.com/XWebView/Sample) for XWebView. It contains more example plugins, have a try.

## License

XWebView is available under the Apache License 2.0. See the [LICENSE](LICENSE) file for more info.

XWebView is derived from [Crosswalk Project for iOS](https://github.com/crosswalk-project/crosswalk-ios) which is available under the [BSD license](LICENSE.crosswalk).
