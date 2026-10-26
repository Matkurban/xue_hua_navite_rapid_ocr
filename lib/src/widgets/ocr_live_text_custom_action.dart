import 'package:flutter/widgets.dart' show IconData;

import '../models/ocr_text_line.dart';

/// Custom action item displayed inside the `OcrLiveTextOverlay` floating selection toolbar.
class OcrLiveTextCustomAction {
  const OcrLiveTextCustomAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  /// Button label shown in the floating selection bar.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Callback invoked with the currently selected text and selected [OcrTextLine]s.
  final void Function(String selectedText, List<OcrTextLine> selectedLines)
  onPressed;
}
