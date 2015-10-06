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
#include <unistd.h>

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

#import "XWVHttpConnection.h"

static NSMutableURLRequest *parseRequest(NSMutableURLRequest *request, NSData *line);
static NSHTTPURLResponse *buildResponse(NSURLRequest *request, NSURL *rootURL);
static NSData *serializeResponse(const NSHTTPURLResponse *response);
static NSString *getMIMETypeByExtension(NSString *extension);


@implementation XWVHttpConnection {
    CFSocketNativeHandle _socket;
    NSInputStream *_input;
    NSOutputStream *_output;
    NSMutableArray *_requestQueue;

    // output state
    NSFileHandle *_file;
    size_t _fileSize;
    NSData* _outputBuf;
    size_t _bytesRemain;

    // input state
    NSMutableURLRequest *_request;
    NSUInteger _cursor;
    NSMutableData *_inputBuf;
}

- (id)initWithNativeHandle:(CFSocketNativeHandle)handle {
    if (self = [super init])
        _socket = handle;
    return self;
}

- (BOOL)open {
    if (_requestQueue != nil) return NO;  // reopen is forbidden

    CFReadStreamRef input = NULL;
    CFWriteStreamRef output = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, _socket, &input, &output);
    if (input == NULL || output == NULL) {
        return NO;
    }
    CFReadStreamSetProperty(input, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(output, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

    _input = CFBridgingRelease(input);
    _output = CFBridgingRelease(output);
    [_input  setDelegate:self];
    [_output setDelegate:self];
    [_input  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_input  open];
    [_output open];

    if (_delegate && [_delegate respondsToSelector:@selector(didOpenConnection:)])
        [_delegate didOpenConnection:self];
    return YES;
}

- (void)close {
    [_input  close];
    [_output close];
    _input = nil;
    _output = nil;

    _file = nil;
    _inputBuf = nil;
    _outputBuf = nil;

    if (_delegate && [_delegate respondsToSelector:@selector(didCloseConnection:)])
        [_delegate didCloseConnection:self];
}

- (NSURL *)rootURL {
    NSURL *root;
    if (_delegate && [_delegate respondsToSelector:@selector(documentRoot)]) {
        root = [NSURL fileURLWithPath:_delegate.documentRoot isDirectory:YES];
        NSAssert(root != nil, @"<XWV> you must set a valid documentRoot");
    } else {
        NSBundle *bundle = [NSBundle mainBundle];
        root = bundle.resourceURL ?: bundle.bundleURL;
        [root URLByAppendingPathComponent:@"www"];
    }
    return root;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch(eventCode) {
        case NSStreamEventOpenCompleted: {
            // Initialize input/output state.
            if (aStream == _input) {
                _cursor = 0;
                _request = nil;
                _inputBuf = [[NSMutableData alloc] initWithLength:512];
                _requestQueue = [[NSMutableArray alloc] init];
            } else {
                _file = nil;
                _fileSize = 0;
                _outputBuf = nil;
            }
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            NSInteger len = [_input read:(_inputBuf.mutableBytes + _cursor) maxLength:(_inputBuf.length - _cursor)];
            if (len <= 0)  break;
            len += _cursor;
            _cursor = 0;
            uint8_t *buf = _inputBuf.mutableBytes;
            for (int i = 1; i < len; ++i) {
                if (buf[i] == '\n' && buf[i - 1] == '\r') {
                    // End of line
                    if (_cursor == i - 1 && _request != nil) {
                        // End of request header.
                        [_requestQueue insertObject:_request atIndex:0];
                        _request = nil;
                    } else if (_request == nil || _request.URL != nil) {
                        NSData *line = [NSData dataWithBytesNoCopy:(buf + _cursor) length:(i - _cursor - 1)];
                        _request = parseRequest(_request, line);
                        if (_request == nil)  // bad request
                            _request = [NSMutableURLRequest new];
                    }
                    _cursor = i + 1;
                }
            }
            if (_cursor > 0) {
                // Move unparsed data to the begining.
                memmove(buf, buf + _cursor, len - _cursor);
            } else {
                // Enlarge input buffer.
                _inputBuf.length <<= 1;
            }
            _cursor = len - _cursor;
            if (!_output.hasSpaceAvailable)
                break;
        }
        case NSStreamEventHasSpaceAvailable: {
            if (!_outputBuf) {
                if (!_requestQueue.count)  break;
                NSURLRequest *request = _requestQueue.lastObject;
                [_requestQueue removeLastObject];
                NSHTTPURLResponse *response = buildResponse(request, [self rootURL]);
                if ([request.HTTPMethod compare:@"GET"] == NSOrderedSame) {
                    _file = [NSFileHandle fileHandleForReadingFromURL:response.URL error:nil];
                    _fileSize = (size_t)_file.seekToEndOfFile;
                }
                _outputBuf = serializeResponse(response);
                _bytesRemain = _outputBuf.length + _fileSize;
            }

#define CHUNK_SIZE (128 * 1024)
            NSInteger len;
            do {
                size_t off;
                if (_bytesRemain > _fileSize) {
                    // Send response header
                    off = _outputBuf.length - (_bytesRemain - _fileSize);
                } else if (!(off = (_fileSize - _bytesRemain) % CHUNK_SIZE)) {
                    // Send file content
                    [_file seekToFileOffset:(_fileSize - _bytesRemain)];
                    _outputBuf = [_file readDataOfLength:CHUNK_SIZE];
                }
                len = [_output write:(_outputBuf.bytes + off) maxLength:(_outputBuf.length - off)];
                _bytesRemain -= len;
            } while (_bytesRemain && _output.hasSpaceAvailable && len > 0);
            if (_bytesRemain == 0) {
                // Response has been sent completely.
                _file = nil;
                _fileSize = 0;
                _outputBuf = nil;
            }
            if (len >= 0)  break;
        }
        case NSStreamEventErrorOccurred:
            NSLog(@"ERROR: %@", aStream.streamError.localizedDescription);
        case NSStreamEventEndEncountered:
            [self close];
        case NSStreamEventNone:
            break;
    }
}

@end


static const char HttpVersion[] = "HTTP/1.1";
static const char* HttpRequestMethodToken[] = {
    "GET",
    "HEAD",
    "POST",
    "PUT",
    "DELETE",
    "CONNECT",
    "OPTIONS",
    "TRACE"
};
static const char* HttpResponseReasonPhrase[5][6] = {
    {
        "Continue"                    // 100
    },
    {
        "OK"                          // 200
    },
    {
        "Multiple Choices"            // 300
    },
    {
        "Bad Request",                // 400
        NULL,
        NULL,
        NULL,
        "Not Found",                  // 404
        "Method Not Allowed"          // 405
    },
    {
        "Internal Server Error",      // 500
        "Not Implemented",            // 501
        NULL,
        NULL,
        NULL,
        "HTTP Version Not Supported"  // 505
    }
};

NSMutableURLRequest *parseRequest(NSMutableURLRequest *request, NSData *line) {
    const uint8_t *buf = line.bytes;
    NSUInteger size = line.length;
    const uint8_t *p, *q = NULL;

    if (!request) {
        // Parse request line
        if ((p = memchr(buf, ' ', size)) != NULL) {
            ++p;
            q = memchr(p, ' ', size - (p - buf));
        }
        if (!p || !q || memcmp(q + 1, HttpVersion, sizeof(HttpVersion) - 1))
            return nil;
        for (int i = 0; i < sizeof(HttpRequestMethodToken); ++i) {
            const char *token = HttpRequestMethodToken[i];
            if (!memcmp(buf, token, strlen(token) - 1)) {
                NSString *path = [[NSString alloc] initWithBytes:p length:(q - p) encoding:NSASCIIStringEncoding];
                NSURL *url = [[NSURL alloc] initWithScheme:@"http" host:@"" path:path];
                request = [NSMutableURLRequest requestWithURL:url];
                request.HTTPMethod = [NSString stringWithUTF8String:token];
                break;
            }
        }
    } else if ((p = memchr(buf, ':', size)) != NULL) {
        // Parse header field
        NSString *name, *value;
        name = [[NSString alloc] initWithBytes:buf length:(p - buf) encoding:NSASCIIStringEncoding];
        while (isspace(*(++p)));
        value = [[NSString alloc] initWithBytes:p length:(size - (p - buf)) encoding:NSASCIIStringEncoding];

        if (!strncasecmp((const char *)buf, "Host", 4)) {
            // Support origin-form only
            request.URL = [[NSURL alloc] initWithScheme:@"http" host:value path:request.URL.path];
        } else {
            if ([request valueForHTTPHeaderField:name])
                [request addValue:value forHTTPHeaderField:name];
            else
                [request setValue:value forHTTPHeaderField:name];
        }
    } else {
        return nil;
    }
    return request;
}

NSHTTPURLResponse *buildResponse(NSURLRequest *request, NSURL *documentRoot) {
    // Date format, see section 7.1.1.1 of RFC7231
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
    dateFormatter.dateFormat = @"E, dd MMM yyyy HH:mm:ss z";

    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithObject:[dateFormatter stringFromDate:NSDate.date] forKey:@"Date"];
    NSURL *fileURL = nil;
    int statusCode = 500;
    if (request == nil || request.URL == nil) {
        statusCode = 400;  // Bad request
    } else if ([request.HTTPMethod compare:@"GET"] == NSOrderedSame ||
               [request.HTTPMethod compare:@"HEAD"] == NSOrderedSame) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        fileURL = [documentRoot URLByAppendingPathComponent:request.URL.path];
        if ([fileManager fileExistsAtPath:fileURL.path isDirectory:&isDirectory] && isDirectory) {
            fileURL = [fileURL URLByAppendingPathComponent:@"/index.html"];
        }
        if ([fileManager isReadableFileAtPath:fileURL.path]) {
            statusCode = 200;
            NSDictionary *attrs = [fileManager attributesOfItemAtPath:fileURL.path error:nil];
            headers[@"Content-Type"] = getMIMETypeByExtension(fileURL.pathExtension);
            headers[@"Content-Length"] = [NSString stringWithFormat:@"%llu", attrs.fileSize];
            headers[@"Last-Modified"] = [dateFormatter stringFromDate:attrs.fileModificationDate];
        } else {
            statusCode = 404;  // Not found
        }
    } else {
        statusCode = 405;  // Method Not Allowed
        headers[@"Allow"] = @"GET HEAD";
    }
    if (statusCode != 200) {
        headers[@"Content-Length"] = @"0";
    }
    return [[NSHTTPURLResponse alloc] initWithURL:fileURL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers];
}

NSData *serializeResponse(const NSHTTPURLResponse *response) {
    NSDictionary *headers = response.allHeaderFields;
    NSEnumerator *enumerator;
    NSString *name;

    int class = (int)response.statusCode / 100 - 1;
    NSCAssert(class >= 0 && class < 5, @"<XWV> status code must be in the range [100, 599]");
    
    int code  = (int)response.statusCode % 100;
    if (code >= sizeof(HttpResponseReasonPhrase[class]) / sizeof(char *) ||
        HttpResponseReasonPhrase[class][code] == NULL) {
        // Treat an unrecognized status code as being equivalent to the x00 status code of that class.
        code = 0;
    }
    const char *reason = HttpResponseReasonPhrase[class][code];

    // Calculate buffer size
    size_t len = sizeof(HttpVersion) + 5 + strlen(reason) + 4;
    enumerator = [headers keyEnumerator];
    while (name = [enumerator nextObject])
        len += name.length + [headers[name] length] + 4;

    NSMutableData *data = [[NSMutableData alloc] initWithLength:len];
    char *buf = data.mutableBytes;
    buf += sprintf(buf, "%s %3zd %s\r\n", HttpVersion, response.statusCode, reason);
    enumerator = [headers keyEnumerator];
    while (name = [enumerator nextObject])
        buf += sprintf(buf, "%s: %s\r\n", name.UTF8String, [headers[name] UTF8String]);
    sprintf(buf, "\r\n");
    --data.length;
    return data;
}

NSString *getMIMETypeByExtension(NSString *extension) {
    static NSMutableDictionary *mimeTypeCache = nil;
    if (mimeTypeCache == nil) {
        // Add all MIME types which are unknown to system here.
        mimeTypeCache = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                         @"text/css", @"css",
                         nil];
    }

    NSString *type = mimeTypeCache[extension];
    if (type == nil) {
        // Get MIME type through system-declared uniform type identifier.
        NSString *uti = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(extension), NULL);
        type = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)(uti), kUTTagClassMIMEType);
        if (type == nil)
            type = @"application/octet-stream";  // Fall back to binary stream.
    }
    mimeTypeCache[extension] = type;

    if ([type compare:@"text/" options:NSCaseInsensitiveSearch range:NSMakeRange(0,5)] == NSOrderedSame)
        return [type stringByAppendingString:@"; charset=utf-8"];  // Assume text resource is UTF-8 encoding
    return type;
}
