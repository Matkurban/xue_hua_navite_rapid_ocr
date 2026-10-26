/// Customizable localization strings for `OcrLiveTextOverlay`.
///
/// Pass an instance of [OcrLiveTextStrings] to `OcrLiveTextOverlay.strings`
/// to customize all floating toolbar buttons, tooltips, selection counters,
/// and clipboard feedback messages for internationalization (i18n).
class OcrLiveTextStrings {
  const OcrLiveTextStrings({
    this.copyButtonLabel = 'Copy',
    this.selectAllButtonLabel = 'Select All',
    this.clearSelectionTooltip = 'Clear selection',
    this.hideHighlightsTooltip = 'Hide Live Text Highlights',
    this.showHighlightsTooltip = 'Show Live Text Highlights',
    this.selectedCountBuilder,
    this.copiedSnackBarMessageBuilder,
  });

  /// Preset Chinese (Simplified) localization strings.
  factory OcrLiveTextStrings.zhCN() => OcrLiveTextStrings(
    copyButtonLabel: '复制',
    selectAllButtonLabel: '全选',
    clearSelectionTooltip: '清除选中',
    hideHighlightsTooltip: '隐藏实况文本高亮框',
    showHighlightsTooltip: '显示实况文本高亮框',
    selectedCountBuilder: (int count) => '已选 $count 项',
    copiedSnackBarMessageBuilder: (int count) => '已复制 $count 行文字到剪贴板',
  );

  /// Preset Japanese localization strings.
  factory OcrLiveTextStrings.jaJP() => OcrLiveTextStrings(
    copyButtonLabel: 'コピー',
    selectAllButtonLabel: 'すべて選択',
    clearSelectionTooltip: '選択を解除',
    hideHighlightsTooltip: 'テキスト認識のハイライトを隠す',
    showHighlightsTooltip: 'テキスト認識のハイライトを表示',
    selectedCountBuilder: (int count) => '$count 件選択中',
    copiedSnackBarMessageBuilder: (int count) =>
        '$count 行のテキストをクリップボードにコピーしました',
  );

  /// Label for the "Copy" action button in the floating selection bar.
  final String copyButtonLabel;

  /// Label for the "Select All" action button in the floating selection bar.
  final String selectAllButtonLabel;

  /// Tooltip for the clear selection (`X`) icon button.
  final String clearSelectionTooltip;

  /// Tooltip for the corner toggle button when highlights are currently visible.
  final String hideHighlightsTooltip;

  /// Tooltip for the corner toggle button when highlights are currently hidden.
  final String showHighlightsTooltip;

  /// Custom formatter for the selected line count badge (e.g., `"3 selected"`).
  final String Function(int selectedCount)? selectedCountBuilder;

  /// Custom formatter for the clipboard toast/SnackBar message (e.g., `"Copied 3 line(s) to clipboard"`).
  final String Function(int copiedLineCount)? copiedSnackBarMessageBuilder;

  /// Formats the selected line count using [selectedCountBuilder] or the default English template.
  String formatSelectedCount(int count) {
    if (selectedCountBuilder != null) {
      return selectedCountBuilder!(count);
    }
    return '$count selected';
  }

  /// Formats the clipboard SnackBar notification using [copiedSnackBarMessageBuilder] or the default English template.
  String formatCopiedMessage(int count) {
    if (copiedSnackBarMessageBuilder != null) {
      return copiedSnackBarMessageBuilder!(count);
    }
    return 'Copied $count line(s) to clipboard';
  }
}
