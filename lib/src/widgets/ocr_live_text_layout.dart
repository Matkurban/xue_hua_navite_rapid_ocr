import 'package:flutter/painting.dart' show Alignment, BoxFit, FilterQuality;

/// How [OcrLiveTextOverlay] inscribes the decoded bitmap and the highlights.
///
/// [fit], [alignment], and the bitmap's `ImageInfo.scale` are the only layout
/// inputs. There is no second mapping that ignores alignment or scale.
class OcrLiveTextLayout {
  const OcrLiveTextLayout({
    required this.fit,
    required this.alignment,
    this.filterQuality = FilterQuality.medium,
  });

  /// [BoxFit.contain] with [Alignment.center], matching [Image]'s own default.
  const OcrLiveTextLayout.contain({
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
  }) : fit = BoxFit.contain;

  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
}
