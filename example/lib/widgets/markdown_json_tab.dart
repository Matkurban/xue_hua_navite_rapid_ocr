import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Tab 3: Displays `OcrResult.toMarkdown()` and `OcrResult.toJson()` with copy actions.
class MarkdownJsonTab extends StatelessWidget {
  const MarkdownJsonTab({super.key, required this.ocrResult});

  final OcrResult? ocrResult;

  @override
  Widget build(BuildContext context) {
    final OcrResult? result = ocrResult;
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
}
