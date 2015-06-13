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

#import "XWVInvocation.h"

@interface NSNumber (XWVInvocation)
- (instancetype)initWithInvocation:(NSInvocation *)invocation;
- (void)getValue:(void *)buffer objCType:(const char *)type;
@end

@interface NSInvocation (XWVInvocation)
+ (NSInvocation *)invocationWithTarget:(id)target selector:(SEL)selector arguments:(NSArray *)args;
+ (NSInvocation *)invocationWithTarget:(id)target selector:(SEL)selector valist:(va_list)valist;
- (void)setArguments:(NSArray *)args;
- (void)setVariableArguments:(va_list)valist;
@end


@implementation NSValue (XWVInvocation)

+ (NSValue *)valueWithInvocation:(NSInvocation *)invocation {
    if (!invocation)  return nil;

    NSNumber *num = [[NSNumber alloc] initWithInvocation:invocation];
    if (num)  return num;

    NSMethodSignature *sig = invocation.methodSignature;
    const char *type = [sig methodReturnType];
    NSUInteger len = sig.methodReturnLength;
    if (len > sizeof(uint64_t)) {
        void *buffer = malloc(len);
        NSValue *value = [NSValue valueWithBytes:buffer objCType:type];
        free(buffer);
        return value;
    }

    uint64_t value = 0;
    if (len)
        [invocation getReturnValue:&value];
    return [NSValue valueWithBytes:&value objCType:type];
}

- (BOOL)isNumber {
    return [self isKindOfClass:NSNumber.class];
}
- (BOOL)isObject {
    return strcmp(self.objCType, @encode(id)) ? NO : YES;
}
- (BOOL)isVoid {
    return strcmp(self.objCType, @encode(void)) ? NO : YES;
}

@end


@implementation XWVInvocation

+ (id)construct:(Class)aClass initializer:(SEL)selector arguments:(NSArray *)args {
    return [XWVInvocation constructOnThread:nil class:aClass initializer:selector arguments:args];
}
+ (id)constructOnThread:(NSThread *)thread class:(Class)aClass initializer:(SEL)selector arguments:(NSArray *)args {
    id obj = [aClass alloc];
    NSInvocation* inv = [NSInvocation invocationWithTarget:obj selector:selector arguments:args];
    if (thread)
        [inv performSelector:@selector(invokeWithTarget:) onThread:thread withObject:obj waitUntilDone:YES];
    else
        [inv invoke];
    [inv getReturnValue:&obj];
    return obj;
}

+ (NSValue *)call:(id)target selector:(SEL)selector arguments:(NSArray *)args {
    return [XWVInvocation callOnThread:nil target:target selector:selector arguments:args];
}
+ (NSValue *)callOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector arguments:(NSArray *)args {
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector arguments:args];
    if (thread)
        [inv performSelector:@selector(invokeWithTarget:) onThread:thread withObject:target waitUntilDone:YES];
    else
        [inv invoke];
    return [NSValue valueWithInvocation:inv];
}

+ (void)asyncCall:(id)target selector:(SEL)selector arguments:(NSArray *)args {
    return [XWVInvocation asyncCallOnThread:nil target:target selector:selector arguments:args];
}
+ (void)asyncCallOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector arguments:(NSArray *)args {
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector arguments:args];
    [inv retainArguments];
    [inv performSelector:@selector(invokeWithTarget:) onThread:(thread ?: NSThread.currentThread) withObject:target waitUntilDone:NO];
}

// Variadic methods

+ (id)construct:(Class)aClass initializer:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    id obj = [aClass alloc];
    NSInvocation* inv = [NSInvocation invocationWithTarget:obj selector:selector valist:ap];
    va_end(ap);

    [inv invoke];
    [inv getReturnValue:&obj];
    return obj;
}
+ (id)constructOnThread:(NSThread *)thread class:(Class)aClass initializer:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    id obj = [aClass alloc];
    NSInvocation* inv = [NSInvocation invocationWithTarget:obj selector:selector valist:ap];
    va_end(ap);

    if (thread)
        [inv performSelector:@selector(invokeWithTarget:) onThread:thread withObject:obj waitUntilDone:YES];
    else
        [inv invoke];
    [inv getReturnValue:&obj];
    return obj;
}

+ (NSValue *)call:(id)target selector:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector valist:ap];
    va_end(ap);
    [inv invoke];
    return [NSValue valueWithInvocation:inv];
}
+ (NSValue *)callOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector valist:ap];
    va_end(ap);
    if (thread)
        [inv performSelector:@selector(invokeWithTarget:) onThread:thread withObject:target waitUntilDone:YES];
    else
        [inv invoke];
    return [NSValue valueWithInvocation:inv];
}

+ (void)asyncCall:(id)target selector:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector valist:ap];
    va_end(ap);
    [inv retainArguments];
    [inv performSelector:@selector(invokeWithTarget:) onThread:NSThread.currentThread withObject:target waitUntilDone:NO];
}
+ (void)asyncCallOnThread:(NSThread *)thread target:(id)target selector:(SEL)selector, ... {
    va_list ap;
    va_start(ap, selector);
    NSInvocation* inv = [NSInvocation invocationWithTarget:target selector:selector valist:ap];
    va_end(ap);
    [inv retainArguments];
    [inv performSelector:@selector(invokeWithTarget:) onThread:(thread ?: NSThread.currentThread) withObject:target waitUntilDone:NO];
}

@end

//////////////////////////////////////////////////////////////////////////

@implementation NSNumber (XWVInvocation)

#define ISTYPE(t)       (!strcmp(type, @encode(t)))
- (instancetype)initWithInvocation:(NSInvocation *)invocation {
    NSMethodSignature *sig = invocation.methodSignature;
    if (sig.methodReturnLength > sizeof(uint64_t) || !sig.methodReturnLength)
        return nil;

    const char *type = [sig methodReturnType];
    uint64_t value = 0;
    void *buffer = &value;
    [invocation getReturnValue:buffer];
#define NUMBER(type, suffix) return [self initWith##suffix: *(type *)buffer];
    if ISTYPE(BOOL)                    NUMBER(BOOL, Bool)
    else if ISTYPE(char)               NUMBER(char, Char)
    else if ISTYPE(short)              NUMBER(short, Short)
    else if ISTYPE(int)                NUMBER(int, Int)
    else if ISTYPE(long)               NUMBER(long, Long)
    else if ISTYPE(long long)          NUMBER(long long, LongLong)
    else if ISTYPE(unsigned char)      NUMBER(unsigned char, UnsignedChar)
    else if ISTYPE(unsigned short)     NUMBER(unsigned short, UnsignedShort)
    else if ISTYPE(unsigned int)       NUMBER(unsigned int, UnsignedInt)
    else if ISTYPE(unsigned long)      NUMBER(unsigned long, UnsignedLong)
    else if ISTYPE(unsigned long long) NUMBER(unsigned long long, UnsignedLongLong)
    else if ISTYPE(float)              NUMBER(float, Float)
    else if ISTYPE(double)             NUMBER(double, Double)
    else return nil;
#undef NUMBER
}

- (void)getValue:(void *)buffer objCType:(const char *)type {
#define VALUE(type, prefix) *(type *)buffer = self.prefix##Value;
    if ISTYPE(BOOL)                    VALUE(BOOL, bool)
    else if ISTYPE(char)               VALUE(char, char)
    else if ISTYPE(short)              VALUE(short, short)
    else if ISTYPE(int)                VALUE(int, int)
    else if ISTYPE(long)               VALUE(long, long)
    else if ISTYPE(long long)          VALUE(long long, longLong)
    else if ISTYPE(unsigned char)      VALUE(unsigned char, unsignedChar)
    else if ISTYPE(unsigned short)     VALUE(unsigned short, unsignedShort)
    else if ISTYPE(unsigned int)       VALUE(unsigned int, unsignedInt)
    else if ISTYPE(unsigned long)      VALUE(unsigned long, unsignedLong)
    else if ISTYPE(unsigned long long) VALUE(unsigned long long, unsignedLongLong)
    else if ISTYPE(float)              VALUE(float, float)
    else if ISTYPE(double)             VALUE(double, double)
    else [NSException raise:@"TypeError" format:@"'%s' is not a number type", type];
#undef VALUE
}
#undef ISTYPE

@end


@implementation NSInvocation (XWVInvocation)
+ (NSInvocation *)invocationWithTarget:(id)target selector:(SEL)selector arguments:(NSArray *)args {
    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (sig == nil) {
        [target doesNotRecognizeSelector:selector];
        return nil;
    }
    if ((args ? args.count : 0) < sig.numberOfArguments - 2)
        return nil;  // Too few arguments

    NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = selector;
    if (args && args.count)
        [inv setArguments:args];
    return inv;
}
+ (NSInvocation *)invocationWithTarget:(id)target selector:(SEL)selector valist:(va_list)valist {
    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (sig == nil) {
        [target doesNotRecognizeSelector:selector];
        return nil;
    }

    NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = selector;
    [inv setVariableArguments:valist];
    return inv;
}

- (void)setArguments:(NSArray *)args {
    NSMethodSignature *sig = self.methodSignature;
    NSUInteger cnt = MIN(sig.numberOfArguments - 2, args.count);
    for(NSUInteger i = 0; i < cnt; ++i) {
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        NSObject *val = [args objectAtIndex:i];
        void *buf = &val;
        if (val == NSNull.null) {
            // Convert NSNull to nil
            val = nil;
        } else if (strcmp(type, @encode(id))) {
            if ([val isKindOfClass:NSNumber.class]) {
                // Convert NSNumber to argument type
                NSNumber* num = (NSNumber*)val;
                unsigned long long data;
                buf = &data;
                [num getValue:buf objCType:type];
            } else if ([val isKindOfClass:NSValue.class]) {
                // TODO: Convert NSValue to argument type
            }
        }
        [self setArgument:buf atIndex:(i + 2)];
    }
}

- (void)setVariableArguments:(va_list)valist {
    NSMethodSignature *sig = self.methodSignature;
    for (NSUInteger i = 2; i < sig.numberOfArguments; ++i) {
        const char *type = [sig getArgumentTypeAtIndex: i];
        void *buf = NULL;
        NSUInteger size;
        NSGetSizeAndAlignment(type, NULL, &size);
        if (!strcmp(type, @encode(float))) {
            // The float value is promoted to double
            float data = (float)va_arg(valist, double);
            buf = &data;
        } else if (size < sizeof(int)) {
            // Types narrower than an int are promoted to int.
            if (size == sizeof(short)) {
                short data = (short)va_arg(valist, int);
                buf = &data;
            } else {
                char data = (char)va_arg(valist, int);
                buf = &data;
            }
        } else if (size <= sizeof(long long)) {
            // Any type that size is less or equal than long long.
            long long data = va_arg(valist, long long);
            buf = &data;
        } else {
            NSAssert(false, @"structure type is unsupported.");
        }
        [self setArgument:buf atIndex: i];
    }
}
@end
