import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart'
    show Alignment, BoxFit, FittedSizes, applyBoxFit;

/// Maps OCR image pixels onto the rectangle where [paintImage] draws them.
///
/// The mapping follows Flutter's `paintImage`: [applyBoxFit] runs in logical
/// pixels (`pixelSize / imageScale`), the source crop is converted back to
/// pixels, and both the source and destination rects are inscribed with
/// [alignment]. [BoxFit.cover], [BoxFit.fitWidth], and [BoxFit.fitHeight]
/// therefore crop the same pixels the [Image] widget crops, and letterboxing
/// for [BoxFit.contain] uses the same origin.
class OcrImageCoordinateTransform {
  const OcrImageCoordinateTransform({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
    required this.sourceRect,
    required this.destinationRect,
  });

  /// Horizontal scale from image pixels to local logical pixels.
  ///
  /// Together with [offsetX] this is `destination.left + (x - source.left) * scaleX`.
  final double scaleX;

  /// Vertical scale from image pixels to local logical pixels.
  final double scaleY;

  /// Local X of image X = 0 after the source-crop origin is applied.
  final double offsetX;

  /// Local Y of image Y = 0 after the source-crop origin is applied.
  final double offsetY;

  /// Pixel rect of the image that is visible (the [applyBoxFit] source).
  final Rect sourceRect;

  /// Local rect where those pixels are painted.
  final Rect destinationRect;

  factory OcrImageCoordinateTransform.compute({
    required Size containerSize,
    required double imageWidth,
    required double imageHeight,
    required BoxFit fit,
    Alignment alignment = Alignment.center,
    double imageScale = 1.0,
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
      return OcrImageCoordinateTransform(
        scaleX: 1,
        scaleY: 1,
        offsetX: 0,
        offsetY: 0,
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

    final double scaleX = sourceRect.width > 0
        ? destinationRect.width / sourceRect.width
        : 1.0;
    final double scaleY = sourceRect.height > 0
        ? destinationRect.height / sourceRect.height
        : 1.0;

    return OcrImageCoordinateTransform(
      scaleX: scaleX,
      scaleY: scaleY,
      offsetX: destinationRect.left - sourceRect.left * scaleX,
      offsetY: destinationRect.top - sourceRect.top * scaleY,
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
