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

#include <sys/socket.h>
#include <netinet/in.h>

#import "XWVHttpServer.h"
#import "XWVHttpConnection.h"

@interface XWVHttpServer () <XWVHttpConnectionDelegate>
@end

@implementation XWVHttpServer {
    CFSocketRef _socket;
    NSMutableSet *_connections;
    NSString *_documentRoot;
}

- (in_port_t)port {
    in_port_t port = 0;
    if (_socket != NULL) {
        NSData *addr = (__bridge_transfer NSData *)CFSocketCopyAddress(_socket);
        port = ntohs(((const struct sockaddr_in *)[addr bytes])->sin_port);
    }
    return port;
}

- (NSString *)documentRoot {
    return _documentRoot;
}

- (id)initWithDocumentRoot:(NSString *)root {
    if (self = [super init]) {
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
            return nil;
        }
        _documentRoot = [root copy];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)didCloseConnection:(NSNotification *)connection {
    [_connections removeObject:connection];
}

static void ServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    XWVHttpServer *server = (__bridge XWVHttpServer *)info;
    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data;
    assert(socket == server->_socket && type == kCFSocketAcceptCallBack);

    XWVHttpConnection * conn = [[XWVHttpConnection alloc] initWithNativeHandle:handle];
    [server->_connections addObject:conn];
    conn.delegate = server;
    [conn open];
}

- (BOOL)start {
    if (_socket != nil) return NO;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(0);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    NSData *address = [NSData dataWithBytes:&addr length:sizeof(addr)];
    CFSocketSignature signature = {PF_INET, SOCK_STREAM, IPPROTO_TCP, (__bridge CFDataRef)(address)};

    CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    _socket = CFSocketCreateWithSocketSignature(kCFAllocatorDefault, &signature, kCFSocketAcceptCallBack, &ServerAcceptCallBack, &context);
    if (_socket == NULL)  return NO;

    const int yes = 1;
    setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    _connections = [[NSMutableSet alloc] init];
    [NSThread detachNewThreadSelector:@selector(serverLoop:) toTarget:self withObject:nil];
    return YES;
}

- (void)stop {
    // Close all connections.
    for (XWVHttpConnection * conn in _connections) {
        conn.delegate = nil;
        [conn close];
    }
    _connections = nil;

    // Close server socket.
    if (_socket != NULL) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
}

- (void)serverLoop:(id)unused {
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, _socket, 0);
    CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes);
    CFRelease(source);
    CFRunLoopRun();
}

@end
