// swift-tools-version: 5.9
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let ortDylib = packageRoot
    .appendingPathComponent("Sources/xue_hua_navite_rapid_ocr/Vendor/libonnxruntime.dylib")
let hasOrt = FileManager.default.fileExists(atPath: ortDylib.path)

var resources: [Resource] = []
var linkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
]
if hasOrt {
    // Copied into framework Versions/A/Resources/ for RapidOCR dlopen.
    resources.append(.copy("Vendor/libonnxruntime.dylib"))
    linkerSettings.append(.unsafeFlags([
        "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
        "-Xlinker", "-rpath", "-Xlinker", "@loader_path/Resources",
        "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
    ], .when(platforms: [.macOS])))
}

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
    targets: [
        .target(
            name: "xue_hua_navite_rapid_ocr",
            path: "Sources/xue_hua_navite_rapid_ocr",
            // Only compile the forwarder; Vendor holds the ORT dylib resource.
            sources: ["xue_hua_navite_rapid_ocr_c_api.cpp"],
            resources: resources,
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("DART_SHARED_LIB"),
            ],
            linkerSettings: linkerSettings
        ),
    ],
    cxxLanguageStandard: .cxx17
)
