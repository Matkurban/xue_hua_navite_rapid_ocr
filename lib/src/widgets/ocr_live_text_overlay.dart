import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ocr_models.dart';

/// Custom action item displayed inside the [OcrLiveTextOverlay] floating selection toolbar.
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

/// Controller for programmatically interacting with an [OcrLiveTextOverlay].
class OcrLiveTextController extends ChangeNotifier {
  final Set<int> _selectedIndices = <int>{};
  bool _showHighlightBoxes = true;

  /// Set of currently selected [OcrTextLine] indices.
  Set<int> get selectedIndices => Set<int>.unmodifiable(_selectedIndices);

  /// Whether all recognized text highlight boxes are currently visible.
  bool get showHighlightBoxes => _showHighlightBoxes;

  /// Toggles the visibility of all recognized text highlight boxes.
  void toggleHighlightBoxes([bool? visible]) {
    final bool next = visible ?? !_showHighlightBoxes;
    if (_showHighlightBoxes != next) {
      _showHighlightBoxes = next;
      notifyListeners();
    }
  }

  /// Selects all lines `[0 .. totalLines - 1]`.
  void selectAll(int totalLines) {
    _selectedIndices
      ..clear()
      ..addAll(List<int>.generate(totalLines, (int i) => i));
    notifyListeners();
  }

  /// Clears the current selection.
  void clearSelection() {
    if (_selectedIndices.isNotEmpty) {
      _selectedIndices.clear();
      notifyListeners();
    }
  }

  /// Replaces the current selection with [indices].
  void setSelection(Iterable<int> indices) {
    _selectedIndices
      ..clear()
      ..addAll(indices);
    notifyListeners();
  }
}

/// Interactive 6-platform "Live Text" overlay widget (`OcrLiveTextOverlay`).
///
/// Renders the source [image] alongside rotated quadrilateral highlights for every
/// [OcrTextLine] in [ocrResult], supporting:
/// - Single tap on a text box to select/deselect or immediately copy.
/// - Touch drag or mouse marquee/lasso drag selection across multiple rotated text lines.
/// - Automatic `SystemMouseCursors.text` cursor when hovering over any recognized text polygon on Desktop/Web.
/// - Floating contextual action bar with "Copy", "Select All", "Clear", and custom actions.
/// - Smooth animated toggle to show/hide all text highlight boxes.
class OcrLiveTextOverlay extends StatefulWidget {
  const OcrLiveTextOverlay({
    super.key,
    required this.image,
    required this.ocrResult,
    this.controller,
    this.fit = BoxFit.contain,
    this.initialShowHighlights = true,
    this.showFloatingToolbar = true,
    this.showToggleHighlightsButton = true,
    this.copyOnSingleTap = false,
    this.highlightFillColor = const Color(0x282196F3),
    this.highlightBorderColor = const Color(0x992196F3),
    this.selectedFillColor = const Color(0x4D1976D2),
    this.selectedBorderColor = const Color(0xFF1565C0),
    this.hoveredFillColor = const Color(0x3842A5F5),
    this.marqueeFillColor = const Color(0x261E88E5),
    this.marqueeBorderColor = const Color(0xCC1E88E5),
    this.onSelectionChanged,
    this.onTextCopied,
    this.customActions = const <OcrLiveTextCustomAction>[],
  });

  /// Original image provider (e.g., `MemoryImage`, `FileImage`, `NetworkImage`, `AssetImage`).
  final ImageProvider image;

  /// OCR recognition result containing [OcrTextLine]s and [OcrResult.imageWidth] / [OcrResult.imageHeight].
  final OcrResult ocrResult;

  /// Optional external controller for programmatic selection and highlight toggling.
  final OcrLiveTextController? controller;

  /// How the image and OCR coordinate space should be inscribed into the layout box.
  final BoxFit fit;

  /// Whether highlight boxes are initially visible when [controller] is not provided.
  final bool initialShowHighlights;

  /// Whether to display the floating action toolbar when one or more text lines are selected.
  final bool showFloatingToolbar;

  /// Whether to render the corner Live Text badge button that toggles highlight visibility.
  final bool showToggleHighlightsButton;

  /// If `true`, tapping a single text box immediately copies its text to the system clipboard.
  final bool copyOnSingleTap;

  /// Unselected text box fill color.
  final Color highlightFillColor;

  /// Unselected text box border color.
  final Color highlightBorderColor;

  /// Selected text box fill color.
  final Color selectedFillColor;

  /// Selected text box border color.
  final Color selectedBorderColor;

  /// Hovered text box fill color on Desktop & Web.
  final Color hoveredFillColor;

  /// Drag selection rectangle/lasso fill color.
  final Color marqueeFillColor;

  /// Drag selection rectangle/lasso border color.
  final Color marqueeBorderColor;

  /// Callback fired whenever the selected lines change.
  final void Function(String selectedText, List<OcrTextLine> selectedLines)?
  onSelectionChanged;

  /// Callback fired when selected text is copied to the clipboard.
  final void Function(String copiedText)? onTextCopied;

  /// Additional custom action buttons shown in the floating selection toolbar.
  final List<OcrLiveTextCustomAction> customActions;

  @override
  State<OcrLiveTextOverlay> createState() => _OcrLiveTextOverlayState();
}

class _OcrLiveTextOverlayState extends State<OcrLiveTextOverlay>
    with SingleTickerProviderStateMixin {
  late OcrLiveTextController _controller;
  bool _ownsController = false;
  late AnimationController _fadeController;

  int? _hoveredLineIndex;
  Offset? _dragStartLocal;
  Offset? _dragCurrentLocal;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = OcrLiveTextController()
        ..toggleHighlightBoxes(widget.initialShowHighlights);
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _controller.showHighlightBoxes ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant OcrLiveTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = OcrLiveTextController()
          ..toggleHighlightBoxes(widget.initialShowHighlights);
        _ownsController = true;
      }
      _controller.addListener(_onControllerChanged);
    }
    if (oldWidget.ocrResult != widget.ocrResult) {
      _controller.clearSelection();
      _hoveredLineIndex = null;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_controller.showHighlightBoxes) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }
    if (mounted) {
      setState(() {});
    }
  }

  List<OcrTextLine> get _selectedLines {
    final List<int> sortedIdx = _controller.selectedIndices.toList()..sort();
    return sortedIdx
        .where((int idx) => idx >= 0 && idx < widget.ocrResult.lines.length)
        .map((int idx) => widget.ocrResult.lines[idx])
        .toList(growable: false);
  }

  String get _selectedText =>
      _selectedLines.map((OcrTextLine l) => l.text).join('\n');

  void _notifySelectionChanged() {
    widget.onSelectionChanged?.call(_selectedText, _selectedLines);
  }

  Future<void> _copySelectedText() async {
    final String text = _selectedText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    widget.onTextCopied?.call(text);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Copied ${_selectedLines.length} line(s) to clipboard'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size containerSize = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 640,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 480,
        );
        final _ImageCoordinateTransform transform =
            _ImageCoordinateTransform.compute(
              containerSize: containerSize,
              imageWidth: math.max(1, widget.ocrResult.imageWidth).toDouble(),
              imageHeight: math.max(1, widget.ocrResult.imageHeight).toDouble(),
              fit: widget.fit,
            );

        final Rect? dragRect =
            (_dragStartLocal != null && _dragCurrentLocal != null)
            ? Rect.fromPoints(_dragStartLocal!, _dragCurrentLocal!)
            : null;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Underlying Image
            Image(
              image: widget.image,
              fit: widget.fit,
              width: containerSize.width,
              height: containerSize.height,
            ),

            // 2. Interactive MouseRegion + GestureDetector + CustomPaint Overlay
            MouseRegion(
              cursor: _hoveredLineIndex != null
                  ? SystemMouseCursors.text
                  : SystemMouseCursors.basic,
              onHover: (PointerHoverEvent event) {
                final int? hit = _hitTestLineIndex(
                  event.localPosition,
                  transform,
                );
                if (hit != _hoveredLineIndex) {
                  setState(() {
                    _hoveredLineIndex = hit;
                  });
                }
              },
              onExit: (_) {
                if (_hoveredLineIndex != null) {
                  setState(() {
                    _hoveredLineIndex = null;
                  });
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails details) {
                  final int? hit = _hitTestLineIndex(
                    details.localPosition,
                    transform,
                  );
                  if (hit != null) {
                    final Set<int> current = Set<int>.from(
                      _controller.selectedIndices,
                    );
                    if (current.contains(hit) && current.length == 1) {
                      current.remove(hit);
                    } else {
                      current
                        ..clear()
                        ..add(hit);
                    }
                    _controller.setSelection(current);
                    _notifySelectionChanged();
                    if (widget.copyOnSingleTap && current.isNotEmpty) {
                      _copySelectedText();
                    }
                  } else {
                    _controller.clearSelection();
                    _notifySelectionChanged();
                  }
                },
                onPanStart: (DragStartDetails details) {
                  setState(() {
                    _dragStartLocal = details.localPosition;
                    _dragCurrentLocal = details.localPosition;
                  });
                },
                onPanUpdate: (DragUpdateDetails details) {
                  setState(() {
                    _dragCurrentLocal = details.localPosition;
                  });
                  if (_dragStartLocal != null && _dragCurrentLocal != null) {
                    final Rect marquee = Rect.fromPoints(
                      _dragStartLocal!,
                      _dragCurrentLocal!,
                    );
                    final Set<int> hits = _hitTestMarquee(marquee, transform);
                    _controller.setSelection(hits);
                  }
                },
                onPanEnd: (DragEndDetails details) {
                  setState(() {
                    _dragStartLocal = null;
                    _dragCurrentLocal = null;
                  });
                  _notifySelectionChanged();
                },
                onPanCancel: () {
                  setState(() {
                    _dragStartLocal = null;
                    _dragCurrentLocal = null;
                  });
                },
                child: AnimatedBuilder(
                  animation: _fadeController,
                  builder: (BuildContext context, Widget? child) {
                    return CustomPaint(
                      painter: _OcrLiveTextPainter(
                        lines: widget.ocrResult.lines,
                        transform: transform,
                        selectedIndices: _controller.selectedIndices,
                        hoveredIndex: _hoveredLineIndex,
                        highlightOpacity: _fadeController.value,
                        dragMarqueeRect: dragRect,
                        highlightFillColor: widget.highlightFillColor,
                        highlightBorderColor: widget.highlightBorderColor,
                        selectedFillColor: widget.selectedFillColor,
                        selectedBorderColor: widget.selectedBorderColor,
                        hoveredFillColor: widget.hoveredFillColor,
                        marqueeFillColor: widget.marqueeFillColor,
                        marqueeBorderColor: widget.marqueeBorderColor,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 3. Floating Selection Action Toolbar
            if (widget.showFloatingToolbar &&
                _controller.selectedIndices.isNotEmpty)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(24),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${_controller.selectedIndices.length} selected',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'ocr_live_text_copy_btn',
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy'),
                            onPressed: _copySelectedText,
                          ),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'ocr_live_text_select_all_btn',
                            ),
                            icon: const Icon(
                              Icons.select_all_rounded,
                              size: 16,
                            ),
                            label: const Text('Select All'),
                            onPressed: () {
                              _controller.selectAll(
                                widget.ocrResult.lines.length,
                              );
                              _notifySelectionChanged();
                            },
                          ),
                          for (final OcrLiveTextCustomAction action
                              in widget.customActions)
                            TextButton.icon(
                              icon: Icon(
                                action.icon ?? Icons.auto_awesome_rounded,
                                size: 16,
                              ),
                              label: Text(action.label),
                              onPressed: () => action.onPressed(
                                _selectedText,
                                _selectedLines,
                              ),
                            ),
                          IconButton(
                            key: const ValueKey<String>(
                              'ocr_live_text_clear_btn',
                            ),
                            tooltip: 'Clear selection',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _controller.clearSelection();
                              _notifySelectionChanged();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 4. Corner Live Text Highlight Toggle Badge
            if (widget.showToggleHighlightsButton)
              Positioned(
                bottom: 12,
                right: 12,
                child: FloatingActionButton.small(
                  key: const ValueKey<String>('ocr_live_text_toggle_btn'),
                  heroTag: null,
                  tooltip: _controller.showHighlightBoxes
                      ? 'Hide Live Text Highlights'
                      : 'Show Live Text Highlights',
                  onPressed: () => _controller.toggleHighlightBoxes(),
                  child: Icon(
                    _controller.showHighlightBoxes
                        ? Icons.text_fields_rounded
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Checks whether [localPoint] lies inside any rotated [OcrTextLine] quadrilateral.
  int? _hitTestLineIndex(
    Offset localPoint,
    _ImageCoordinateTransform transform,
  ) {
    final Offset imagePoint = transform.localToImage(localPoint);
    for (int i = widget.ocrResult.lines.length - 1; i >= 0; i--) {
      final OcrTextLine line = widget.ocrResult.lines[i];
      if (_isPointInPolygon(imagePoint, line.cornerPoints)) {
        return i;
      }
    }
    return null;
  }

  /// Finds all [OcrTextLine] indices whose transformed polygons intersect [localMarquee].
  Set<int> _hitTestMarquee(
    Rect localMarquee,
    _ImageCoordinateTransform transform,
  ) {
    final Set<int> selected = <int>{};
    for (int i = 0; i < widget.ocrResult.lines.length; i++) {
      final OcrTextLine line = widget.ocrResult.lines[i];
      final List<Offset> localCorners = line.cornerPoints
          .map(transform.imageToLocal)
          .toList(growable: false);
      final Rect localBounds = _polygonBounds(localCorners);
      if (localMarquee.overlaps(localBounds)) {
        selected.add(i);
      }
    }
    return selected;
  }

  /// Ray-casting point-in-polygon algorithm for rotated 4-corner quadrilaterals.
  static bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final double xi = polygon[i].dx;
      final double yi = polygon[i].dy;
      final double xj = polygon[j].dx;
      final double yj = polygon[j].dy;

      final bool intersect =
          ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) *
                      (point.dy - yi) /
                      ((yj - yi) == 0 ? 1e-7 : (yj - yi)) +
                  xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  static Rect _polygonBounds(List<Offset> pts) {
    double minX = pts.first.dx;
    double maxX = pts.first.dx;
    double minY = pts.first.dy;
    double maxY = pts.first.dy;
    for (final Offset p in pts.skip(1)) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class _ImageCoordinateTransform {
  const _ImageCoordinateTransform({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });

  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  factory _ImageCoordinateTransform.compute({
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

    return _ImageCoordinateTransform(
      scaleX: scaleX,
      scaleY: scaleY,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  Offset imageToLocal(Offset imagePoint) {
    return Offset(
      offsetX + imagePoint.dx * scaleX,
      offsetY + imagePoint.dy * scaleY,
    );
  }

  Offset localToImage(Offset localPoint) {
    return Offset(
      (localPoint.dx - offsetX) / (scaleX == 0 ? 1.0 : scaleX),
      (localPoint.dy - offsetY) / (scaleY == 0 ? 1.0 : scaleY),
    );
  }
}

class _OcrLiveTextPainter extends CustomPainter {
  const _OcrLiveTextPainter({
    required this.lines,
    required this.transform,
    required this.selectedIndices,
    required this.hoveredIndex,
    required this.highlightOpacity,
    required this.dragMarqueeRect,
    required this.highlightFillColor,
    required this.highlightBorderColor,
    required this.selectedFillColor,
    required this.selectedBorderColor,
    required this.hoveredFillColor,
    required this.marqueeFillColor,
    required this.marqueeBorderColor,
  });

  final List<OcrTextLine> lines;
  final _ImageCoordinateTransform transform;
  final Set<int> selectedIndices;
  final int? hoveredIndex;
  final double highlightOpacity;
  final Rect? dragMarqueeRect;
  final Color highlightFillColor;
  final Color highlightBorderColor;
  final Color selectedFillColor;
  final Color selectedBorderColor;
  final Color hoveredFillColor;
  final Color marqueeFillColor;
  final Color marqueeBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < lines.length; i++) {
      final OcrTextLine line = lines[i];
      if (line.cornerPoints.length < 4) continue;

      final bool isSelected = selectedIndices.contains(i);
      final bool isHovered = hoveredIndex == i;

      if (!isSelected && !isHovered && highlightOpacity <= 0.01) {
        continue;
      }

      final List<Offset> pts = line.cornerPoints
          .map(transform.imageToLocal)
          .toList(growable: false);

      final Path polyPath = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy)
        ..lineTo(pts[3].dx, pts[3].dy)
        ..close();

      final Color baseFill = isSelected
          ? selectedFillColor
          : (isHovered ? hoveredFillColor : highlightFillColor);
      final Color baseBorder = isSelected
          ? selectedBorderColor
          : highlightBorderColor;

      final double effectiveOpacity = (isSelected || isHovered)
          ? 1.0
          : highlightOpacity;

      final Paint fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = baseFill.withValues(
          alpha: (baseFill.a * effectiveOpacity).clamp(0.0, 1.0),
        );

      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.2 : 1.3
        ..strokeJoin = StrokeJoin.round
        ..color = baseBorder.withValues(
          alpha: (baseBorder.a * effectiveOpacity).clamp(0.0, 1.0),
        );

      canvas.drawPath(polyPath, fillPaint);
      canvas.drawPath(polyPath, borderPaint);
    }

    // Draw interactive drag selection marquee rectangle if active
    if (dragMarqueeRect != null) {
      final Paint marqueeFill = Paint()
        ..style = PaintingStyle.fill
        ..color = marqueeFillColor;
      final Paint marqueeStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = marqueeBorderColor;
      canvas.drawRect(dragMarqueeRect!, marqueeFill);
      canvas.drawRect(dragMarqueeRect!, marqueeStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _OcrLiveTextPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.selectedIndices != selectedIndices ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.highlightOpacity != highlightOpacity ||
        oldDelegate.dragMarqueeRect != dragMarqueeRect;
  }
}
