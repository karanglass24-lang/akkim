// swift-tools-version: 5.9
// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.
import PackageDescription

let package = Package(
    name: "akkim",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Akkim", targets: ["Akkim"]),
        // 실행 파일명은 앱/설치 스크립트가 기대하는 lowercase 이름으로 맞춥니다.
        .executable(name: "akkim-helper", targets: ["AkkimHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "Akkim",
            path: "Sources/Akkim",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("Combine"),
            ]
        ),
        .executableTarget(
            name: "AkkimHelper",
            path: "Sources/AkkimHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
