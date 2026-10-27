import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart'
    show Alignment, BoxFit, FittedSizes, applyBoxFit;

/// Maps OCR image pixels onto the rectangle where `paintImage` draws them.
///
/// The mapping is only [applyBoxFit] plus [Alignment] plus the image scale:
/// [applyBoxFit] runs in logical pixels (`pixelSize / imageScale`), the source
/// crop is converted back to pixels, and both rects are inscribed with
/// [alignment]. [scaleX], [scaleY], [offsetX], and [offsetY] are derived from
/// those rects. They are not a second coordinate system.
class OcrImageCoordinateTransform {
  const OcrImageCoordinateTransform._({
    required this.sourceRect,
    required this.destinationRect,
  });

  /// Pixel rect of the image that is visible (the [applyBoxFit] source).
  final Rect sourceRect;

  /// Local rect where those pixels are painted.
  final Rect destinationRect;

  /// Horizontal scale from image pixels to local logical pixels.
  double get scaleX =>
      sourceRect.width == 0 ? 1 : destinationRect.width / sourceRect.width;

  /// Vertical scale from image pixels to local logical pixels.
  double get scaleY =>
      sourceRect.height == 0 ? 1 : destinationRect.height / sourceRect.height;

  /// Local X of image X = 0 after the source-crop origin is applied.
  double get offsetX => destinationRect.left - sourceRect.left * scaleX;

  /// Local Y of image Y = 0 after the source-crop origin is applied.
  double get offsetY => destinationRect.top - sourceRect.top * scaleY;

  factory OcrImageCoordinateTransform.compute({
    required Size containerSize,
    required double imageWidth,
    required double imageHeight,
    required BoxFit fit,
    required Alignment alignment,
    required double imageScale,
  }) {
    final double pixelW = imageWidth.isFinite ? imageWidth : 0;
    final double pixelH = imageHeight.isFinite ? imageHeight : 0;
    final double safeScale = imageScale.isFinite && imageScale > 0
        ? imageScale
        : 1.0;
    if (pixelW <= 0 ||
        pixelH <= 0 ||
        containerSize.width <= 0 ||
        containerSize.height <= 0) {
      return OcrImageCoordinateTransform._(
        sourceRect: Rect.fromLTWH(0, 0, pixelW, pixelH),
        destinationRect: Rect.fromLTWH(
          0,
          0,
          containerSize.width,
          containerSize.height,
        ),
      );
    }

    final Size inputPixels = Size(pixelW, pixelH);
    final Size inputLogical = inputPixels / safeScale;
    final FittedSizes fitted = applyBoxFit(fit, inputLogical, containerSize);
    final Size sourcePixels = fitted.source * safeScale;
    final Rect sourceRect = alignment.inscribe(
      sourcePixels,
      Offset.zero & inputPixels,
    );
    final Rect destinationRect = alignment.inscribe(
      fitted.destination,
      Offset.zero & containerSize,
    );
    return OcrImageCoordinateTransform._(
      sourceRect: sourceRect,
      destinationRect: destinationRect,
    );
  }

  /// Converts an OCR image coordinate [imagePoint] into widget local coordinates.
  Offset imageToLocal(Offset imagePoint) {
    return Offset(
      offsetX + imagePoint.dx * scaleX,
      offsetY + imagePoint.dy * scaleY,
    );
  }

  /// Converts a widget local pointer coordinate [localPoint] into image pixels.
  Offset localToImage(Offset localPoint) {
    final double sx = scaleX == 0 ? 1.0 : scaleX;
    final double sy = scaleY == 0 ? 1.0 : scaleY;
    return Offset(
      (localPoint.dx - offsetX) / sx,
      (localPoint.dy - offsetY) / sy,
    );
  }

  /// Whether [imagePoint] lies inside the visible source crop.
  bool containsImagePoint(Offset imagePoint) => sourceRect.contains(imagePoint);
}
