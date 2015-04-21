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

#ifndef XWebView_XWVHttpServer_h
#define XWebView_XWVHttpServer_h

#import <Foundation/Foundation.h>

@interface XWVHttpServer : NSObject

@property(nonatomic, readonly) in_port_t port;

- (id)initWithDocumentRoot:(NSString *)root;
- (BOOL)start:(NSThread *)thread;
- (void)stop;

@end

#endif
