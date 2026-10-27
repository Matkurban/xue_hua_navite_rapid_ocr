import 'dart:ui' show Offset, Size;

/// Converts between EXIF-corrected OCR pixels and the bitmap a codec paints
/// when it does not itself apply orientation.
///
/// Native detection normalizes orientation tags `1..8` and reports
/// [OcrResult.imageWidth] / [OcrResult.imageHeight] in that corrected space.
/// Flutter's [Image] widget paints whatever the codec produced. When those
/// two sizes disagree by a 90-degree swap, corners are mapped back into the
/// un-oriented bitmap so highlights sit on the pixels actually on screen.
///
/// Continuous corner coordinates are used (pixel edges, not the `- 1` sample
/// index), so a corner round-trips exactly.
class OcrExifCoordinateMapper {
  const OcrExifCoordinateMapper._();

  /// Size of the bitmap before orientation tag [orientation] was applied.
  static Size rawSize({
    required int correctedWidth,
    required int correctedHeight,
    required int orientation,
  }) {
    final bool swap = orientation >= 5 && orientation <= 8;
    if (swap) {
      return Size(correctedHeight.toDouble(), correctedWidth.toDouble());
    }
    return Size(correctedWidth.toDouble(), correctedHeight.toDouble());
  }

  /// Maps a point in corrected OCR space back to pre-orientation pixels.
  static Offset correctedToRaw(
    Offset corrected, {
    required int correctedWidth,
    required int correctedHeight,
    required int orientation,
  }) {
    final double cw = correctedWidth.toDouble();
    final double ch = correctedHeight.toDouble();
    final double x = corrected.dx;
    final double y = corrected.dy;
    switch (orientation) {
      case 2:
        return Offset(cw - x, y);
      case 3:
        return Offset(cw - x, ch - y);
      case 4:
        return Offset(x, ch - y);
      case 5:
        return Offset(y, x);
      case 6:
        return Offset(y, cw - x);
      case 7:
        return Offset(ch - y, cw - x);
      case 8:
        return Offset(ch - y, x);
      default:
        return corrected;
    }
  }

  /// Forward map matching the native EXIF rotator (continuous coordinates).
  static Offset rawToCorrected(
    Offset raw, {
    required int rawWidth,
    required int rawHeight,
    required int orientation,
  }) {
    final double rw = rawWidth.toDouble();
    final double rh = rawHeight.toDouble();
    final double x = raw.dx;
    final double y = raw.dy;
    switch (orientation) {
      case 2:
        return Offset(rw - x, y);
      case 3:
        return Offset(rw - x, rh - y);
      case 4:
        return Offset(x, rh - y);
      case 5:
        return Offset(y, x);
      case 6:
        return Offset(rh - y, x);
      case 7:
        return Offset(rh - y, rw - x);
      case 8:
        return Offset(y, rw - x);
      default:
        return raw;
    }
  }
}

/// Pixel space of the bitmap [Image] is painting, plus a map from corrected
/// OCR corners into that space.
///
/// One policy, used for every frame:
/// * Before the image stream emits, corners stay in corrected OCR pixels.
/// * When the decoded bitmap still has the pre-orientation size (tags 2–8),
///   corners are inverse-mapped with [OcrExifCoordinateMapper].
/// * Otherwise each axis is scaled from corrected pixels into the decoded
///   bitmap, including a non-uniform stretch. The overlay then applies
///   `BoxFit` to that decoded size. It does not keep painting in OCR pixels
///   when the codec size disagrees.
class OcrDisplayedImageSpace {
  const OcrDisplayedImageSpace({
    required this.imageWidth,
    required this.imageHeight,
    required this.toDisplay,
  });

  final double imageWidth;
  final double imageHeight;

  /// Maps one corrected OCR pixel into the displayed bitmap's pixel space.
  final Offset Function(Offset correctedPoint) toDisplay;

  static OcrDisplayedImageSpace resolve({
    required int correctedWidth,
    required int correctedHeight,
    required int exifOrientation,
    Size? decodedPixelSize,
  }) {
    final double cw = correctedWidth <= 0 ? 1 : correctedWidth.toDouble();
    final double ch = correctedHeight <= 0 ? 1 : correctedHeight.toDouble();
    final Size corrected = Size(cw, ch);

    if (decodedPixelSize == null ||
        decodedPixelSize.width <= 0 ||
        decodedPixelSize.height <= 0) {
      return OcrDisplayedImageSpace(
        imageWidth: cw,
        imageHeight: ch,
        toDisplay: (Offset p) => p,
      );
    }

    final Size raw = OcrExifCoordinateMapper.rawSize(
      correctedWidth: correctedWidth,
      correctedHeight: correctedHeight,
      orientation: exifOrientation,
    );
    final bool decodedIsRaw =
        exifOrientation > 1 &&
        _nearSize(decodedPixelSize, raw) &&
        !_nearSize(decodedPixelSize, corrected);
    if (decodedIsRaw) {
      return OcrDisplayedImageSpace(
        imageWidth: decodedPixelSize.width,
        imageHeight: decodedPixelSize.height,
        toDisplay: (Offset p) => OcrExifCoordinateMapper.correctedToRaw(
          p,
          correctedWidth: correctedWidth,
          correctedHeight: correctedHeight,
          orientation: exifOrientation,
        ),
      );
    }

    return _scaled(from: corrected, to: decodedPixelSize);
  }

  static OcrDisplayedImageSpace _scaled({
    required Size from,
    required Size to,
  }) {
    final double sx = from.width == 0 ? 1 : to.width / from.width;
    final double sy = from.height == 0 ? 1 : to.height / from.height;
    return OcrDisplayedImageSpace(
      imageWidth: to.width,
      imageHeight: to.height,
      toDisplay: (Offset p) => Offset(p.dx * sx, p.dy * sy),
    );
  }

  static bool _nearSize(Size a, Size b) {
    return (a.width - b.width).abs() <= 1.5 &&
        (a.height - b.height).abs() <= 1.5;
  }
}
