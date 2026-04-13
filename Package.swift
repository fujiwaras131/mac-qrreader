// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QRReaderDaemon",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "qr-reader-daemon", targets: ["QRReaderDaemon"])
    ],
    targets: [
        .executableTarget(
            name: "QRReaderDaemon",
            path: "Sources/QRReaderDaemon"
        )
    ]
)
