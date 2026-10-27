#!/usr/bin/env dart
// Downloads ONNX Runtime + RapidOCR `.onnx` weights for the host developer
// machine (SHA-256 verified). Character dictionaries are NOT fetched here —
// apps download those at runtime via OcrDictionaryStore.
//
// Usage (from the plugin root or any app that depends on this package):
//   dart run xue_hua_navite_rapid_ocr:fetch_runtime
//   dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort
//   dart run xue_hua_navite_rapid_ocr:fetch_runtime --models --ppocrv5
//   dart run xue_hua_navite_rapid_ocr:fetch_runtime --build-native
//   dart run xue_hua_navite_rapid_ocr:fetch_runtime --embed-macos-app /path/App.app

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xue_hua_navite_rapid_ocr/src/runtime/ocr_runtime_assets.dart';

Future<void> main(List<String> args) async {
  final _Args parsed = _Args.parse(args);
  final Directory root = _findPackageRoot();
  stdout.writeln('Package root: ${root.path}');

  final http.Client client = http.Client();
  try {
    if (parsed.doOrt) {
      await _fetchOrt(root, client);
    }
    if (parsed.doModels) {
      await _fetchModels(root, client, includePpocrv5: parsed.ppocrv5);
    }
    if (parsed.buildNative) {
      await _buildNative(root);
    }
    if (parsed.embedMacosApp != null) {
      await _embedMacosOrt(root, Directory(parsed.embedMacosApp!));
    }
    if (!parsed.doOrt &&
        !parsed.doModels &&
        !parsed.buildNative &&
        parsed.embedMacosApp == null) {
      stderr.writeln('Nothing to do. Pass --ort, --models, --all, '
          '--build-native, and/or --embed-macos-app.');
      exitCode = 64;
    } else {
      stdout.writeln('Done.');
    }
  } finally {
    client.close();
  }
}

class _Args {
  _Args({
    required this.doOrt,
    required this.doModels,
    required this.ppocrv5,
    required this.buildNative,
    required this.embedMacosApp,
  });

  final bool doOrt;
  final bool doModels;
  final bool ppocrv5;
  final bool buildNative;
  final String? embedMacosApp;

  static _Args parse(List<String> args) {
    bool ort = false;
    bool models = false;
    bool all = false;
    bool ppocrv5 = true;
    bool buildNative = false;
    String? embed;
    for (int i = 0; i < args.length; i++) {
      final String a = args[i];
      if (a == '--ort' || a == '--ort-only') {
        ort = true;
      } else if (a == '--models' || a == '--models-only') {
        models = true;
      } else if (a == '--all') {
        all = true;
      } else if (a == '--ppocrv5') {
        ppocrv5 = true;
      } else if (a == '--no-ppocrv5') {
        ppocrv5 = false;
      } else if (a == '--build-native') {
        buildNative = true;
      } else if (a == '--embed-macos-app') {
        if (i + 1 >= args.length) {
          stderr.writeln('Missing path after --embed-macos-app');
          exit(64);
        }
        embed = args[++i];
      } else if (a == '-h' || a == '--help') {
        stdout.writeln(
          'fetch_runtime — download ONNX Runtime + RapidOCR ONNX weights\n'
          '  --all / --ort / --models / --ppocrv5 / --no-ppocrv5\n'
          '  --build-native / --embed-macos-app <App.app>',
        );
        exit(0);
      } else {
        stderr.writeln('Unknown argument: $a');
        exit(64);
      }
    }
    if (!ort && !models && !buildNative && embed == null) {
      all = true;
    }
    if (all) {
      ort = true;
      models = true;
    }
    return _Args(
      doOrt: ort,
      doModels: models,
      ppocrv5: ppocrv5,
      buildNative: buildNative,
      embedMacosApp: embed,
    );
  }
}

Directory _findPackageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 12; i++) {
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final String text = pubspec.readAsStringSync();
      if (text.contains(RegExp(r'^name:\s*xue_hua_navite_rapid_ocr\s*$', multiLine: true))) {
        return dir;
      }
      // Path dependency from example/: walk parents.
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  // Fallback: script location ../../ from bin/
  final String script = Platform.script.toFilePath();
  final Directory fromBin = Directory(p.normalize(p.join(p.dirname(script), '..')));
  final File pubspec = File(p.join(fromBin.path, 'pubspec.yaml'));
  if (pubspec.existsSync()) {
    return fromBin;
  }
  stderr.writeln('Could not locate xue_hua_navite_rapid_ocr package root.');
  throw StateError('Could not locate xue_hua_navite_rapid_ocr package root.');
}

Future<void> _fetchModels(
  Directory root,
  http.Client client, {
  required bool includePpocrv5,
}) async {
  final Directory dest = Directory(p.join(root.path, 'assets', 'models'));
  await dest.create(recursive: true);
  stdout.writeln('Fetching ONNX models -> ${dest.path}');
  final List<OcrOnnxModelAsset> assets = <OcrOnnxModelAsset>[
    ...kDefaultOnnxModelAssets,
    if (includePpocrv5) ...kOptionalPpocrv5OnnxModelAssets,
  ];
  for (final OcrOnnxModelAsset asset in assets) {
    await _downloadFile(
      client: client,
      url: asset.url,
      dest: File(p.join(dest.path, asset.fileName)),
      expectSha256: asset.sha256,
    );
  }
  // Remove legacy v3.4.0 filenames if present.
  const List<String> legacy = <String>[
    'ch_ppocr_mobile_v2.0_cls_infer.onnx',
    'ch_PP-OCRv4_det_infer.onnx',
    'ch_PP-OCRv4_rec_infer.onnx',
    'Multilingual_PP-OCRv3_det_infer.onnx',
    'en_PP-OCRv4_rec_infer.onnx',
    'japan_PP-OCRv4_rec_infer.onnx',
    'korean_PP-OCRv4_rec_infer.onnx',
    'latin_PP-OCRv3_rec_infer.onnx',
    'cyrillic_PP-OCRv3_rec_infer.onnx',
    'arabic_PP-OCRv4_rec_infer.onnx',
    'multilingual_PP-OCRv4_rec_infer.onnx',
  ];
  for (final String name in legacy) {
    final File f = File(p.join(dest.path, name));
    if (f.existsSync()) {
      stdout.writeln('RM legacy $name');
      f.deleteSync();
    }
  }
}

Future<void> _fetchOrt(Directory root, http.Client client) async {
  final OcrOrtHostArtifact? host = _hostOrtArtifact();
  if (host == null) {
    stderr.writeln(
      'Unsupported host ${Platform.operatingSystem}-${Platform.localHostname} '
      '(arch=${_unameM()}). Place ORT under third_party/onnxruntime/<platform>/ manually.',
    );
    exitCode = 1;
    return;
  }

  final Directory dest =
      Directory(p.join(root.path, 'third_party', 'onnxruntime', host.platformKey));
  await dest.create(recursive: true);
  final Directory work =
      Directory(p.join(root.path, 'third_party', '.onnxruntime-download'));
  await work.create(recursive: true);

  final File archive = File(p.join(work.path, host.assetName));
  await _downloadFile(
    client: client,
    url: host.url,
    dest: archive,
    expectSha256: host.sha256,
  );

  final Directory extract = Directory(p.join(work.path, 'extract-${host.platformKey}'));
  if (extract.existsSync()) {
    extract.deleteSync(recursive: true);
  }
  extract.createSync(recursive: true);
  await _extractArchive(archive, extract);

  final File? srcLib = _findPackedLib(extract, host.packedLibRelativePath);
  if (srcLib == null) {
    stderr.writeln('Missing ${host.packedLibRelativePath} inside ${host.assetName}');
    exit(1);
  }
  final File outLib = File(p.join(dest.path, host.outFileName));
  await srcLib.copy(outLib.path);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['+x', outLib.path]);
  }
  stdout.writeln('OK ${outLib.path}');

  if (Platform.isMacOS) {
    await _prepareMacosCopies(root, outLib);
    await _fetchIosXcframework(root, client, work);
  }
}

OcrOrtHostArtifact? _hostOrtArtifact() {
  final String os = Platform.operatingSystem;
  final String arch = _unameM();
  if (os == 'linux' && (arch == 'x86_64' || arch == 'amd64')) {
    return kOrtLinuxX64;
  }
  if (os == 'macos') {
    if (arch == 'arm64') return kOrtMacosArm64;
    if (arch == 'x86_64') return kOrtMacosX64;
  }
  if (os == 'windows') {
    return kOrtWinX64;
  }
  return null;
}

String _unameM() {
  if (Platform.isWindows) {
    return Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ??
        'x86_64';
  }
  final ProcessResult r = Process.runSync('uname', <String>['-m']);
  return (r.stdout as String).trim();
}

Future<void> _prepareMacosCopies(Directory root, File ortDylib) async {
  final File spmVendor = File(p.join(
    root.path,
    'macos',
    'xue_hua_navite_rapid_ocr',
    'Sources',
    'xue_hua_navite_rapid_ocr',
    'Vendor',
    'libonnxruntime.dylib',
  ));
  final File cocoa = File(
    p.join(root.path, 'macos', 'Libraries', 'libonnxruntime.dylib'),
  );
  spmVendor.parent.createSync(recursive: true);
  cocoa.parent.createSync(recursive: true);
  await ortDylib.copy(spmVendor.path);
  await ortDylib.copy(cocoa.path);
  await Process.run('install_name_tool', <String>[
    '-id',
    '@rpath/libonnxruntime.dylib',
    spmVendor.path,
  ]);
  await Process.run('install_name_tool', <String>[
    '-id',
    '@rpath/libonnxruntime.dylib',
    cocoa.path,
  ]);
  await Process.run('codesign', <String>['--force', '--sign', '-', spmVendor.path]);
  await Process.run('codesign', <String>['--force', '--sign', '-', cocoa.path]);
  stdout.writeln('Prepared SPM Vendor + CocoaPods Libraries copies');
}

Future<void> _fetchIosXcframework(
  Directory root,
  http.Client client,
  Directory work,
) async {
  final Directory iosDest =
      Directory(p.join(root.path, 'third_party', 'onnxruntime', 'ios'));
  final Directory xc = Directory(p.join(iosDest.path, 'onnxruntime.xcframework'));
  final File archive = File(
    p.join(work.path, 'pod-archive-onnxruntime-c-$kOnnxRuntimeIosVersion.zip'),
  );
  if (!xc.existsSync()) {
    await iosDest.create(recursive: true);
    await _downloadFile(
      client: client,
      url: kOrtIosPodArchiveUrl,
      dest: archive,
      expectSha256: null,
    );
    final Directory extract = Directory(p.join(work.path, 'extract-ios'));
    if (extract.existsSync()) {
      extract.deleteSync(recursive: true);
    }
    extract.createSync(recursive: true);
    await _extractArchive(archive, extract);
    final Directory found = Directory(
      p.join(extract.path, 'onnxruntime.xcframework'),
    );
    if (!found.existsSync()) {
      stderr.writeln('Missing onnxruntime.xcframework inside iOS pod archive');
      exit(1);
    }
    if (xc.existsSync()) {
      xc.deleteSync(recursive: true);
    }
    await _copyDirectory(found, xc);
    extract.deleteSync(recursive: true);
    stdout.writeln('OK ${xc.path}');
  } else {
    stdout.writeln('Using existing ${xc.path}');
  }

  final Directory frameworks =
      Directory(p.join(root.path, 'ios', 'Frameworks', 'onnxruntime.xcframework'));
  final Directory spmIos = Directory(p.join(
    root.path,
    'ios',
    'xue_hua_navite_rapid_ocr',
    'OnnxRuntime',
    'onnxruntime.xcframework',
  ));
  frameworks.parent.createSync(recursive: true);
  spmIos.parent.createSync(recursive: true);
  if (frameworks.existsSync()) {
    frameworks.deleteSync(recursive: true);
  }
  if (spmIos.existsSync()) {
    spmIos.deleteSync(recursive: true);
  }
  await _copyDirectory(xc, frameworks);
  await _copyDirectory(xc, spmIos);
  stdout.writeln('Prepared iOS Frameworks + SPM OnnxRuntime xcframework copies');
}

Future<void> _buildNative(Directory root) async {
  final Directory build = Directory(p.join(root.path, 'build', 'native'));
  await build.create(recursive: true);
  final bool hasCmake = (await Process.run('bash', <String>[
        '-lc',
        'command -v cmake',
      ]))
          .exitCode ==
      0;
  if (hasCmake) {
    final ProcessResult cfg = await Process.run(
      'cmake',
      <String>[
        '-S',
        p.join(root.path, 'src'),
        '-B',
        build.path,
        '-DCMAKE_BUILD_TYPE=Release',
      ],
    );
    stdout.write(cfg.stdout);
    stderr.write(cfg.stderr);
    if (cfg.exitCode != 0) {
      exit(cfg.exitCode);
    }
    final ProcessResult built = await Process.run(
      'cmake',
      <String>['--build', build.path, '--parallel'],
    );
    stdout.write(built.stdout);
    stderr.write(built.stderr);
    if (built.exitCode != 0) {
      exit(built.exitCode);
    }
  } else {
    stderr.writeln('cmake not found; building with system C++ compiler');
    if (Platform.isMacOS) {
      final String out =
          p.join(build.path, 'libxue_hua_navite_rapid_ocr.dylib');
      final ProcessResult r = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O2',
        '-fPIC',
        '-shared',
        '-o',
        out,
        p.join(root.path, 'src', 'xue_hua_navite_rapid_ocr_c_api.cpp'),
        '-I${p.join(root.path, 'src')}',
        '-install_name',
        '@rpath/libxue_hua_navite_rapid_ocr.dylib',
      ]);
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      if (r.exitCode != 0) exit(r.exitCode);
      stdout.writeln('Built $out');
    } else if (Platform.isLinux) {
      final String out = p.join(build.path, 'libxue_hua_navite_rapid_ocr.so');
      final ProcessResult r = await Process.run('c++', <String>[
        '-std=c++17',
        '-O2',
        '-fPIC',
        '-shared',
        '-o',
        out,
        p.join(root.path, 'src', 'xue_hua_navite_rapid_ocr_c_api.cpp'),
        '-I${p.join(root.path, 'src')}',
        '-ldl',
      ]);
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      if (r.exitCode != 0) exit(r.exitCode);
      stdout.writeln('Built $out');
    } else {
      stderr.writeln('No cmake and no compiler recipe for this OS. Install cmake.');
      exit(1);
    }
  }

  int copied = 0;
  final Directory ortRoot =
      Directory(p.join(root.path, 'third_party', 'onnxruntime'));
  if (ortRoot.existsSync()) {
    for (final FileSystemEntity entity in ortRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String name = p.basename(entity.path);
      if (name == 'libonnxruntime.so.1' ||
          name == 'libonnxruntime.dylib' ||
          name == 'onnxruntime.dll') {
        final File dest = File(p.join(build.path, name));
        await entity.copy(dest.path);
        if (Platform.isMacOS && name.endsWith('.dylib')) {
          await Process.run('install_name_tool', <String>[
            '-id',
            '@rpath/libonnxruntime.dylib',
            dest.path,
          ]);
          await Process.run(
            'codesign',
            <String>['--force', '--sign', '-', dest.path],
          );
        }
        copied++;
        stdout.writeln('Copied $name -> ${build.path}');
      }
    }
  }
  if (copied == 0) {
    stderr.writeln(
      'ONNX Runtime library not found under third_party/onnxruntime. '
      'Re-run with --ort before expecting real OCR text.',
    );
  }
}

Future<void> _embedMacosOrt(Directory root, Directory app) async {
  if (!app.existsSync()) {
    stderr.writeln('App bundle not found: ${app.path}');
    exit(1);
  }
  final List<String> candidates = <String>[
    p.join(
      root.path,
      'macos/xue_hua_navite_rapid_ocr/Sources/xue_hua_navite_rapid_ocr/Vendor/libonnxruntime.dylib',
    ),
    p.join(root.path, 'macos/Libraries/libonnxruntime.dylib'),
    p.join(root.path, 'third_party/onnxruntime/macos-arm64/libonnxruntime.dylib'),
    p.join(root.path, 'third_party/onnxruntime/macos-x64/libonnxruntime.dylib'),
  ];
  File? ort;
  for (final String c in candidates) {
    final File f = File(c);
    if (f.existsSync()) {
      ort = f;
      break;
    }
  }
  if (ort == null) {
    final Directory resources =
        Directory(p.join(app.path, 'Contents', 'Resources'));
    if (resources.existsSync()) {
      for (final FileSystemEntity e in resources.listSync(recursive: true)) {
        if (e is File && p.basename(e.path) == 'libonnxruntime.dylib') {
          ort = e;
          break;
        }
      }
    }
  }
  if (ort == null) {
    stderr.writeln(
      'ERROR: libonnxruntime.dylib not found (run: dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort)',
    );
    exit(1);
  }
  final Directory frameworks =
      Directory(p.join(app.path, 'Contents', 'Frameworks'));
  frameworks.createSync(recursive: true);
  final File dest = File(p.join(frameworks.path, 'libonnxruntime.dylib'));
  await ort.copy(dest.path);
  await Process.run('install_name_tool', <String>[
    '-id',
    '@rpath/libonnxruntime.dylib',
    dest.path,
  ]);
  await Process.run('codesign', <String>['--force', '--sign', '-', dest.path]);

  for (final FileSystemEntity e in frameworks.listSync(recursive: true)) {
    if (e is File && p.basename(e.path) == 'xue-hua-navite-rapid-ocr') {
      final File sibling =
          File(p.join(p.dirname(e.path), 'libonnxruntime.dylib'));
      await dest.copy(sibling.path);
      await Process.run(
        'codesign',
        <String>['--force', '--sign', '-', sibling.path],
      );
      break;
    }
  }
  stdout.writeln('Embedded ORT into ${dest.path}');
}

Future<void> _downloadFile({
  required http.Client client,
  required String url,
  required File dest,
  required String? expectSha256,
}) async {
  if (dest.existsSync() && dest.lengthSync() > 0) {
    if (expectSha256 != null) {
      final String got = await _sha256OfFile(dest);
      if (got == expectSha256) {
        stdout.writeln('SKIP ${p.basename(dest.path)} (sha256 ok)');
        return;
      }
      stdout.writeln('REGET ${p.basename(dest.path)} (sha256 mismatch)');
      dest.deleteSync();
    } else {
      stdout.writeln('SKIP ${p.basename(dest.path)}');
      return;
    }
  }

  stdout.writeln('GET ${p.basename(dest.path)}');
  dest.parent.createSync(recursive: true);
  final File tmp = File('${dest.path}.tmp');
  if (tmp.existsSync()) {
    tmp.deleteSync();
  }

  http.StreamedResponse? response;
  Object? lastError;
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      response = await client.send(req).timeout(const Duration(seconds: 120));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        break;
      }
      lastError = 'HTTP ${response.statusCode}';
      response = null;
    } catch (e) {
      lastError = e;
      response = null;
    }
    stderr.writeln('Retry $attempt for ${p.basename(dest.path)}: $lastError');
    await Future<void>.delayed(Duration(seconds: attempt));
  }
  if (response == null) {
    stderr.writeln('FAIL ${p.basename(dest.path)}: $lastError');
    exit(1);
  }

  final IOSink sink = tmp.openWrite();
  await response.stream.pipe(sink);
  await sink.close();

  if (expectSha256 != null) {
    final String got = await _sha256OfFile(tmp);
    if (got != expectSha256) {
      stderr.writeln(
        'SHA256 FAIL ${p.basename(dest.path)} expected=$expectSha256 got=$got',
      );
      tmp.deleteSync();
      exit(1);
    }
  } else {
    final String got = await _sha256OfFile(tmp);
    stdout.writeln('SHA256 (unpinned): $got');
  }

  if (dest.existsSync()) {
    dest.deleteSync();
  }
  tmp.renameSync(dest.path);
  stdout.writeln('OK ${p.basename(dest.path)}');
}

Future<String> _sha256OfFile(File file) async {
  final Digest digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<void> _extractArchive(File archive, Directory dest) async {
  final String path = archive.path;
  if (path.endsWith('.zip')) {
    final ProcessResult r = await Process.run(
      'unzip',
      <String>['-q', path, '-d', dest.path],
    );
    if (r.exitCode != 0) {
      stderr.write(r.stderr);
      // Fallback: PowerShell Expand-Archive on Windows
      if (Platform.isWindows) {
        final ProcessResult ps = await Process.run('powershell', <String>[
          '-NoProfile',
          '-Command',
          'Expand-Archive -Force -Path "${archive.path}" -DestinationPath "${dest.path}"',
        ]);
        if (ps.exitCode != 0) {
          stderr.write(ps.stderr);
          exit(ps.exitCode);
        }
        return;
      }
      exit(r.exitCode);
    }
    return;
  }
  final ProcessResult r = await Process.run(
    'tar',
    <String>['-xzf', path, '-C', dest.path],
  );
  if (r.exitCode != 0) {
    stderr.write(r.stderr);
    exit(r.exitCode);
  }
}

File? _findPackedLib(Directory extract, String packedRelative) {
  final String normalized = packedRelative.replaceAll('\\', '/');
  for (final FileSystemEntity e in extract.listSync(recursive: true)) {
    if (e is! File) continue;
    final String rel = p
        .relative(e.path, from: extract.path)
        .replaceAll('\\', '/');
    if (rel == normalized || rel.endsWith('/$normalized')) {
      return e;
    }
  }
  // Sometimes the tarball nests one top folder; match by basename path suffix.
  for (final FileSystemEntity e in extract.listSync(recursive: true)) {
    if (e is! File) continue;
    if (e.path.replaceAll('\\', '/').endsWith('/$normalized')) {
      return e;
    }
  }
  return null;
}

Future<void> _copyDirectory(Directory src, Directory dest) async {
  await dest.create(recursive: true);
  await for (final FileSystemEntity entity in src.list(recursive: false)) {
    final String name = p.basename(entity.path);
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(p.join(dest.path, name)));
    } else if (entity is File) {
      await entity.copy(p.join(dest.path, name));
    }
  }
}
