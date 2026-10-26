import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Tab 2: Displays pipeline telemetry metrics and spatially clustered [OcrTextBlock]s.
class ParagraphBlocksTab extends StatelessWidget {
  const ParagraphBlocksTab({
    super.key,
    required this.ocrResult,
    this.pickedFileName,
  });

  final OcrResult? ocrResult;
  final String? pickedFileName;

  @override
  Widget build(BuildContext context) {
    final OcrResult? result = ocrResult;
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
                if (pickedFileName != null)
                  _metricItem('Source File', pickedFileName!),
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

  Widget _metricItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
