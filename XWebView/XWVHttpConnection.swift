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

import Foundation

protocol XWVHttpConnectionDelegate {
    func handleRequest(request: NSURLRequest) -> NSHTTPURLResponse
    func didOpenConnection(connection: XWVHttpConnection)
    func didCloseConnection(connection: XWVHttpConnection)
}

final class XWVHttpConnection : NSObject {
    private let handle: CFSocketNativeHandle
    private let delegate: XWVHttpConnectionDelegate
    private var input: NSInputStream!
    private var output: NSOutputStream!
    private let bufferMaxSize = 64 * 1024

    // input state
    private var requestQueue = [NSURLRequest]()
    private var inputBuffer: NSMutableData!
    private var cursor: Int = 0

    // output state
    private var outputBuffer: NSData!
    private var bytesRemained: Int = 0
    private var fileHandle: NSFileHandle!
    private var fileSize: Int = 0

    init(handle: CFSocketNativeHandle, delegate: XWVHttpConnectionDelegate) {
        self.handle = handle
        self.delegate = delegate
        super.init()
    }

    func open() -> Bool {
        let ptr1 = UnsafeMutablePointer<Unmanaged<CFReadStream>?>.alloc(1)
        let ptr2 = UnsafeMutablePointer<Unmanaged<CFWriteStream>?>.alloc(1)
        defer {
            ptr1.dealloc(1)
            ptr2.dealloc(1)
        }
        CFStreamCreatePairWithSocket(nil, handle, ptr1, ptr2)
        if ptr1.memory == nil || ptr2.memory == nil { return false }

        input = ptr1.memory!.takeRetainedValue()
        output = ptr2.memory!.takeRetainedValue()
        CFReadStreamSetProperty(input, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue)
        CFWriteStreamSetProperty(output, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue)

        input.delegate = self
        output.delegate = self
        input.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        output.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        input.open()
        output.open()
        delegate.didOpenConnection(self)
        return true
    }

    func close() {
        input.close()
        output.close()
        input = nil
        output = nil
        delegate.didCloseConnection(self)
    }
}

extension XWVHttpConnection : NSStreamDelegate {
    @objc func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch eventCode {
        case NSStreamEvent.OpenCompleted:
            // Initialize input/output state.
            if aStream === input {
                inputBuffer = NSMutableData(length: 512)
                cursor = 0;
            } else {
                outputBuffer = nil
                fileHandle = nil
                fileSize = 0
            }

        case NSStreamEvent.HasBytesAvailable:
            let base = UnsafeMutablePointer<UInt8>(inputBuffer.mutableBytes)
            let bytesReaded = input.read(base.advancedBy(cursor), maxLength: inputBuffer.length - cursor)
            guard bytesReaded > 0 else { break }

            var bytesConsumed = 0
            var ptr = cursor > 3 ? base.advancedBy(cursor - 3): base
            for _ in 0 ..< bytesReaded {
                if UnsafePointer<UInt32>(ptr).memory == UInt32(bigEndian: 0x0d0a0d0a) {
                    // End of request header.
                    ptr += 3
                    let data = inputBuffer.subdataWithRange(NSRange(bytesConsumed...base.distanceTo(ptr)))
                    if let request = NSMutableURLRequest(data: data) {
                        requestQueue.insert(request, atIndex: 0)
                    } else {
                        // Bad request
                        requestQueue.insert(NSURLRequest(), atIndex: 0)
                    }
                    bytesConsumed += data.length
                }
                ++ptr
            }
            if bytesConsumed > 0 {
                // Move remained bytes to the begining.
                inputBuffer.replaceBytesInRange(NSRange(0..<bytesConsumed), withBytes: nil, length: 0)
            } else if bytesReaded + cursor == inputBuffer.length {
                // Enlarge input buffer.
                guard inputBuffer.length < bufferMaxSize else {
                    close()
                    break
                }
                inputBuffer.length <<= 1
            }
            cursor += bytesReaded - bytesConsumed
            if output.hasSpaceAvailable { fallthrough }

        case NSStreamEvent.HasSpaceAvailable:
            if outputBuffer == nil {
                guard let request = requestQueue.popLast() else { break }
                let response = delegate.handleRequest(request)
                if request.HTTPMethod == "GET", let fileURL = response.URL where fileURL.fileURL {
                    fileHandle = try! NSFileHandle(forReadingFromURL: fileURL)
                    fileSize = Int(fileHandle.seekToEndOfFile())
                }
                outputBuffer = response.octetsOfHeaders
                bytesRemained = outputBuffer.length + fileSize
            }

            var bytesSent = 0
            repeat {
                let off: Int
                if bytesRemained > fileSize {
                    // Send response header
                    off = outputBuffer.length - (bytesRemained - fileSize)
                } else {
                    // Send file content
                    off = (fileSize - bytesRemained) % bufferMaxSize
                    if off == 0 {
                        fileHandle.seekToFileOffset(UInt64(fileSize - bytesRemained))
                        outputBuffer = fileHandle.readDataOfLength(bufferMaxSize)
                    }
                }
                let ptr = UnsafePointer<UInt8>(outputBuffer.bytes)
                bytesSent = output.write(ptr.advancedBy(off), maxLength: outputBuffer.length - off)
                bytesRemained -= bytesSent
            } while bytesRemained > 0 && output.hasSpaceAvailable && bytesSent > 0
            if bytesRemained == 0 {
                // Response has been sent completely.
                fileHandle = nil
                fileSize = 0
                outputBuffer = nil
            }
            if bytesSent < 0 { fallthrough }

        case NSStreamEvent.ErrorOccurred:
            print("<XWV> ERROR: " + (aStream.streamError?.localizedDescription ?? "Unknown"))
            fallthrough

        case NSStreamEvent.EndEncountered:
            fileHandle = nil
            inputBuffer = nil
            outputBuffer = nil
            close()

        default:
            break
        }
    }
}

private extension String {
    mutating func trim(@noescape predicate: (Character) -> Bool) {
        if !isEmpty {
            var start = startIndex
            var end = endIndex.predecessor()
            for var s = start; s != endIndex && predicate(self[s]); start = ++s {}
            if start == endIndex {
                self = ""
            } else {
                for var e = end; predicate(self[e]); end = --e {}
                self = self[start ... end]
            }
        }
    }
}

private extension NSMutableURLRequest {
    private enum Version : String {
        case v1_0 = "HTTP/1.0"
        case v1_1 = "HTTP/1.1"
    }
    private enum Method : String {
        case Get     = "GET"
        case Head    = "HEAD"
        case Post    = "POST"
        case Put     = "PUT"
        case Delete  = "DELETE"
        case Connect = "CONNECT"
        case Options = "OPTIONS"
        case Trace   = "TRACE"
    }
    private var CRLF: NSData {
        var CRLF: [UInt8] = [ 0x0d, 0x0a ]
        return NSData(bytes: &CRLF, length: 2)
    }

    convenience init?(data: NSData) {
        self.init()
        var cursor = 0
        repeat {
            let range = NSRange(cursor..<data.length)
            guard let end = data.rangeOfData(CRLF, options: NSDataSearchOptions(rawValue: 0), range: range).toRange()?.startIndex,
                  let line = NSString(data: data.subdataWithRange(NSRange(cursor..<end)), encoding: NSASCIIStringEncoding) as? String else {
                return nil
            }
            if cursor == 0 {
                // request line
                var method: Method?
                var target: String = ""
                var version: Version?
                if let sp = line.characters.indexOf(" ") {
                    method = Method(rawValue: line[line.startIndex ..< sp])
                    target = line[sp.successor() ..< line.endIndex]
                    if method != nil, let sp = target.characters.indexOf(" ") {
                        version = Version(rawValue: target[sp.successor() ..< target.endIndex])
                        target = target[target.startIndex ..< sp]
                    }
                }
                guard version != nil else { return nil }
                HTTPMethod = method!.rawValue
                URL = NSURL(string: target)
            } else if !line.isEmpty {
                // header field
                guard let colon = line.characters.indexOf(":") else { return nil }
                let name = line[line.startIndex ..< colon]
                var value = line[colon.successor() ..< line.endIndex]
                value.trim { $0 == " " || $0 == "\t" }
                if valueForHTTPHeaderField(name) != nil {
                    addValue(value, forHTTPHeaderField:name)
                } else {
                    setValue(value, forHTTPHeaderField:name)
                }
            }
            cursor = end + 2
        } while cursor < data.length
    }
}

private extension NSHTTPURLResponse {
    var octetsOfHeaders: NSData {
        assert(statusCode > 100 && statusCode < 600)
        let reason = NSHTTPURLResponse.localizedStringForStatusCode(statusCode).capitalizedString
        let statusLine = "HTTP/1.1 \(statusCode) \(reason)\r\n"
        let data = allHeaderFields.reduce(NSMutableData(data: statusLine.dataUsingEncoding(NSASCIIStringEncoding)!)) {
            $0.appendData(($1.0 as! NSString).dataUsingEncoding(NSASCIIStringEncoding)!)
            $0.appendData(": ".dataUsingEncoding(NSASCIIStringEncoding)!)
            $0.appendData(($1.1 as! NSString).dataUsingEncoding(NSASCIIStringEncoding)!)
            $0.appendData("\r\n".dataUsingEncoding(NSASCIIStringEncoding)!)
            return $0
        }
        data.appendData("\r\n".dataUsingEncoding(NSASCIIStringEncoding)!)
        return data
    }
}
