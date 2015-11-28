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

public typealias asl_object_t = COpaquePointer

@asmname("asl_open") func asl_open(ident: UnsafePointer<Int8>, _ facility: UnsafePointer<Int8>, _ opts: UInt32) -> asl_object_t;
@asmname("asl_close") func asl_close(obj: asl_object_t);
@asmname("asl_vlog") func asl_vlog(obj: asl_object_t, _ msg: asl_object_t, _ level: Int32, _ format: UnsafePointer<Int8>, _ ap: CVaListPointer) -> Int32;
@asmname("asl_add_output_file") func asl_add_output_file(client: asl_object_t, _ descriptor: Int32, _ msg_fmt: UnsafePointer<Int8>, _ time_fmt: UnsafePointer<Int8>, _ filter: Int32, _ text_encoding: Int32) -> Int32;
@asmname("asl_set_output_file_filter") func asl_set_output_file_filter(asl: asl_object_t, _ descriptor: Int32, _ filter: Int32) -> Int32;

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
        private init?(symbol: Character) {
            guard symbol != "\0", let value = Level.symbols.indexOf(symbol) else {
                return nil
            }
            self = Level(rawValue: Int32(value))!
        }
    }

    public struct Filter : OptionSetType {
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
            asl_set_output_file_filter(client, STDERR_FILENO, filter.rawValue)
        }
    }

    private let client: asl_object_t
    private var lock: pthread_mutex_t = pthread_mutex_t()
    public init(facility: String, format: String? = nil) {
        client = asl_open(nil, facility, 0)
        pthread_mutex_init(&lock, nil)

        #if DEBUG
        filter = Filter(upto: .Debug)
        #else
        filter = Filter(upto: .Notice)
        #endif

        let format = format ?? "$((Time)(lcl)) $(Facility) <$((Level)(char))>: $(Message)"
        asl_add_output_file(client, STDERR_FILENO, format, "sec", filter.rawValue, 1)
    }
    deinit {
        asl_close(client)
        pthread_mutex_destroy(&lock)
    }

    public func log(message: String, level: Level) {
        pthread_mutex_lock(&lock)
        asl_vlog(client, nil, level.rawValue, message, getVaList([]))
        pthread_mutex_unlock(&lock)
    }

    public func log(message: String, level: Level? = nil) {
        var msg = message
        var lvl = level ?? .Debug
        if level == nil, let ch = msg.characters.first, l = Level(symbol: ch) {
            msg = msg[msg.startIndex.successor() ..< msg.endIndex]
            lvl = l
        }
        log(msg, level: lvl)
    }

    @objc public func invokeDefaultMethodWithArguments(args: [AnyObject]!) -> AnyObject! {
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
func log(message: String, level: XWVLogging.Level? = nil) {
    logger.log(message, level: level)
}

@noreturn func die(@autoclosure message: ()->String, file: StaticString = __FILE__, line: UInt = __LINE__) {
    logger.log(message(), level: .Alert)
    fatalError(message, file: file, line: line)
}
