import 'dart:ui' show Offset, Size;

import 'package:flutter/painting.dart' show BoxFit, FittedSizes, applyBoxFit;

/// Coordinate space transformer mapping between normalized OCR image pixels
/// and the rendered `OcrLiveTextOverlay` layout box.
class OcrImageCoordinateTransform {
  const OcrImageCoordinateTransform({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });

  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  factory OcrImageCoordinateTransform.compute({
    required Size containerSize,
    required double imageWidth,
    required double imageHeight,
    required BoxFit fit,
  }) {
    final Size inputSize = Size(imageWidth, imageHeight);
    final FittedSizes fitted = applyBoxFit(fit, inputSize, containerSize);
    final double scaleX = inputSize.width > 0
        ? fitted.destination.width / inputSize.width
        : 1.0;
    final double scaleY = inputSize.height > 0
        ? fitted.destination.height / inputSize.height
        : 1.0;
    final double offsetX =
        (containerSize.width - fitted.destination.width) * 0.5;
    final double offsetY =
        (containerSize.height - fitted.destination.height) * 0.5;

    return OcrImageCoordinateTransform(
      scaleX: scaleX,
      scaleY: scaleY,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  /// Converts an OCR image coordinate [imagePoint] into widget local coordinate space.
  Offset imageToLocal(Offset imagePoint) {
    return Offset(
      offsetX + imagePoint.dx * scaleX,
      offsetY + imagePoint.dy * scaleY,
    );
  }

  /// Converts a widget local pointer coordinate [localPoint] into OCR image coordinate space.
  Offset localToImage(Offset localPoint) {
    return Offset(
      (localPoint.dx - offsetX) / (scaleX == 0 ? 1.0 : scaleX),
      (localPoint.dy - offsetY) / (scaleY == 0 ? 1.0 : scaleY),
    );
  }
}
