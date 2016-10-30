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

#import <Cocoa/Cocoa.h>

//! Project version number for XWebViewX.
FOUNDATION_EXPORT double XWebViewXVersionNumber;

//! Project version string for XWebViewX.
FOUNDATION_EXPORT const unsigned char XWebViewXVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <XWebViewX/PublicHeader.h>


// The workaround for loading file URL on OS X 10.10.x.
#import <WebKit/WKWebView.h>
@interface WKWebView (XWebView)
- (nullable WKNavigation *)loadFileURL:(nonnull NSURL *)URL allowingReadAccessToURL:(nonnull NSURL *)readAccessURL;
@end


NS_ASSUME_NONNULL_BEGIN

// Special init which can't be reference directly in Swift, but cannot be a protocol either.
@interface _InitSelector: NSObject
// Init with script
- (id)initByScriptWithArguments:(NSArray *)args;
@end

NS_ASSUME_NONNULL_END
