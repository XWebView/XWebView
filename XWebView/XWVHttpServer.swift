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
#if os(iOS)
import UIKit
import MobileCoreServices
#else
import CoreServices
#endif

class XWVHttpServer : NSObject {
    fileprivate var socket: CFSocket!
    fileprivate var connections = Set<XWVHttpConnection>()
    fileprivate let overlays: [URL]
    private(set) var port: in_port_t = 0

    var rootURL: URL {
        return overlays.last!
    }
    var overlayURLs: [URL] {
        return overlays.dropLast().reversed()
    }

    init(rootURL: URL, overlayURLs: [URL]?) {
        precondition(rootURL.isFileURL)
        var overlays = [rootURL]
        overlayURLs?.forEach {
            precondition($0.isFileURL)
            overlays.append($0)
        }
        self.overlays = overlays.reversed()
        super.init()
    }
    convenience init(rootURL: URL) {
        self.init(rootURL: rootURL, overlayURLs: nil)
    }
    deinit {
        stop()
    }

    private func listen(on port: in_port_t) -> Bool {
        guard socket == nil else { return false }

        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = CFSocketContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let callbackType = CFSocketCallBackType.acceptCallBack.rawValue
        socket = CFSocketCreate(nil, PF_INET, SOCK_STREAM, 0, callbackType, ServerAcceptCallBack, &context)
        guard socket != nil else {
            log("!Failed to create socket")
            return false
        }

        var yes = UInt32(1)
        setsockopt(CFSocketGetNative(socket), SOL_SOCKET, SO_REUSEADDR, &yes, UInt32(MemoryLayout<UInt32>.size))

        var sockaddr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: UInt8(AF_INET),
            sin_port: port.bigEndian,
            sin_addr: in_addr(s_addr: UInt32(0x7f000001).bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        let data = Data(bytes: &sockaddr, count: MemoryLayout<sockaddr_in>.size)
        guard CFSocketSetAddress(socket, data as CFData!) == CFSocketError.success else {
            log("!Failed to listen on port \(port) \(String(cString: strerror(errno)))")
            CFSocketInvalidate(socket)
            return false
        }

        let serverLoop = #selector(XWVHttpServer.serverLoop(_:))
        Thread.detachNewThreadSelector(serverLoop, toTarget: self, with: nil)
        return true
    }

    private func close() {
        // Close all connections.
        connections.forEach { $0.close() }
        connections.removeAll()

        // Close server socket.
        if socket != nil {
            CFSocketInvalidate(socket)
            socket = nil
        }
    }

    func start(port: in_port_t = 0) -> Bool {
        if port == 0 {
            // Try to find a random port in registered ports range
            for _ in 0 ..< 100 {
                let port = in_port_t(arc4random() % (49152 - 1024) + 1024)
                if listen(on: port) {
                    self.port = port
                    break
                }
            }
        } else if listen(on: port) {
            self.port = port
        }
        guard self.port != 0 else { return false }

        #if os(iOS)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(XWVHttpServer.suspend(_:)),
                                               name: NSNotification.Name.UIApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(XWVHttpServer.resume(_:)),
                                               name: NSNotification.Name.UIApplicationWillEnterForeground,
                                               object: nil)
        #endif
        return true
    }

    func stop() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        #endif
        port = 0
        close()
    }

    @objc func suspend(_: NSNotification!) {
        close()
        log("+HTTP server is suspended")
    }
    @objc func resume(_: NSNotification!) {
        if listen(on: port) {
            log("+HTTP server is resumed")
        }
    }

    @objc func serverLoop(_: AnyObject) {
        let runLoop = CFRunLoopGetCurrent()
        let source = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(runLoop, source, CFRunLoopMode.commonModes)
        CFRunLoopRun()
    }
}

extension XWVHttpServer : XWVHttpConnectionDelegate {
    func didOpenConnection(_ connection: XWVHttpConnection) {
        connections.insert(connection)
    }
    func didCloseConnection(_ connection: XWVHttpConnection) {
        connections.remove(connection)
    }

    func handleRequest(_ request: URLRequest?) -> HTTPURLResponse {
        // Date format, see section 7.1.1.1 of RFC7231
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")
        dateFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"

        var headers: [String: String] = ["Date": dateFormatter.string(from: Date())]
        var statusCode = 500
        var fileURL: URL? = nil
        if request == nil {
            // Bad request
            statusCode = 400
            log("?Bad request")
        } else if let request = request, request.httpMethod == "GET" || request.httpMethod == "HEAD" {
            let fileManager = FileManager.default
            let relativePath = String(request.url!.path.characters.dropFirst())
            for baseURL in overlays {
                var isDirectory: ObjCBool = false
                var url = URL(string: relativePath, relativeTo: baseURL)!
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        url = url.appendingPathComponent("index.html")
                    }
                    if fileManager.isReadableFile(atPath: url.path) {
                        fileURL = url
                        break
                    }
                }
            }
            if let fileURL = fileURL {
                statusCode = 200
                let attrs = try! fileManager.attributesOfItem(atPath: fileURL.path)
                headers["Content-Type"] = getMIMETypeByExtension(extensionName: fileURL.pathExtension)
                headers["Content-Length"] = String(describing: attrs[FileAttributeKey.size]!)
                headers["Last-Modified"] = dateFormatter.string(from: attrs[FileAttributeKey.modificationDate] as! Date)
                log("+\(request.httpMethod!) \(fileURL.path)")
            } else {
                // Not found
                statusCode = 404
                fileURL = nil
                log("-File NOT found for URL \(request.url!)")
            }
        } else {
            // Method not allowed
            statusCode = 405
            headers["Allow"] = "GET HEAD"
        }
        if statusCode != 200 {
            headers["Content-Length"] = "0"
        }
        let url = fileURL ?? request?.url ?? URL(string: "nil")!
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

private func ServerAcceptCallBack(socket: CFSocket?, type: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) {
    let server = unsafeBitCast(info, to: XWVHttpServer.self)
    assert(socket === server.socket && type == CFSocketCallBackType.acceptCallBack)

    let handle = data!.load(as: CFSocketNativeHandle.self)
    let connection = XWVHttpConnection(handle: handle, delegate: server)
    _ = connection.open()
}

private var mimeTypeCache = [
    // MIME types which are unknown by system.
    "css" : "text/css"
]
private func getMIMETypeByExtension(extensionName: String) -> String {
    var type: String! = mimeTypeCache[extensionName]
    if type == nil {
        // Get MIME type through system-declared uniform type identifier.
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, extensionName as CFString, nil),
            let mt = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassMIMEType) {
                type = mt.takeRetainedValue() as String
        } else {
            // Fall back to binary stream.
            type = "application/octet-stream"
        }
        mimeTypeCache[extensionName] = type
    }
    if type.lowercased().hasPrefix("text/") {
        // Assume text resource is UTF-8 encoding
        return type + "; charset=utf-8"
    }
    return type
}
