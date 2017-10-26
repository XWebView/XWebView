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
    func handleRequest(_ request: URLRequest?) -> HTTPURLResponse
    func didOpenConnection(_ connection: XWVHttpConnection)
    func didCloseConnection(_ connection: XWVHttpConnection)
}

final class XWVHttpConnection : NSObject {
    private let handle: CFSocketNativeHandle
    private let delegate: XWVHttpConnectionDelegate
    private var input: InputStream!
    private var output: OutputStream!
    private let bufferMaxSize = 64 * 1024

    // input state
    private var requestQueue = [URLRequest?]()
    private var inputBuffer: Data!
    private var cursor: Int = 0

    // output state
    private var outputBuffer: Data!
    private var bytesRemained: Int = 0
    private var fileHandle: FileHandle!
    private var fileSize: Int = 0

    init(handle: CFSocketNativeHandle, delegate: XWVHttpConnectionDelegate) {
        self.handle = handle
        self.delegate = delegate
        super.init()
    }

    func open() -> Bool {
        let ptr1 = UnsafeMutablePointer<Unmanaged<CFReadStream>?>.allocate(capacity: 1)
        let ptr2 = UnsafeMutablePointer<Unmanaged<CFWriteStream>?>.allocate(capacity: 1)
        defer {
            ptr1.deallocate(capacity: 1)
            ptr2.deallocate(capacity: 1)
        }
        CFStreamCreatePairWithSocket(nil, handle, ptr1, ptr2)
        guard ptr1.pointee != nil && ptr2.pointee != nil else {
            return false
        }

        input = ptr1.pointee!.takeRetainedValue()
        output = ptr2.pointee!.takeRetainedValue()
        CFReadStreamSetProperty(input, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)
        CFWriteStreamSetProperty(output, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)

        input.delegate = self
        output.delegate = self
        input.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        output.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
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

extension XWVHttpConnection : StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            // Initialize input/output state.
            if aStream === input {
                inputBuffer = Data(count: 512)
                cursor = 0
            } else {
                outputBuffer = nil
                fileHandle = nil
                fileSize = 0
            }

        case Stream.Event.hasBytesAvailable:
            let count = inputBuffer.count
            let bytesReaded = inputBuffer.withUnsafeMutableBytes {
                (base: UnsafeMutablePointer<UInt8>) -> Int in
                input.read(base.advanced(by: cursor), maxLength: count - cursor)
            }
            guard bytesReaded > 0 else { break }
            cursor += bytesReaded

            var bytesConsumed = 0
            while let eoh = inputBuffer.range(of: Data([13, 10, 13, 10]), in: bytesConsumed..<cursor) {
                // End of request header is found
                let data = inputBuffer.subdata(in: bytesConsumed..<eoh.upperBound)
                requestQueue.insert(URLRequest(data: data), at: 0)
                bytesConsumed += data.count
            }
            if bytesConsumed > 0 {
                // Move remained bytes to the begining.
                inputBuffer.replaceSubrange(0..<bytesConsumed, with: Data())
                cursor -= bytesConsumed
            } else if cursor == inputBuffer.count {
                // Enlarge input buffer.
                guard inputBuffer.count < bufferMaxSize else {
                    close()
                    break
                }
                inputBuffer.count <<= 1
            }
            if output.hasSpaceAvailable { fallthrough }

        case Stream.Event.hasSpaceAvailable:
            if outputBuffer == nil {
                guard let request = requestQueue.popLast() else { break }
                let response = delegate.handleRequest(request)
                if request?.httpMethod == "GET", let fileURL = response.url, fileURL.isFileURL {
                    fileHandle = try! FileHandle(forReadingFrom: fileURL)
                    fileSize = Int(fileHandle.seekToEndOfFile())
                }
                outputBuffer = response.octetsOfHeaders
                bytesRemained = outputBuffer.count + fileSize
            }

            var bytesSent = 0
            repeat {
                let off: Int
                if bytesRemained > fileSize {
                    // Send response header
                    off = outputBuffer.count - (bytesRemained - fileSize)
                } else {
                    // Send file content
                    off = (fileSize - bytesRemained) % bufferMaxSize
                    if off == 0 {
                        fileHandle.seek(toFileOffset: UInt64(fileSize - bytesRemained))
                        outputBuffer = fileHandle.readData(ofLength: bufferMaxSize)
                    }
                }
                bytesSent = outputBuffer.withUnsafeBytes{
                    (ptr: UnsafePointer<UInt8>) -> Int in
                    output.write(ptr.advanced(by: off), maxLength: outputBuffer.count - off)
                }
                bytesRemained -= bytesSent
            } while bytesRemained > 0 && output.hasSpaceAvailable && bytesSent > 0
            if bytesRemained == 0 {
                // Response has been sent completely.
                fileHandle = nil
                fileSize = 0
                outputBuffer = nil
            }
            if bytesSent < 0 { fallthrough }

        case Stream.Event.errorOccurred:
            let error = aStream.streamError?.localizedDescription ?? "Unknown"
            log("!HTTP connection error: \(error)")
            fallthrough

        case Stream.Event.endEncountered:
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
    mutating func trim(predicate: (Character) -> Bool) {
        if !isEmpty {
            var start = startIndex
            while start != endIndex && predicate(self[start]) {
                start = index(after: start)
            }
            if start < endIndex {
                var end = endIndex
                repeat {
                    end = index(before: end)
                } while predicate(self[end])
                self = String(self[start ... end])
            } else {
                self = ""
            }
        }
    }
}

private extension URLRequest {
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
    private static var CRLF: Data {
        return Data(bytes: [0x0d, 0x0a])
    }

    init?(data: Data) {
        guard var cursor = data.range(of: URLRequest.CRLF)?.lowerBound else { return nil }

        // parse request line
        if let line = String(data: data.subdata(in: 0..<cursor), encoding: String.Encoding.ascii),
            let fields = Optional(line.split(separator: " ")), fields.count == 3,
            let method = Method(rawValue: String(fields[0])),
            let url = URL(string: String(fields[1])),
            let _ = Version(rawValue: String(fields[2])) {
            self.init(url: url)
            httpMethod = method.rawValue
        } else {
            return nil
        }

        // parse request header
        cursor += 2
        while cursor < data.count {
            guard let end = data.range(of: URLRequest.CRLF, in: cursor..<data.count)?.lowerBound,
                  let line = String(data: data.subdata(in: cursor..<end), encoding: String.Encoding.ascii) else {
                return nil
            }
            guard line.isEmpty else {
                // end of request
                break
            }

            // parse header field
            guard let colon = line.index(of: ":") else { return nil }
            let name = String(line.prefix(upTo: colon))
            var value = String(line.suffix(from: line.index(after: colon)))
            value.trim { $0 == " " || $0 == "\t" }
            if self.value(forHTTPHeaderField: name) != nil {
                addValue(value, forHTTPHeaderField:name)
            } else {
                setValue(value, forHTTPHeaderField:name)
            }
            cursor = end + 2
        }
    }
}

private extension HTTPURLResponse {
    var octetsOfHeaders: Data {
        assert(statusCode > 100 && statusCode < 600)
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
        let content = allHeaderFields.reduce("HTTP/1.1 \(statusCode) \(reason)\r\n") {
            $0 + ($1.0 as! String) + ": " + ($1.1 as! String) + "\r\n"
        } + "\r\n"
        return content.data(using: String.Encoding.ascii)!
    }
}
