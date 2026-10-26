import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

import '../utils/sample_image_generator.dart';
import '../widgets/engine_config_tab.dart';
import '../widgets/live_text_preview_tab.dart';
import '../widgets/markdown_json_tab.dart';
import '../widgets/paragraph_blocks_tab.dart';

/// Main interactive page demonstrating:
/// 1. Picking an image or capturing a camera photo via `xue_hua_file_operations` (`pickFile`, `capturePhoto`) and running OCR.
/// 2. Multilingual OCR switching (`OcrLanguage.chineseAndEnglish`, `japanese`, `korean`, `latin`, `cyrillic`, `arabic`, `multilingual`).
/// 3. Interactive `OcrLiveTextOverlay` with `OcrLiveTextStrings` i18n customization.
class OcrDemoHomePage extends StatefulWidget {
  const OcrDemoHomePage({super.key});

  @override
  State<OcrDemoHomePage> createState() => _OcrDemoHomePageState();
}

class _OcrDemoHomePageState extends State<OcrDemoHomePage> {
  final XueHuaNaviteRapidOcr _ocr = XueHuaNaviteRapidOcr();
  final XueHuaFileOperations _fileOps = XueHuaFileOperations.instance;
  final OcrLiveTextController _liveTextController = OcrLiveTextController();
  final ValueNotifier<String> _selectedOverlayTextNotifier =
      ValueNotifier<String>('');

  OcrLanguage _selectedLanguage = OcrLanguage.chineseAndEnglish;
  OcrExecutionProvider _selectedProvider = OcrExecutionProvider.auto;
  DemoOverlayLocale _selectedOverlayLocale = DemoOverlayLocale.zhCN;

  final int _maxSideLen = 960;
  double _boxThresh = 0.5;
  final double _boxScoreThresh = 0.6;
  double _unclipRatio = 1.6;
  double _minConfidence = 0.3;
  bool _doAngle = true;

  bool _isBusy = false;
  String _statusMessage = 'Initializing RapidOCR Engine...';
  String? _pickedFileName;
  Uint8List? _activeImageBytes;
  Uint8List? _sampleRawRgbaBytes;
  OcrResult? _ocrResult;

  @override
  void initState() {
    super.initState();
    _bootstrapDemo();
  }

  @override
  void dispose() {
    _selectedOverlayTextNotifier.dispose();
    _liveTextController.dispose();
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _bootstrapDemo() async {
    setState(() {
      _isBusy = true;
      _statusMessage =
          'Generating multilingual sample image & initializing engine...';
    });

    try {
      final ({Uint8List pngBytes, Uint8List rawRgbaBytes}) generated =
          await SampleImageGenerator.generateForLanguage(_selectedLanguage);
      _activeImageBytes = generated.pngBytes;
      _sampleRawRgbaBytes = generated.rawRgbaBytes;
      _pickedFileName = 'synthetic_${_selectedLanguage.name}.png';

      await _reinitializeEngine();
      await _runRecognizeBytes();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Initialization failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _reinitializeEngine() async {
    setState(() {
      _isBusy = true;
      _statusMessage =
          'Initializing (${_selectedLanguage.displayName}, EP: ${_selectedProvider.wireName})...';
    });

    await _ocr.initialize(
      OcrModelConfig.forLanguage(
        _selectedLanguage,
        executionProvider: _selectedProvider,
        numThreads: 4,
        enableHardwareAcceleration:
            _selectedProvider != OcrExecutionProvider.cpu,
        enableWebModelCache: true,
      ),
    );

    if (mounted) {
      setState(() {
        _isBusy = false;
        _statusMessage =
            'Engine Ready (${_selectedLanguage.modelPrefix}, EP: ${_selectedProvider.wireName})';
      });
    }
  }

  OcrRecognizeOptions get _currentOptions => OcrRecognizeOptions(
    maxSideLen: _maxSideLen,
    boxThresh: _boxThresh,
    boxScoreThresh: _boxScoreThresh,
    unclipRatio: _unclipRatio,
    doAngle: _doAngle,
    mostAngle: true,
    minConfidence: _minConfidence,
  );

  /// Uses `xue_hua_file_operations` (`^1.5.2`) to pick an image file across all 6 platforms
  /// (`withData: true` so bytes are available for both `OcrLiveTextOverlay` and `recognizeBytes`/`recognizeFile`)
  /// and immediately runs OCR recognition.
  Future<void> _pickImageAndRecognize() async {
    setState(() {
      _isBusy = true;
      _statusMessage =
          'Opening system image picker via xue_hua_file_operations...';
    });

    try {
      final PlatformFile? file = await _fileOps.pickFile(
        type: FileType.image,
        withData: true,
      );
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _isBusy = false;
          _statusMessage = 'Image selection cancelled.';
        });
        return;
      }

      setState(() {
        _pickedFileName = file.name;
        _statusMessage = 'Running OCR on picked image "${file.name}"...';
      });

      late final OcrResult result;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        _activeImageBytes = file.bytes;
        result = await _ocr.recognizeBytes(
          file.bytes!,
          options: _currentOptions,
        );
      } else if (file.path != null && file.path!.isNotEmpty) {
        result = await _ocr.recognizeFile(file.path!, options: _currentOptions);
      } else {
        throw const XueHuaOcrException(
          'Selected PlatformFile has neither bytes nor path.',
        );
      }

      if (mounted) {
        setState(() {
          _ocrResult = result;
          _statusMessage =
              'Recognized "${file.name}" in ${result.totalTimeMs.toStringAsFixed(1)} ms '
              '(${result.lines.length} lines, ${result.blocks.length} blocks, EXIF: ${result.exifOrientation})';
        });
      }
    } on FileOperationsException catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'FileOperationsException (${e.code.name}): ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Pick & Recognize error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _runRecognizeBytes() async {
    if (_activeImageBytes == null) return;
    setState(() {
      _isBusy = true;
      _statusMessage = 'Running recognizeBytes (Zero-Copy Buffer)...';
    });
    try {
      final OcrResult res = await _ocr.recognizeBytes(
        _activeImageBytes!,
        options: _currentOptions,
      );
      if (mounted) {
        setState(() {
          _ocrResult = res;
          _statusMessage =
              'recognizeBytes completed in ${res.totalTimeMs.toStringAsFixed(1)} ms '
              '(${res.lines.length} lines, ${res.blocks.length} blocks, EP: ${res.executionProviderUsed})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'recognizeBytes error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _runRecognizeRawPixels() async {
    if (_sampleRawRgbaBytes == null) return;
    setState(() {
      _isBusy = true;
      _statusMessage = 'Running recognizeRawPixels (RGBA8888 960×640)...';
    });
    try {
      final OcrResult res = await _ocr.recognizeRawPixels(
        pixels: _sampleRawRgbaBytes!,
        width: 960,
        height: 640,
        format: OcrPixelFormat.rgba8888,
        rowStride: 960 * 4,
        options: _currentOptions,
      );
      if (mounted) {
        setState(() {
          _ocrResult = res;
          _statusMessage =
              'recognizeRawPixels completed in ${res.totalTimeMs.toStringAsFixed(1)} ms '
              '(${res.lines.length} lines, ${res.blocks.length} blocks)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'recognizeRawPixels error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _switchLanguageAndRecognize(OcrLanguage language) async {
    setState(() {
      _selectedLanguage = language;
      _isBusy = true;
    });
    final ({Uint8List pngBytes, Uint8List rawRgbaBytes}) generated =
        await SampleImageGenerator.generateForLanguage(language);
    _activeImageBytes = generated.pngBytes;
    _sampleRawRgbaBytes = generated.rawRgbaBytes;
    _pickedFileName = 'synthetic_${language.name}.png';
    await _reinitializeEngine();
    await _runRecognizeBytes();
  }

  @override
  Widget build(BuildContext context) {
    final OcrResult? result = _ocrResult;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('XueHua Native RapidOCR (6-Platform)'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(
                icon: Icon(Icons.document_scanner_rounded),
                text: 'Live Text Overlay',
              ),
              Tab(
                icon: Icon(Icons.view_agenda_outlined),
                text: 'Paragraph Blocks',
              ),
              Tab(
                icon: Icon(Icons.description_outlined),
                text: 'Markdown & JSON',
              ),
              Tab(
                icon: Icon(Icons.translate_rounded),
                text: 'Multilingual & Config',
              ),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            // Top Control & Telemetry Banner
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (_isBusy)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          key: const ValueKey<String>('btn_pick_image_ocr'),
                          onPressed: _isBusy ? null : _pickImageAndRecognize,
                          icon: const Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 18,
                          ),
                          label: const Text('Pick Image & OCR'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>('btn_recognize_bytes'),
                          onPressed: _isBusy ? null : _runRecognizeBytes,
                          icon: const Icon(Icons.memory_rounded, size: 18),
                          label: const Text('recognizeBytes'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>(
                            'btn_recognize_raw_pixels',
                          ),
                          onPressed: _isBusy ? null : _runRecognizeRawPixels,
                          icon: const Icon(Icons.grid_on_rounded, size: 18),
                          label: const Text('recognizeRawPixels'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey<String>('btn_select_all_lines'),
                          onPressed: result == null
                              ? null
                              : () {
                                  _liveTextController.selectAll(
                                    result.lines.length,
                                  );
                                },
                          icon: const Icon(Icons.select_all_rounded, size: 18),
                          label: const Text('Select All Live Text'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey<String>('btn_toggle_boxes'),
                          onPressed: () =>
                              _liveTextController.toggleHighlightBoxes(),
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text('Toggle Highlights'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // Tab Views
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  LiveTextPreviewTab(
                    imageBytes: _activeImageBytes,
                    ocrResult: result,
                    controller: _liveTextController,
                    liveTextStrings: _selectedOverlayLocale.strings,
                    selectedOverlayTextListenable: _selectedOverlayTextNotifier,
                    onSelectionChanged:
                        (String selectedText, List<OcrTextLine> _) {
                          _selectedOverlayTextNotifier.value = selectedText;
                        },
                  ),
                  ParagraphBlocksTab(
                    ocrResult: result,
                    pickedFileName: _pickedFileName,
                  ),
                  MarkdownJsonTab(ocrResult: result),
                  EngineConfigTab(
                    selectedLanguage: _selectedLanguage,
                    selectedProvider: _selectedProvider,
                    selectedOverlayLocale: _selectedOverlayLocale,
                    doAngle: _doAngle,
                    boxThresh: _boxThresh,
                    unclipRatio: _unclipRatio,
                    minConfidence: _minConfidence,
                    onLanguageChanged: _switchLanguageAndRecognize,
                    onProviderChanged: (OcrExecutionProvider ep) {
                      setState(() => _selectedProvider = ep);
                      _reinitializeEngine();
                    },
                    onOverlayLocaleChanged: (DemoOverlayLocale loc) {
                      setState(() => _selectedOverlayLocale = loc);
                    },
                    onDoAngleChanged: (bool val) {
                      setState(() => _doAngle = val);
                      _runRecognizeBytes();
                    },
                    onBoxThreshChanged: (double v) =>
                        setState(() => _boxThresh = v),
                    onUnclipRatioChanged: (double v) =>
                        setState(() => _unclipRatio = v),
                    onMinConfidenceChanged: (double v) =>
                        setState(() => _minConfidence = v),
                    onThresholdChangeCommitted: _runRecognizeBytes,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
