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

import Darwin
import Foundation

public typealias asl_object_t = OpaquePointer

@_silgen_name("asl_open") func asl_open(_ ident: UnsafePointer<Int8>?, _ facility: UnsafePointer<Int8>?, _ opts: UInt32) -> asl_object_t?
@_silgen_name("asl_close") func asl_close(_ obj: asl_object_t)
@_silgen_name("asl_vlog") func asl_vlog(_ obj: asl_object_t, _ msg: asl_object_t?, _ level: Int32, _ format: UnsafePointer<Int8>, _ ap: CVaListPointer) -> Int32
@_silgen_name("asl_add_output_file") func asl_add_output_file(_ client: asl_object_t, _ descriptor: Int32, _ msg_fmt: UnsafePointer<Int8>?, _ time_fmt: UnsafePointer<Int8>?, _ filter: Int32, _ text_encoding: Int32) -> Int32
@_silgen_name("asl_set_output_file_filter") func asl_set_output_file_filter(_ asl: asl_object_t, _ descriptor: Int32, _ filter: Int32) -> Int32

public class XWVLogging : XWVScripting {
    public enum Level : Int32 {
        case Emergency = 0
        case Alert     = 1
        case Critical  = 2
        case Error     = 3
        case Warning   = 4
        case Notice    = 5
        case Info      = 6
        case Debug     = 7

        private static let symbols : [Character] = [
            "\0", "\0", "$", "!", "?", "-", "+", " "
        ]
        fileprivate init?(symbol: Character) {
            guard symbol != "\0", let value = Level.symbols.index(of: symbol) else {
                return nil
            }
            self = Level(rawValue: Int32(value))!
        }
    }

    public struct Filter : OptionSet {
        private var value: Int32
        public var rawValue: Int32 {
            return value
        }

        public init(rawValue: Int32) {
            self.value = rawValue
        }
        public init(mask: Level) {
            self.init(rawValue: 1 << mask.rawValue)
        }
        public init(upto: Level) {
            self.init(rawValue: 1 << (upto.rawValue + 1) - 1)
        }
        public init(filter: Level...) {
            self.init(rawValue: filter.reduce(0) { $0 | $1.rawValue })
        }
    }

    public var filter: Filter {
        didSet {
            _ = asl_set_output_file_filter(client, STDERR_FILENO, filter.rawValue)
        }
    }

    private let client: asl_object_t
    private var lock: pthread_mutex_t = pthread_mutex_t()
    public init(facility: String, format: String? = nil) {
        client = asl_open(nil, facility, 0)!
        pthread_mutex_init(&lock, nil)

        #if DEBUG
        filter = Filter(upto: .Debug)
        #else
        filter = Filter(upto: .Notice)
        #endif

        let format = format ?? "$((Time)(lcl)) $(Facility) <$((Level)(char))>: $(Message)"
        _ = asl_add_output_file(client, STDERR_FILENO, format, "sec", filter.rawValue, 1)
    }
    deinit {
        asl_close(client)
        pthread_mutex_destroy(&lock)
    }

    public func log(_ message: String, level: Level) {
        pthread_mutex_lock(&lock)
        _ = asl_vlog(client, nil, level.rawValue, message, getVaList([]))
        pthread_mutex_unlock(&lock)
    }

    public func log(_ message: String, level: Level? = nil) {
        var msg = message
        var lvl = level ?? .Debug
        if level == nil, let ch = msg.first, let l = Level(symbol: ch) {
            msg = String(msg.dropFirst())
            lvl = l
        }
        log(msg, level: lvl)
    }

    @objc public func invokeDefaultMethod(withArguments args: [Any]!) -> Any! {
        guard args.count > 0 else { return nil }
        let message = args[0] as? String ?? "\(args[0])"
        var level: Level? = nil
        if args.count > 1, let num = args[1] as? Int {
            if 3 <= num && num <= 7 {
                level = Level(rawValue: Int32(num))
            } else {
                level = .Debug
            }
        }
        log(message, level: level)
        return nil
    }
}

private let logger = XWVLogging(facility: "org.xwebview.xwebview")
func log(_ message: String, level: XWVLogging.Level? = nil) {
    logger.log(message, level: level)
}

func die(_ message: @autoclosure ()->String, file: StaticString = #file, line: UInt = #line) -> Never  {
    logger.log(message(), level: .Alert)
    fatalError(message, file: file, line: line)
}
