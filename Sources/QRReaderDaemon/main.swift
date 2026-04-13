import Cocoa
import Foundation

func baudConstant(_ baud: Int32) -> speed_t {
    switch baud {
    case 1200: return speed_t(B1200)
    case 2400: return speed_t(B2400)
    case 4800: return speed_t(B4800)
    case 9600: return speed_t(B9600)
    case 19200: return speed_t(B19200)
    case 38400: return speed_t(B38400)
    case 57600: return speed_t(B57600)
    case 115200: return speed_t(B115200)
    default: return speed_t(B9600)
    }
}

struct ReaderConfig {
    let baudRate: Int32
    let dataBits: Int
    let stopBits: Int
    let parity: Character
    let dedupeWindowSec: TimeInterval
    let lineEnding: String

    static func fromEnvironment() -> ReaderConfig {
        let env = ProcessInfo.processInfo.environment

        func intValue(_ key: String, _ fallback: Int32) -> Int32 {
            if let raw = env[key], let value = Int32(raw) {
                return value
            }
            return fallback
        }

        func intValueSwift(_ key: String, _ fallback: Int) -> Int {
            if let raw = env[key], let value = Int(raw) {
                return value
            }
            return fallback
        }

        func doubleValue(_ key: String, _ fallback: Double) -> Double {
            if let raw = env[key], let value = Double(raw) {
                return value
            }
            return fallback
        }

        let ending = env["QR_LINE_ENDING"] ?? "\\n"
        return ReaderConfig(
            baudRate: intValue("QR_BAUD", 9600),
            dataBits: intValueSwift("QR_DATABITS", 8),
            stopBits: intValueSwift("QR_STOPBITS", 1),
            parity: Character((env["QR_PARITY"] ?? "N").uppercased()),
            dedupeWindowSec: doubleValue("QR_DEDUPE_WINDOW_SEC", 0.35),
            lineEnding: ending
        )
    }
}

final class SerialReader {
    private let config: ReaderConfig
    private var fileDescriptor: Int32 = -1

    init(config: ReaderConfig) {
        self.config = config
    }

    func connect(path: String) throws {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw NSError(domain: "SerialReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed for \(path)"])
        }

        var options = termios()
        if tcgetattr(fd, &options) != 0 {
            close(fd)
            throw NSError(domain: "SerialReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "tcgetattr failed"])
        }

        cfmakeraw(&options)
        options.c_cflag |= (CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSIZE)

        switch config.dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        default: options.c_cflag |= tcflag_t(CS8)
        }

        if config.stopBits == 2 {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }

        switch config.parity {
        case "E":
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        case "O":
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag |= tcflag_t(PARODD)
        default:
            options.c_cflag &= ~tcflag_t(PARENB)
        }

        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        let speed = baudConstant(config.baudRate)
        _ = cfsetispeed(&options, speed)
        _ = cfsetospeed(&options, speed)

        if tcsetattr(fd, TCSANOW, &options) != 0 {
            close(fd)
            throw NSError(domain: "SerialReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "tcsetattr failed"])
        }

        if fcntl(fd, F_SETFL, 0) != 0 {
            close(fd)
            throw NSError(domain: "SerialReader", code: 4, userInfo: [NSLocalizedDescriptionKey: "fcntl failed"])
        }

        self.fileDescriptor = fd
    }

    func readChunk(maxBytes: Int = 1024) throws -> Data {
        guard fileDescriptor >= 0 else {
            return Data()
        }

        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let count = Darwin.read(fileDescriptor, &buffer, maxBytes)
        if count > 0 {
            return Data(buffer.prefix(count))
        }
        if count == 0 {
            return Data()
        }

        if errno == EAGAIN || errno == EWOULDBLOCK {
            return Data()
        }
        throw NSError(domain: "SerialReader", code: 5, userInfo: [NSLocalizedDescriptionKey: "read failed"])
    }

    func closePort() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        closePort()
    }
}

final class KeyboardInjector {
    private let source: CGEventSource?

    init() {
        self.source = CGEventSource(stateID: .combinedSessionState)
    }

    func inject(text: String) {
        guard !text.isEmpty else { return }
        for scalar in text.unicodeScalars {
            let value = UniChar(scalar.value)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            var mutable = value
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

final class DeviceScanner {
    static func findCandidates() -> [String] {
        let fm = FileManager.default
        let devPath = "/dev"
        guard let entries = try? fm.contentsOfDirectory(atPath: devPath) else {
            return []
        }

        let prefixes = ["cu.usb", "tty.usb", "cu.wchusbserial", "cu.SLAB_USBtoUART"]
        return entries
            .filter { name in prefixes.contains { name.hasPrefix($0) } }
            .map { "\(devPath)/\($0)" }
            .sorted()
    }
}

final class App {
    private let config = ReaderConfig.fromEnvironment()
    private let injector = KeyboardInjector()

    private var lastValue = ""
    private var lastInjectedAt = Date.distantPast

    func run() {
        print("[qr-reader] start, waiting serial device")
        while true {
            autoreleasepool {
                if let device = DeviceScanner.findCandidates().first {
                    runSession(device: device)
                } else {
                    Thread.sleep(forTimeInterval: 1.0)
                }
            }
        }
    }

    private func runSession(device: String) {
        let reader = SerialReader(config: config)
        do {
            try reader.connect(path: device)
            print("[qr-reader] connected: \(device)")

            var pending = Data()
            while true {
                let chunk = try reader.readChunk()
                if chunk.isEmpty {
                    Thread.sleep(forTimeInterval: 0.03)
                    continue
                }

                pending.append(chunk)
                while let range = pending.firstRange(of: Data([0x0A])) {
                    let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
                    pending.removeSubrange(pending.startIndex...range.lowerBound)

                    guard var raw = String(data: lineData, encoding: .utf8) else {
                        continue
                    }
                    raw = raw.replacingOccurrences(of: "\r", with: "")
                    let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !payload.isEmpty else { continue }

                    let now = Date()
                    if payload == lastValue && now.timeIntervalSince(lastInjectedAt) < config.dedupeWindowSec {
                        continue
                    }

                    let output = payload + config.lineEnding
                    injector.inject(text: output)
                    lastValue = payload
                    lastInjectedAt = now
                    print("[qr-reader] injected: \(payload)")
                }
            }
        } catch {
            print("[qr-reader] disconnected/error: \(error.localizedDescription)")
            reader.closePort()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
}

App().run()
