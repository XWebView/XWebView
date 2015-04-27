# XWebView - eXtensible WebView for iOS

## Introduction

XWebView is an extensible WebView which is built on top of [WKWebView](https://developer.apple.com/library/ios/documentation/WebKit/Reference/WKWebView_Ref/), the modern WebKit framework debuted in iOS 8.0. It provides fast Web runtime with carefully designed plugin API for developing sophisticated iOS native or hybrid applications.

Plugins written in Objective-C or Swift programming language can be automatically exposed in JavaScript context. With capabilities offered by plugins, Web apps can look and behave exactly like native apps. They will be no longer a second-class citizen on iOS platform.

## Features

Basically, plugins are native classes which can export their interfaces to a JavaScript environment. Calling methods and accessing properties of a plugin object in JavaScript result in same operations to the native plugin object. If you know the [Apache Cordova](https://cordova.apache.org/), you may have the concept of plugins. Well, XWebView does more in simpler form.

Unlike Cordova, you needn't to write JavaScript stubs for XWebView plugins commonly. The generated stubs are suitable for most cases. Stubs are generated dynamically in runtime by type information which is provided by compiler. You still have opportunity to override stubs for special cases.

The form of XWebView plugin API is similar to the [scripting API of WebKit](https://developer.apple.com/library/mac/documentation/AppleApplications/Conceptual/SafariJSProgTopics/Tasks/ObjCFromJavaScript.html) which only available on OS X. Although the JavaScript context of WKWebView is not accessible on iOS, the communication is bridged through [message passing](https://developer.apple.com/library/mac/documentation/WebKit/Reference/WKUserContentController_Ref/index.html#//apple_ref/occ/instm/WKUserContentController/addScriptMessageHandler:name:) under the hood.

Besides mapping to an ordinary JavaScript object, a plugin object can also be mapped to a JavaScript function. Calling of the function results in an invocation of a certain native method of the plugin object.

Further more, JavaScript constructor is also supported. A plugin can have multiple instances. In this case, an initializer is mapped to the function of constructor. Meanwhile, principal object of the plugin is created as the prototype of constructor. Each instance has a pair of native and JavaScript object which share the same life cycle and states.

XWebView is designed for embedding. It's easy to adopt since it's an extension of WKWebView class. Basically, creating and loading plugin objects are the only additional steps you need to handle. Additionally, XWebView offers 3 threading modes for plugin: plugin thread(default, per WebView), specified thread(under your control) and main thread(use cautiously).

There is a [sample App](https://github.com/XWebView/Sample) for XWebView, have a try.

The project lacks documentation currently, so dig more from the code :-)

## System Requirements:

* Development:
  * Xcode 6.3+
  * iOS SDK 8.1+
* Deployment:
  * iOS 8.1+

## License

XWebView is available under the Apache License 2.0. See the [LICENSE](LICENSE) file for more info.

XWebView is derived from [Crosswalk Project for iOS](https://github.com/crosswalk-project/crosswalk-ios) which is available under the [BSD license](LICENSE.crosswalk).
