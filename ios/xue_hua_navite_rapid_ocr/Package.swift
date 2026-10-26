// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xue_hua_navite_rapid_ocr",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "xue-hua-navite-rapid-ocr",
            type: .dynamic,
            targets: ["xue_hua_navite_rapid_ocr"]
        ),
    ],
    targets: [
        .target(
            name: "xue_hua_navite_rapid_ocr",
            path: "Sources/xue_hua_navite_rapid_ocr",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("DART_SHARED_LIB"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
