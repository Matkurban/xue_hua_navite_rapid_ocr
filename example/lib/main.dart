import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XueHuaRapidOcrExampleApp());
}

class XueHuaRapidOcrExampleApp extends StatelessWidget {
  const XueHuaRapidOcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XueHua Native RapidOCR Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42A5F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const OcrDemoHomePage(),
    );
  }
}

class OcrDemoHomePage extends StatefulWidget {
  const OcrDemoHomePage({super.key});

  @override
  State<OcrDemoHomePage> createState() => _OcrDemoHomePageState();
}

class _OcrDemoHomePageState extends State<OcrDemoHomePage> {
  final XueHuaNaviteRapidOcr _ocr = XueHuaNaviteRapidOcr();
  final OcrLiveTextController _liveTextController = OcrLiveTextController();

  OcrLanguage _selectedLanguage = OcrLanguage.chineseAndEnglish;
  OcrExecutionProvider _selectedProvider = OcrExecutionProvider.auto;
  int _maxSideLen = 960;
  double _boxThresh = 0.5;
  double _boxScoreThresh = 0.6;
  double _unclipRatio = 1.6;
  double _minConfidence = 0.3;
  bool _doAngle = true;

  bool _isBusy = false;
  String _statusMessage = 'Initializing RapidOCR Engine...';
  Uint8List? _samplePngBytes;
  Uint8List? _sampleRawRgbaBytes;
  OcrResult? _ocrResult;
  String _selectedOverlayText = '';

  @override
  void initState() {
    super.initState();
    _bootstrapDemo();
  }

  @override
  void dispose() {
    _liveTextController.dispose();
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _bootstrapDemo() async {
    setState(() {
      _isBusy = true;
      _statusMessage =
          'Generating sample invoice image & initializing engine...';
    });

    try {
      await _generateSyntheticSampleImage();
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

  /// Generates a synthetic 960x640 document canvas with tilted & horizontal text lines
  /// so the demo runs offline across all 6 platforms without external file dependencies.
  Future<void> _generateSyntheticSampleImage() async {
    const int width = 960;
    const int height = 640;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Paper card background
    final Paint bgPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    final Paint cardBorder = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 24, width - 48, height - 48),
        const Radius.circular(16),
      ),
      cardBorder,
    );

    void drawDocLine(
      String text,
      Offset pos, {
      double fontSize = 26,
      FontWeight weight = FontWeight.w600,
      Color color = const Color(0xFF0F172A),
      double tiltDeg = 0.0,
    }) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      if (tiltDeg != 0.0) {
        canvas.rotate(tiltDeg * math.pi / 180.0);
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 96);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    drawDocLine(
      'XueHua Native RapidOCR v1.0.0',
      const Offset(58, 52),
      fontSize: 30,
      weight: FontWeight.w800,
      color: const Color(0xFF1E3A8A),
    );
    drawDocLine(
      'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline',
      const Offset(58, 108),
      fontSize: 24,
      color: const Color(0xFF334155),
    );
    drawDocLine(
      '零拷贝 FFI Worker Isolate + WebGPU/WASM 六端统一推理',
      const Offset(58, 205),
      fontSize: 25,
      color: const Color(0xFF0F766E),
      tiltDeg: -1.5,
    );
    drawDocLine(
      '支持 DBNet 多边形检测、AngleNet 方向校正与 CTC 解码',
      const Offset(58, 262),
      fontSize: 25,
      color: const Color(0xFF0F766E),
      tiltDeg: -1.5,
    );
    drawDocLine(
      'Invoice #INV-2026-0892   Date: 2026-10-26',
      const Offset(76, 396),
      fontSize: 24,
      color: const Color(0xFF1E293B),
    );
    drawDocLine(
      'Total Amount: \$1,280.00 USD (Paid Offline)',
      const Offset(76, 454),
      fontSize: 24,
      weight: FontWeight.w700,
      color: const Color(0xFFB91C1C),
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(width, height);
    final ByteData? pngData = await img.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final ByteData? rawRgbaData = await img.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    if (pngData != null) {
      _samplePngBytes = pngData.buffer.asUint8List();
    }
    if (rawRgbaData != null) {
      _sampleRawRgbaBytes = rawRgbaData.buffer.asUint8List();
    }
  }

  Future<void> _reinitializeEngine() async {
    setState(() {
      _isBusy = true;
      _statusMessage =
          'Initializing (${_selectedLanguage.displayName}, EP: ${_selectedProvider.wireName})...';
    });

    await _ocr.initialize(
      OcrModelConfig(
        language: _selectedLanguage,
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

  Future<void> _runRecognizeBytes() async {
    if (_samplePngBytes == null) return;
    setState(() {
      _isBusy = true;
      _statusMessage = 'Running recognizeBytes (Zero-Copy PNG Buffer)...';
    });
    try {
      final OcrResult res = await _ocr.recognizeBytes(
        _samplePngBytes!,
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
      _statusMessage = 'Running recognizeRawPixels (RGBA8888 960x640)...';
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
              Tab(icon: Icon(Icons.tune_rounded), text: 'Engine & Options'),
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
                          key: const ValueKey<String>('btn_recognize_bytes'),
                          onPressed: _isBusy ? null : _runRecognizeBytes,
                          icon: const Icon(Icons.memory_rounded, size: 18),
                          label: const Text('recognizeBytes (PNG)'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>(
                            'btn_recognize_raw_pixels',
                          ),
                          onPressed: _isBusy ? null : _runRecognizeRawPixels,
                          icon: const Icon(Icons.grid_on_rounded, size: 18),
                          label: const Text('recognizeRawPixels (RGBA8888)'),
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
                  _buildLiveTextTab(context, result),
                  _buildBlocksTab(context, result),
                  _buildMarkdownAndJsonTab(context, result),
                  _buildEngineConfigTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTextTab(BuildContext context, OcrResult? result) {
    if (_samplePngBytes == null || result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: OcrLiveTextOverlay(
                image: MemoryImage(_samplePngBytes!),
                ocrResult: result,
                controller: _liveTextController,
                onSelectionChanged:
                    (String selectedText, List<OcrTextLine> lines) {
                      setState(() {
                        _selectedOverlayText = selectedText;
                      });
                    },
                customActions: <OcrLiveTextCustomAction>[
                  OcrLiveTextCustomAction(
                    label: 'JSON',
                    icon: Icons.data_object_rounded,
                    onPressed:
                        (String text, List<OcrTextLine> selectedLines) async {
                          final String jsonStr =
                              const JsonEncoder.withIndent('  ').convert(
                                selectedLines
                                    .map((OcrTextLine l) => l.toJson())
                                    .toList(),
                              );
                          await Clipboard.setData(ClipboardData(text: jsonStr));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied selected lines JSON!'),
                              ),
                            );
                          }
                        },
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectedOverlayText.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(
              'Selected Text:\n$_selectedOverlayText',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _buildBlocksTab(BuildContext context, OcrResult? result) {
    if (result == null) {
      return const Center(child: Text('No OCR result yet.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: <Widget>[
                _metricItem(
                  'Image Size',
                  '${result.imageWidth}×${result.imageHeight}',
                ),
                _metricItem('EXIF Orientation', '${result.exifOrientation}'),
                _metricItem('Execution Provider', result.executionProviderUsed),
                _metricItem(
                  'Total Time',
                  '${result.totalTimeMs.toStringAsFixed(2)} ms',
                ),
                _metricItem(
                  'Preprocess',
                  '${result.preprocessTimeMs.toStringAsFixed(2)} ms',
                ),
                _metricItem(
                  'DBNet Det',
                  '${result.detTimeMs.toStringAsFixed(2)} ms',
                ),
                _metricItem(
                  'AngleNet Cls',
                  '${result.clsTimeMs.toStringAsFixed(2)} ms',
                ),
                _metricItem(
                  'CrnnNet Rec',
                  '${result.recTimeMs.toStringAsFixed(2)} ms',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Clustered Paragraph Blocks (${result.blocks.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < result.blocks.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(child: Text('B${i + 1}')),
              title: SelectableText(result.blocks[i].text),
              subtitle: Text(
                'Lines: ${result.blocks[i].lines.length} • '
                'Avg Confidence: ${(result.blocks[i].averageConfidence * 100).toStringAsFixed(1)}% • '
                'Bounds: (${result.blocks[i].boundingBox.left.toStringAsFixed(0)}, '
                '${result.blocks[i].boundingBox.top.toStringAsFixed(0)}, '
                '${result.blocks[i].boundingBox.width.toStringAsFixed(0)}×'
                '${result.blocks[i].boundingBox.height.toStringAsFixed(0)})',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.blocks[i].text));
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMarkdownAndJsonTab(BuildContext context, OcrResult? result) {
    if (result == null) {
      return const Center(child: Text('No OCR result yet.'));
    }
    final String md = result.toMarkdown();
    final String jsonStr = const JsonEncoder.withIndent('  ')
        .convert(result.toJson());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Structured Markdown Output (toMarkdown)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Markdown'),
              onPressed: () => Clipboard.setData(ClipboardData(text: md)),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              md,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Serialized JSON Output (toJson)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy JSON'),
              onPressed: () => Clipboard.setData(ClipboardData(text: jsonStr)),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEngineConfigTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Model & Hardware Acceleration (OcrModelConfig)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<OcrLanguage>(
          initialValue: _selectedLanguage,
          decoration: const InputDecoration(
            labelText: 'OCR Recognition Language',
            border: OutlineInputBorder(),
          ),
          items: OcrLanguage.values
              .map(
                (OcrLanguage lang) => DropdownMenuItem<OcrLanguage>(
                  value: lang,
                  child: Text(lang.displayName),
                ),
              )
              .toList(),
          onChanged: (OcrLanguage? val) {
            if (val != null) {
              setState(() => _selectedLanguage = val);
              _reinitializeEngine();
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<OcrExecutionProvider>(
          initialValue: _selectedProvider,
          decoration: const InputDecoration(
            labelText: 'Execution Provider (Hardware Acceleration)',
            border: OutlineInputBorder(),
          ),
          items: OcrExecutionProvider.values
              .map(
                (OcrExecutionProvider ep) =>
                    DropdownMenuItem<OcrExecutionProvider>(
                      value: ep,
                      child: Text('${ep.name} (${ep.wireName})'),
                    ),
              )
              .toList(),
          onChanged: (OcrExecutionProvider? val) {
            if (val != null) {
              setState(() => _selectedProvider = val);
              _reinitializeEngine();
            }
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Detection & Recognition Thresholds (OcrRecognizeOptions)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SwitchListTile(
          title: const Text(
            'Enable 180° / Tilt Angle Classification (doAngle)',
          ),
          value: _doAngle,
          onChanged: (bool val) {
            setState(() => _doAngle = val);
            _runRecognizeBytes();
          },
        ),
        _buildSliderRow(
          label:
              'DBNet Box Threshold (boxThresh): ${_boxThresh.toStringAsFixed(2)}',
          value: _boxThresh,
          min: 0.1,
          max: 0.9,
          onChanged: (double v) => setState(() => _boxThresh = v),
        ),
        _buildSliderRow(
          label:
              'Polygon Unclip Ratio (unclipRatio): ${_unclipRatio.toStringAsFixed(2)}',
          value: _unclipRatio,
          min: 1.0,
          max: 2.5,
          onChanged: (double v) => setState(() => _unclipRatio = v),
        ),
        _buildSliderRow(
          label:
              'Min Confidence Filter (minConfidence): ${_minConfidence.toStringAsFixed(2)}',
          value: _minConfidence,
          min: 0.0,
          max: 0.95,
          onChanged: (double v) => setState(() => _minConfidence = v),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: (_) => _runRecognizeBytes(),
        ),
      ],
    );
  }

  Widget _metricItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
