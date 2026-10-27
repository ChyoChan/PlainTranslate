// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "PlainTranslate",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "PlainTranslate", targets: ["PlainTranslate"])],
    targets: [
        .executableTarget(name: "PlainTranslate"),
        .testTarget(name: "PlainTranslateTests", dependencies: ["PlainTranslate"]),
    ],
    swiftLanguageVersions: [.v5]
)
