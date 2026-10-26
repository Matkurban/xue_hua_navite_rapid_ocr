import 'package:flutter/foundation.dart';

/// Controller for programmatically interacting with an `OcrLiveTextOverlay`.
///
/// Exposes granular [ValueListenable]s ([selectedIndicesListenable] and
/// [showHighlightBoxesListenable]) so subtrees and [CustomPainter]s can rebuild
/// or repaint independently without triggering full-widget `setState` calls.
class OcrLiveTextController extends ChangeNotifier {
  OcrLiveTextController({bool initialShowHighlights = true})
    : _showHighlightBoxesNotifier = ValueNotifier<bool>(initialShowHighlights);

  final ValueNotifier<Set<int>> _selectedIndicesNotifier =
      ValueNotifier<Set<int>>(const <int>{});
  final ValueNotifier<bool> _showHighlightBoxesNotifier;

  /// Granular listenable for selected line indices.
  ValueListenable<Set<int>> get selectedIndicesListenable =>
      _selectedIndicesNotifier;

  /// Granular listenable for highlight box visibility.
  ValueListenable<bool> get showHighlightBoxesListenable =>
      _showHighlightBoxesNotifier;

  /// Set of currently selected `OcrTextLine` indices.
  Set<int> get selectedIndices => _selectedIndicesNotifier.value;

  /// Whether all recognized text highlight boxes are currently visible.
  bool get showHighlightBoxes => _showHighlightBoxesNotifier.value;

  /// Toggles the visibility of all recognized text highlight boxes.
  void toggleHighlightBoxes([bool? visible]) {
    final bool next = visible ?? !_showHighlightBoxesNotifier.value;
    if (_showHighlightBoxesNotifier.value != next) {
      _showHighlightBoxesNotifier.value = next;
      notifyListeners();
    }
  }

  /// Selects all lines `[0 .. totalLines - 1]`.
  void selectAll(int totalLines) {
    final Set<int> next = Set<int>.unmodifiable(
      List<int>.generate(totalLines, (int i) => i),
    );
    if (!setEquals(_selectedIndicesNotifier.value, next)) {
      _selectedIndicesNotifier.value = next;
      notifyListeners();
    }
  }

  /// Clears the current selection.
  void clearSelection() {
    if (_selectedIndicesNotifier.value.isNotEmpty) {
      _selectedIndicesNotifier.value = const <int>{};
      notifyListeners();
    }
  }

  /// Replaces the current selection with [indices].
  void setSelection(Iterable<int> indices) {
    final Set<int> next = Set<int>.unmodifiable(indices);
    if (!setEquals(_selectedIndicesNotifier.value, next)) {
      _selectedIndicesNotifier.value = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _selectedIndicesNotifier.dispose();
    _showHighlightBoxesNotifier.dispose();
    super.dispose();
  }
}
