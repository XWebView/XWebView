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

#import <Foundation/Foundation.h>

@interface NSValue (XWVInvocation)

@property (nonatomic, readonly) BOOL isNumber;
@property (nonatomic, readonly) BOOL isObject;
@property (nonatomic, readonly) BOOL isVoid;

+ (NSValue *)valueWithInvocation:(NSInvocation *)invocation;

@end

@interface XWVInvocation : NSObject

+ (id)construct:(Class)aClass initializer:(SEL)selector arguments:(NSArray *)args;
+ (id)constructOnThread:(NSThread *)thread class:(Class)aClass initializer:(SEL)selector arguments:(NSArray *)args;

+ (NSValue *)call:(id)target selector:(SEL)selector arguments:(NSArray *)args;
+ (NSValue *)callOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector arguments:(NSArray *)args;

+ (void)asyncCall:(id)target selector:(SEL)selector arguments:(NSArray *)args;
+ (void)asyncCallOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector arguments:(NSArray *)args;

// Variadic methods

+ (id)construct:(Class)aClass initializer:(SEL)selector, ...;
+ (id)constructOnThread:(NSThread *)thread class:(Class)aClass initializer:(SEL)selector, ...;

+ (NSValue *)call:(id)target selector:(SEL)selector, ...;
+ (NSValue *)callOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector, ...;

+ (void)asyncCall:(id)target selector:(SEL)selector, ...;
+ (void)asyncCallOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector, ...;

@end
