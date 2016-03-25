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

#import <UIKit/UIKit.h>

//! Project version number for XWebView.
FOUNDATION_EXPORT double XWebViewVersionNumber;

//! Project version string for XWebView.
FOUNDATION_EXPORT const unsigned char XWebViewVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <XWebView/PublicHeader.h>

// The workaround for loading file URL on iOS 8.x.
#import <WebKit/WKWebView.h>
@interface WKWebView (XWebView)
- (nullable WKNavigation *)loadFileURL:(nonnull NSURL *)URL allowingReadAccessToURL:(nonnull NSURL *)readAccessURL;
@end

#import <XWebView/FixSwift22.h>