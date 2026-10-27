// swift-tools-version: 5.9
import PackageDescription

// ORT xcframework must already sit at OnnxRuntime/onnxruntime.xcframework
// (scripts/download_onnxruntime.sh). Flutter evaluates this from the resolved
// package path under ios/xue_hua_navite_rapid_ocr.
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
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            path: "OnnxRuntime/onnxruntime.xcframework"
        ),
        .target(
            name: "xue_hua_navite_rapid_ocr",
            dependencies: [
                "onnxruntime",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/xue_hua_navite_rapid_ocr",
            sources: ["xue_hua_navite_rapid_ocr_c_api.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("DART_SHARED_LIB"),
                .define("XUE_HUA_ORT_LINKED"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
