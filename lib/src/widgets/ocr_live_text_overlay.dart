import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/ocr_result.dart';
import '../models/ocr_text_line.dart';
import 'ocr_exif_coordinate_mapper.dart';
import 'ocr_image_coordinate_transform.dart';
import 'ocr_live_text_controller.dart';
import 'ocr_live_text_custom_action.dart';
import 'ocr_live_text_geometry.dart';
import 'ocr_live_text_layout.dart';
import 'ocr_live_text_painter.dart';
import 'ocr_live_text_strings.dart';
import 'ocr_live_text_style.dart';

export 'ocr_exif_coordinate_mapper.dart';
export 'ocr_image_coordinate_transform.dart';
export 'ocr_live_text_controller.dart';
export 'ocr_live_text_custom_action.dart';
export 'ocr_live_text_geometry.dart';
export 'ocr_live_text_layout.dart';
export 'ocr_live_text_painter.dart';
export 'ocr_live_text_strings.dart';
export 'ocr_live_text_style.dart';

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
    this.layout = const OcrLiveTextLayout.contain(),
    this.style = const OcrLiveTextStyle(),
    this.initialShowHighlights = true,
    this.showFloatingToolbar = true,
    this.showToggleHighlightsButton = true,
    this.copyOnSingleTap = false,
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

  /// Fit, alignment, and filter quality shared by the [Image] and the highlights.
  final OcrLiveTextLayout layout;

  /// Colors, outset, score floors, and the upright-quad snap.
  final OcrLiveTextStyle style;

  /// Whether highlight boxes are initially visible when [controller] is not provided.
  final bool initialShowHighlights;

  /// Whether to display the floating action toolbar when one or more text lines are selected.
  final bool showFloatingToolbar;

  /// Whether to render the corner Live Text badge button that toggles highlight visibility.
  final bool showToggleHighlightsButton;

  /// If `true`, tapping a single text box immediately copies its text to the system clipboard.
  final bool copyOnSingleTap;

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

  /// Decoded bitmap size and [ImageInfo.scale]. Resolved once per provider so
  /// BoxFit uses the same pixels [Image] paints. Hover and selection do not
  /// touch these fields.
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _decodedPixelSize;
  double _decodedImageScale = 1.0;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageStream();
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
    if (oldWidget.image != widget.image) {
      _decodedPixelSize = null;
      _decodedImageScale = 1.0;
      _resolveImageStream();
    }
  }

  void _resolveImageStream() {
    final ImageStream stream = widget.image.resolve(
      createLocalImageConfiguration(context),
    );
    if (identical(stream, _imageStream) || stream.key == _imageStream?.key) {
      return;
    }
    _detachImageStream();
    _imageStream = stream;
    _imageListener = ImageStreamListener((
      ImageInfo info,
      bool synchronousCall,
    ) {
      final Size size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      final double scale = info.scale == 0 ? 1.0 : info.scale;
      info.dispose();
      if (_decodedPixelSize == size && _decodedImageScale == scale) return;
      if (synchronousCall || !mounted) {
        _decodedPixelSize = size;
        _decodedImageScale = scale;
        return;
      }
      setState(() {
        _decodedPixelSize = size;
        _decodedImageScale = scale;
      });
    }, onError: (Object error, StackTrace? stackTrace) {});
    _imageStream!.addListener(_imageListener!);
  }

  void _detachImageStream() {
    final ImageStreamListener? listener = _imageListener;
    if (_imageStream != null && listener != null) {
      _imageStream!.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _detachImageStream();
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
        final OcrDisplayedImageSpace displaySpace =
            OcrDisplayedImageSpace.resolve(
              correctedWidth: widget.ocrResult.imageWidth,
              correctedHeight: widget.ocrResult.imageHeight,
              exifOrientation: widget.ocrResult.exifOrientation,
              decodedPixelSize: _decodedPixelSize,
            );
        final OcrImageCoordinateTransform transform =
            OcrImageCoordinateTransform.compute(
              containerSize: containerSize,
              imageWidth: displaySpace.imageWidth,
              imageHeight: displaySpace.imageHeight,
              fit: widget.layout.fit,
              alignment: widget.layout.alignment,
              imageScale: _decodedImageScale,
            );
        final List<_PreparedLine> prepared = _prepareLines(displaySpace);

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Underlying Image (never rebuilt on hover/selection/drag)
            Image(
              image: widget.image,
              fit: widget.layout.fit,
              alignment: widget.layout.alignment,
              filterQuality: widget.layout.filterQuality,
              gaplessPlayback: true,
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
                          prepared,
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
                    prepared,
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
                    final Set<int> hits = _hitTestMarquee(
                      marquee,
                      transform,
                      prepared,
                    );
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
                    lines: prepared
                        .map((_PreparedLine line) => line.line)
                        .toList(growable: false),
                    sourceIndices: prepared
                        .map((_PreparedLine line) => line.sourceIndex)
                        .toList(growable: false),
                    highlightOutset: widget.style.highlightOutset,
                    transform: transform,
                    selectedIndicesListenable:
                        _controller.selectedIndicesListenable,
                    hoveredIndexListenable: _hoveredLineIndexNotifier,
                    highlightOpacityListenable: _fadeController,
                    dragMarqueeListenable: _dragMarqueeNotifier,
                    highlightFillColor: widget.style.highlightFillColor,
                    highlightBorderColor: widget.style.highlightBorderColor,
                    selectedFillColor: widget.style.selectedFillColor,
                    selectedBorderColor: widget.style.selectedBorderColor,
                    hoveredFillColor: widget.style.hoveredFillColor,
                    marqueeFillColor: widget.style.marqueeFillColor,
                    marqueeBorderColor: widget.style.marqueeBorderColor,
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
                                      _controller.setSelection(
                                        prepared.map(
                                          (_PreparedLine line) =>
                                              line.sourceIndex,
                                        ),
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

  List<_PreparedLine> _prepareLines(OcrDisplayedImageSpace space) {
    final List<OcrTextLine> source = widget.ocrResult.lines;
    final List<_PreparedLine> prepared = <_PreparedLine>[];
    // Junk is judged in corrected OCR space. Display size can be the raw
    // EXIF bitmap, which would reject corners that are valid before mapping.
    final double correctedWidth = widget.ocrResult.imageWidth.toDouble();
    final double correctedHeight = widget.ocrResult.imageHeight.toDouble();
    for (int i = 0; i < source.length; i++) {
      final OcrTextLine line = source[i];
      if (!OcrLiveTextGeometry.isDisplayable(
        line,
        imageWidth: correctedWidth,
        imageHeight: correctedHeight,
        minConfidence: widget.style.minConfidence,
        minBoxScore: widget.style.minBoxScore,
      )) {
        continue;
      }
      final List<Offset> displayCorners = line.cornerPoints
          .map(space.toDisplay)
          .toList(growable: false);
      final OcrTextLine sanitized = OcrLiveTextGeometry.sanitize(
        line.copyWith(
          cornerPoints: displayCorners,
          boundingBox: OcrLiveTextGeometry.polygonBounds(displayCorners),
        ),
        axisSnapDegrees: widget.style.axisSnapDegrees,
      );
      if (!OcrLiveTextGeometry.isDisplayable(
        sanitized,
        imageWidth: space.imageWidth,
        imageHeight: space.imageHeight,
        minConfidence: widget.style.minConfidence,
        minBoxScore: widget.style.minBoxScore,
      )) {
        continue;
      }
      prepared.add(_PreparedLine(sourceIndex: i, line: sanitized));
    }
    return prepared;
  }

  /// Checks whether [localPoint] lies inside a painted highlight quad.
  int? _hitTestLineIndex(
    Offset localPoint,
    OcrImageCoordinateTransform transform,
    List<_PreparedLine> prepared,
  ) {
    for (int i = prepared.length - 1; i >= 0; i--) {
      final List<Offset> quad = OcrLiveTextGeometry.paintedQuad(
        imageCorners: prepared[i].line.cornerPoints,
        transform: transform,
        outset: widget.style.highlightOutset,
      );
      if (OcrLiveTextGeometry.containsPoint(localPoint, quad)) {
        return prepared[i].sourceIndex;
      }
    }
    return null;
  }

  /// Finds source indices whose painted quads intersect [localMarquee].
  Set<int> _hitTestMarquee(
    Rect localMarquee,
    OcrImageCoordinateTransform transform,
    List<_PreparedLine> prepared,
  ) {
    final Set<int> selected = <int>{};
    for (final _PreparedLine preparedLine in prepared) {
      final List<Offset> quad = OcrLiveTextGeometry.paintedQuad(
        imageCorners: preparedLine.line.cornerPoints,
        transform: transform,
        outset: widget.style.highlightOutset,
      );
      if (OcrLiveTextGeometry.quadIntersectsRect(quad, localMarquee)) {
        selected.add(preparedLine.sourceIndex);
      }
    }
    return selected;
  }
}

/// A displayable line plus its index in [OcrResult.lines].
class _PreparedLine {
  const _PreparedLine({required this.sourceIndex, required this.line});

  final int sourceIndex;
  final OcrTextLine line;
}
