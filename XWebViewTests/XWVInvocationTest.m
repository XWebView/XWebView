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

#import <XCTest/XCTest.h>
#import "XWVInvocation.h"

@interface ClassForInvocationTest : NSObject
@property(nonatomic, copy) NSString* name;

- (id)initWithName:(NSString*)name;
- (void)asyncMethod:(XCTestExpectation*)expectation;

@end

@implementation ClassForInvocationTest

- (id)initWithName:(NSString *)name {
    if (self = [super init]) {
        _name = name;
    }
    return self;
}

- (NSString*)getName {
    return _name;
}

- (void)asyncMethod:(XCTestExpectation*)expectation {
    [expectation fulfill];
}

@end

@interface XWVInvocationTest : XCTestCase
@property(nonatomic, strong) ClassForInvocationTest* demo;

@end

@implementation XWVInvocationTest

- (void)setUp {
    [super setUp];
    self.demo = [[ClassForInvocationTest alloc] initWithName:@"TestObject"];
}

- (void)tearDown {
    [super tearDown];
    self.demo = nil;
}

- (void)testConstruct {
    XCTAssertNotNil([XWVInvocation construct:ClassForInvocationTest.class initializer:NSSelectorFromString(@"initWithName:") arguments:@[@"AnotherTestObject"]]);
}

- (void)testCall {
    NSValue* value = [XWVInvocation call:self.demo selector:NSSelectorFromString(@"getName") arguments:nil];
    NSString* name = [NSString stringWithFormat:@"%@", [value pointerValue]];
    XCTAssertEqualObjects(@"TestObject", name);
}

- (void)testAsyncCall {
    XCTestExpectation *expectation = [self expectationWithDescription:@"AsyncCall"];
    [XWVInvocation asyncCall:self.demo selector:NSSelectorFromString(@"asyncMethod:"), expectation];
    [self waitForExpectationsWithTimeout:0.1 handler:^(NSError* error) {
        if (error) {
            XCTAssert(NO, @"testAsyncCall failed");
        }
    }];
}

@end
