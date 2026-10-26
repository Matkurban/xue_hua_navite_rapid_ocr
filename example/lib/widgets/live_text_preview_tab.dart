import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Tab 1: Interactive `OcrLiveTextOverlay` preview with customizable i18n [OcrLiveTextStrings].
class LiveTextPreviewTab extends StatelessWidget {
  const LiveTextPreviewTab({
    super.key,
    required this.imageBytes,
    required this.ocrResult,
    required this.controller,
    required this.liveTextStrings,
    required this.selectedOverlayTextListenable,
    required this.onSelectionChanged,
  });

  final Uint8List? imageBytes;
  final OcrResult? ocrResult;
  final OcrLiveTextController controller;
  final OcrLiveTextStrings liveTextStrings;
  final ValueListenable<String> selectedOverlayTextListenable;
  final void Function(String selectedText, List<OcrTextLine> lines)
  onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = imageBytes;
    final OcrResult? result = ocrResult;
    if (bytes == null || result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: OcrLiveTextOverlay(
                  image: MemoryImage(bytes),
                  ocrResult: result,
                  controller: controller,
                  strings: liveTextStrings,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  onSelectionChanged: onSelectionChanged,
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
                            await Clipboard.setData(
                              ClipboardData(text: jsonStr),
                            );
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
        ),
        ValueListenableBuilder<String>(
          valueListenable: selectedOverlayTextListenable,
          builder: (BuildContext context, String selectedText, Widget? _) {
            if (selectedText.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(
                'Selected Text:\n$selectedText',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          },
        ),
      ],
    );
  }
}
