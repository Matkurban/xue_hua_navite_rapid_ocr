// swift-tools-version: 5.9
import PackageDescription

// ORT must already sit at Sources/.../Vendor/libonnxruntime.dylib
// (dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort). Do not gate on #filePath — Flutter
// evaluates this manifest from a resolved copy where that check is false.
let package = Package(
    name: "xue_hua_navite_rapid_ocr",
    platforms: [
        .macOS(.v11),
        .iOS(.v15),
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
        .target(
            name: "xue_hua_navite_rapid_ocr",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/xue_hua_navite_rapid_ocr",
            sources: ["xue_hua_navite_rapid_ocr_c_api.cpp"],
            resources: [
                .copy("Vendor/libonnxruntime.dylib"),
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("DART_SHARED_LIB"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .unsafeFlags([
                    // Flutter already adds @loader_path; only extend for Vendor dylib + Frameworks.
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/Resources",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
                ], .when(platforms: [.macOS])),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
