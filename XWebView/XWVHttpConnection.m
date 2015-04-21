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

static NSMutableURLRequest *parseRequest(NSMutableURLRequest *request, const char *line);
static NSHTTPURLResponse *buildResponse(NSURLRequest *request, NSURL *rootURL);
static char *serializeResponse(const NSHTTPURLResponse *response, size_t *size);
static NSString *getMIMETypeByExtension(NSString *extension);


@implementation XWVHttpConnection {
    CFSocketNativeHandle _socket;
    NSInputStream *_input;
    NSOutputStream *_output;
    NSMutableArray *_requestQueue;

    // output state
    NSFileHandle *_file;
    off_t _fileSize;
    char *_headerBuf;
    size_t _headerSize;
    size_t _bytesSent;

    // input state
    NSMutableURLRequest *_request;
    char *_lineBuf;
    size_t _lineSize;
    NSUInteger _linePos;
}

- (id)initWithNativeHandle:(CFSocketNativeHandle)handle {
    if (self = [super init]) {
        _socket = handle;
        _requestQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)open {
    assert(_lineBuf == NULL);  // reopen is forbidden

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
    _input = NULL;
    _output = NULL;

    _file = nil;
    free(_lineBuf);
    free(_headerBuf);

    if (_delegate && [_delegate respondsToSelector:@selector(didCloseConnection:)])
        [_delegate didCloseConnection:self];
}

- (NSURL *)rootURL {
    NSURL *root;
    if (_delegate && [_delegate respondsToSelector:@selector(documentRoot)]) {
        root = [NSURL fileURLWithPath:_delegate.documentRoot isDirectory:YES];
        assert(root);
    } else {
        NSBundle *bundle = [NSBundle mainBundle];
        root = bundle.resourceURL ?: bundle.bundleURL;
        [root URLByAppendingPathComponent:@"www"];
    }
    return root;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
#define LINE_SIZE_DEFAULT 128

    switch(eventCode) {
        case NSStreamEventOpenCompleted: {
            // Initialize input/output state.
            if (aStream == _input) {
                _lineSize = LINE_SIZE_DEFAULT;
                _lineBuf = malloc(_lineSize);
                _linePos = 0;
                _request = nil;
            } else {
                _file = nil;
                _fileSize = 0;
                _headerBuf = NULL;
            }
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[LINE_SIZE_DEFAULT], *buf = buffer;
            NSUInteger len = [_input read:buffer maxLength:sizeof(buffer)];
            while (len--) {
                char c = *(buf++);
                if (c == '\r' && *buf == '\n') {
                    // End of line
                    ++buf; --len;
                    _lineBuf[_linePos] = 0;
                    _linePos = 0;
                    if (!_lineBuf[0] && _request != nil) {
                        // End of request headers.
                        [_requestQueue insertObject:_request atIndex:0];
                        _request = nil;
                    } else if (_request == nil || _request.URL != nil) {
                        _request = parseRequest(_request, _lineBuf);
                        if (_request == nil)  // bad request
                            _request = [NSMutableURLRequest new];
                    }
                } else {
                    // Copy to line buffer.
                    if (_linePos == _lineSize - 1) {
                        // Enlarge line buffer exponentially.
                        _lineSize <<= 1;
                        _lineBuf = realloc(_lineBuf, _lineSize);
                    }
                    _lineBuf[_linePos++] = c;
                }
            }
            if (!_output.hasSpaceAvailable)
                break;
        }
        case NSStreamEventHasSpaceAvailable: {
            if (!_headerBuf) {
                if (!_requestQueue.count)  break;
                NSURLRequest *request = _requestQueue.lastObject;
                [_requestQueue removeLastObject];
                NSHTTPURLResponse *response = buildResponse(request, [self rootURL]);
                if ([request.HTTPMethod compare:@"GET"] == NSOrderedSame) {
                    _file = [NSFileHandle fileHandleForReadingFromURL:response.URL error:nil];
                    _fileSize = _file.seekToEndOfFile;
                }
                _headerBuf = serializeResponse(response, &_headerSize);
                --_headerSize;  // exclude the terminator
                _bytesSent = 0;
            }

            off_t len = 0;
#if TARGET_OS_IPHONE
            if (_bytesSent < _headerSize) {
                // Send response header
                len = [_output write:(uint8_t*)(_headerBuf + _bytesSent) maxLength:(_headerSize - _bytesSent)];
            } else if (_file != nil) {
                // Send file content
                [_file seekToFileOffset:_bytesSent - _headerSize];
                NSData *data = [_file readDataToEndOfFile];
                len = [_output write:data.bytes maxLength:data.length];
            }
#else
            if (_file != nil) {
                // Send message body with sendfile(2) syscall rather than copy file content in user space.
                off_t offset = 0;
                struct sf_hdtr hdtr = {NULL, 0, NULL, 0};
                if (_bytesSent < _headerSize) {
                    struct iovec iovec;
                    iovec.iov_base = _headerBuf + _bytesSent;
                    iovec.iov_len = _headerSize - _bytesSent;
                    hdtr.headers = &iovec;
                    hdtr.hdr_cnt = 1;
                } else {
                    // Partial contents of file has been sent.
                    offset = _fileSize - (_bytesSent - _headerSize);
                }
                if (sendfile(_file.fileDescriptor, _socket, offset, &len, &hdtr, 0) < 0 && errno != EAGAIN)
                    len = -1;
            } else {
                // Response has no message body.
                len = [_output write:(uint8_t*)(_headerBuf + _bytesSent) maxLength:(_headerSize - _bytesSent)];
            }
#endif
            if (len > 0) {
                _bytesSent += len;
                if (_bytesSent == _headerSize + _fileSize) {
                    // Response has been sent completely.
                    _file = nil;
                    _fileSize = 0;
                    free(_headerBuf);
                    _headerBuf = NULL;
                }
                break;
            }
        }
        case NSStreamEventEndEncountered:
        case NSStreamEventErrorOccurred:
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

NSMutableURLRequest *parseRequest(NSMutableURLRequest *request, const char *line) {
    char *p, *q;
    if (!request) {
        // Parse request line
        p = strchr(line, ' ');
        q = strrchr(line, ' ');
        if (!p || !q || strncmp(q + 1, HttpVersion, sizeof(HttpVersion) - 1))
            return nil;
        for (int i = 0; i < sizeof(HttpRequestMethodToken); ++i) {
            if (!strncmp(line, HttpRequestMethodToken[i], p - line)) {
                ++p;
                NSString *path = [[NSString alloc] initWithBytes:p length:(q - p) encoding:NSASCIIStringEncoding];
                NSURL *url = [[NSURL alloc] initWithScheme:@"http" host:@"" path:path];
                request = [NSMutableURLRequest requestWithURL:url];
                request.HTTPMethod = [NSString stringWithUTF8String:HttpRequestMethodToken[i]];
                break;
            }
        }
    } else if ((p = strchr(line, ':')) != NULL) {
        // Parse header field
        *(p++) = 0;
        while (isspace(*p)) ++p;
        for (NSInteger i = strlen(p) - 1; isspace(p[i]); --i)
            p[i] = 0;
        NSString *name = [NSString stringWithCString:line encoding:NSASCIIStringEncoding];
        NSString *value = [NSString stringWithCString:p encoding:NSASCIIStringEncoding];

        if (!strcasecmp(line, "Host")) {
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
    return [[NSHTTPURLResponse alloc] initWithURL:fileURL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers];
}

char *serializeResponse(const NSHTTPURLResponse *response, size_t *size) {
    NSDictionary *headers = response.allHeaderFields;
    NSString *name, *value;
    NSEnumerator *enumerator;

    int class = (int)response.statusCode / 100 - 1;
    assert(class >= 0 && class < 5);
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
    while (name = [enumerator nextObject]) {
        value = headers[name];
        len += name.length + value.length + 4;
    }
    if (size)  *size = len;

    char *buffer = malloc(len);
    int pos = sprintf(buffer, "%s %3zd %s\r\n", HttpVersion, response.statusCode, reason);
    enumerator = [headers keyEnumerator];
    while (name = [enumerator nextObject]) {
        value = headers[name];
        pos += sprintf(buffer + pos, "%s: %s\r\n", name.UTF8String, value.UTF8String);
    }
    sprintf(buffer + pos, "\r\n");
    return buffer;
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
