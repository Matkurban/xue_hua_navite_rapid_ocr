import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/ocr_result.dart';
import '../models/ocr_text_line.dart';
import 'ocr_image_coordinate_transform.dart';
import 'ocr_live_text_controller.dart';
import 'ocr_live_text_custom_action.dart';
import 'ocr_live_text_painter.dart';
import 'ocr_live_text_strings.dart';

export 'ocr_image_coordinate_transform.dart';
export 'ocr_live_text_controller.dart';
export 'ocr_live_text_custom_action.dart';
export 'ocr_live_text_painter.dart';
export 'ocr_live_text_strings.dart';

/// Interactive 6-platform "Live Text" overlay widget (`OcrLiveTextOverlay`).
///
/// Built with `package:material_ui/material_ui.dart` and fine-grained
/// [ValueNotifier] / [ValueListenableBuilder] / `CustomPainter(repaint: ...)` updates
/// (zero full-widget `setState` calls):
/// - Pointer hover only updates `_hoveredLineIndexNotifier` (`MouseRegion` cursor + `CustomPainter`).
/// - Drag marquee only updates `_dragMarqueeNotifier` and `_controller.selectedIndicesListenable`.
/// - Floating toolbar only rebuilds when `_controller.selectedIndicesListenable` changes.
/// - Corner toggle button only rebuilds when `_controller.showHighlightBoxesListenable` changes.
/// - All user-visible strings are customizable via [OcrLiveTextStrings] ([strings]) for i18n.
class OcrLiveTextOverlay extends StatefulWidget {
  const OcrLiveTextOverlay({
    super.key,
    required this.image,
    required this.ocrResult,
    this.controller,
    this.strings = const OcrLiveTextStrings(),
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

  /// Customizable localization strings for all buttons, tooltips, and SnackBar messages.
  final OcrLiveTextStrings strings;

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

  /// Fine-grained notifiers for hover and marquee selection (avoids `setState`).
  final ValueNotifier<int?> _hoveredLineIndexNotifier = ValueNotifier<int?>(
    null,
  );
  final ValueNotifier<Rect?> _dragMarqueeNotifier = ValueNotifier<Rect?>(null);
  Offset? _dragStartLocal;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = OcrLiveTextController(
        initialShowHighlights: widget.initialShowHighlights,
      );
      _ownsController = true;
    }
    _controller.showHighlightBoxesListenable.addListener(
      _onHighlightVisibilityChanged,
    );

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
      _controller.showHighlightBoxesListenable.removeListener(
        _onHighlightVisibilityChanged,
      );
      if (_ownsController) {
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = OcrLiveTextController(
          initialShowHighlights: widget.initialShowHighlights,
        );
        _ownsController = true;
      }
      _controller.showHighlightBoxesListenable.addListener(
        _onHighlightVisibilityChanged,
      );
    }
    if (oldWidget.ocrResult != widget.ocrResult) {
      _controller.clearSelection();
      _hoveredLineIndexNotifier.value = null;
      _dragMarqueeNotifier.value = null;
    }
  }

  @override
  void dispose() {
    _controller.showHighlightBoxesListenable.removeListener(
      _onHighlightVisibilityChanged,
    );
    if (_ownsController) {
      _controller.dispose();
    }
    _hoveredLineIndexNotifier.dispose();
    _dragMarqueeNotifier.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onHighlightVisibilityChanged() {
    if (_controller.showHighlightBoxes) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
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
    final List<OcrTextLine> lines = _selectedLines;
    if (lines.isEmpty) return;
    final String text = lines.map((OcrTextLine l) => l.text).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    widget.onTextCopied?.call(text);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(widget.strings.formatCopiedMessage(lines.length)),
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
        final OcrImageCoordinateTransform transform =
            OcrImageCoordinateTransform.compute(
              containerSize: containerSize,
              imageWidth: math.max(1, widget.ocrResult.imageWidth).toDouble(),
              imageHeight: math.max(1, widget.ocrResult.imageHeight).toDouble(),
              fit: widget.fit,
            );

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Underlying Image (never rebuilt on hover/selection/drag)
            Image(
              image: widget.image,
              fit: widget.fit,
              width: containerSize.width,
              height: containerSize.height,
            ),

            // 2. Interactive MouseRegion + GestureDetector + Repaint-Driven CustomPaint
            ValueListenableBuilder<int?>(
              valueListenable: _hoveredLineIndexNotifier,
              builder:
                  (BuildContext context, int? hoveredIndex, Widget? child) {
                    return MouseRegion(
                      cursor: hoveredIndex != null
                          ? SystemMouseCursors.text
                          : SystemMouseCursors.basic,
                      onHover: (PointerHoverEvent event) {
                        final int? hit = _hitTestLineIndex(
                          event.localPosition,
                          transform,
                        );
                        if (_hoveredLineIndexNotifier.value != hit) {
                          _hoveredLineIndexNotifier.value = hit;
                        }
                      },
                      onExit: (_) {
                        if (_hoveredLineIndexNotifier.value != null) {
                          _hoveredLineIndexNotifier.value = null;
                        }
                      },
                      child: child,
                    );
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
                  _dragStartLocal = details.localPosition;
                  _dragMarqueeNotifier.value = Rect.fromPoints(
                    details.localPosition,
                    details.localPosition,
                  );
                },
                onPanUpdate: (DragUpdateDetails details) {
                  final Offset? start = _dragStartLocal;
                  if (start != null) {
                    final Rect marquee = Rect.fromPoints(
                      start,
                      details.localPosition,
                    );
                    _dragMarqueeNotifier.value = marquee;
                    final Set<int> hits = _hitTestMarquee(marquee, transform);
                    _controller.setSelection(hits);
                  }
                },
                onPanEnd: (DragEndDetails details) {
                  _dragStartLocal = null;
                  _dragMarqueeNotifier.value = null;
                  _notifySelectionChanged();
                },
                onPanCancel: () {
                  _dragStartLocal = null;
                  _dragMarqueeNotifier.value = null;
                },
                child: CustomPaint(
                  painter: OcrLiveTextPainter(
                    lines: widget.ocrResult.lines,
                    transform: transform,
                    selectedIndicesListenable:
                        _controller.selectedIndicesListenable,
                    hoveredIndexListenable: _hoveredLineIndexNotifier,
                    highlightOpacityListenable: _fadeController,
                    dragMarqueeListenable: _dragMarqueeNotifier,
                    highlightFillColor: widget.highlightFillColor,
                    highlightBorderColor: widget.highlightBorderColor,
                    selectedFillColor: widget.selectedFillColor,
                    selectedBorderColor: widget.selectedBorderColor,
                    hoveredFillColor: widget.hoveredFillColor,
                    marqueeFillColor: widget.marqueeFillColor,
                    marqueeBorderColor: widget.marqueeBorderColor,
                  ),
                ),
              ),
            ),

            // 3. Floating Selection Action Toolbar (isolated rebuild via ValueListenableBuilder)
            if (widget.showFloatingToolbar)
              ValueListenableBuilder<Set<int>>(
                valueListenable: _controller.selectedIndicesListenable,
                builder:
                    (
                      BuildContext context,
                      Set<int> selectedIndices,
                      Widget? _,
                    ) {
                      if (selectedIndices.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      widget.strings.formatSelectedCount(
                                        selectedIndices.length,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ),
                                  TextButton.icon(
                                    key: const ValueKey<String>(
                                      'ocr_live_text_copy_btn',
                                    ),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
                                    label: Text(widget.strings.copyButtonLabel),
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
                                    label: Text(
                                      widget.strings.selectAllButtonLabel,
                                    ),
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
                                        action.icon ??
                                            Icons.auto_awesome_rounded,
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
                                    tooltip:
                                        widget.strings.clearSelectionTooltip,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
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
                      );
                    },
              ),

            // 4. Corner Live Text Highlight Toggle Badge (isolated rebuild via ValueListenableBuilder)
            if (widget.showToggleHighlightsButton)
              ValueListenableBuilder<bool>(
                valueListenable: _controller.showHighlightBoxesListenable,
                builder:
                    (BuildContext context, bool showHighlights, Widget? _) {
                      return Positioned(
                        bottom: 12,
                        right: 12,
                        child: FloatingActionButton.small(
                          key: const ValueKey<String>(
                            'ocr_live_text_toggle_btn',
                          ),
                          heroTag: null,
                          tooltip: showHighlights
                              ? widget.strings.hideHighlightsTooltip
                              : widget.strings.showHighlightsTooltip,
                          onPressed: () => _controller.toggleHighlightBoxes(),
                          child: Icon(
                            showHighlights
                                ? Icons.text_fields_rounded
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      );
                    },
              ),
          ],
        );
      },
    );
  }

  /// Checks whether [localPoint] lies inside any rotated [OcrTextLine] quadrilateral.
  int? _hitTestLineIndex(
    Offset localPoint,
    OcrImageCoordinateTransform transform,
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
    OcrImageCoordinateTransform transform,
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
