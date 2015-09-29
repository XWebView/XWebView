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

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "XWVException.h"

@interface XWVException ()
@end

@implementation XWVException {

}

+ (void)raiseUnlessRoot:(NSURL *)root {
    if (root != nil) return;
    NSException *exception = [NSException exceptionWithName:@"XWVRootDirectoryNotFound"
                                                     reason:@"Can't find root directory"
                                                     userInfo:nil];
    @throw exception;
}

+ (void)raiseUnlessBadResponse:(const NSHTTPURLResponse *)response {
    int class = (int)response.statusCode / 100 - 1;
    if (class >= 0 && class < 5) return;
    
    NSDictionary *headers = response.allHeaderFields;
    NSException *exception = [NSException exceptionWithName:@"XWVWrongServerStatusCode"
                                                     reason:@"Server returnered a status code >= 500"
                                                   userInfo:@{
                                                              @"response": response,
                                                              @"headers": headers,
                                                              @"statusCode": @(response.statusCode)
                                                              }];
    @throw exception;
}

@end
