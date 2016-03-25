//
//  FixSwift22.m
//  XWebView
//
//  Created by 张琪 on 16/3/22.
//  Copyright © 2016年 XWebView. All rights reserved.
//

#import "FixSwift22.h"

@implementation FixSwift22
+(NSMethodSignature*)getSignatureWithObjCTypes:(const char *)objcTypes{
    return [NSMethodSignature signatureWithObjCTypes:objcTypes];
}
+(NSInvocation*)invocationWithMethodSignature:(NSMethodSignature*)signature{
    return [NSInvocation invocationWithMethodSignature:signature];
}
@end
