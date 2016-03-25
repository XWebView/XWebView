//
//  FixSwift22.h
//  XWebView
//
//  Created by 张琪 on 16/3/22.
//  Copyright © 2016年 XWebView. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FixSwift22 : NSObject
+(nullable NSMethodSignature*)getSignatureWithObjCTypes:(nullable const char *)objcTypes;
+(nullable NSInvocation*)invocationWithMethodSignature:(nullable NSMethodSignature*)signature;
@end
