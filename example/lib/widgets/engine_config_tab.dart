import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Supported UI locale presets for demonstrating [OcrLiveTextStrings] i18n customization.
enum DemoOverlayLocale {
  enUS('English (Default)', OcrLiveTextStrings()),
  zhCN('简体中文 (OcrLiveTextStrings.zhCN)', null),
  jaJP('日本語 (OcrLiveTextStrings.jaJP)', null);

  const DemoOverlayLocale(this.label, this._staticStrings);

  final String label;
  final OcrLiveTextStrings? _staticStrings;

  OcrLiveTextStrings get strings {
    switch (this) {
      case DemoOverlayLocale.enUS:
        return _staticStrings!;
      case DemoOverlayLocale.zhCN:
        return OcrLiveTextStrings.zhCN();
      case DemoOverlayLocale.jaJP:
        return OcrLiveTextStrings.jaJP();
    }
  }
}

/// Tab 4: Multilingual OCR model selector, Execution Provider selector,
/// `OcrLiveTextStrings` i18n language switcher, and DBNet/CTC threshold sliders.
class EngineConfigTab extends StatelessWidget {
  const EngineConfigTab({
    super.key,
    required this.selectedLanguage,
    required this.selectedProvider,
    required this.selectedOverlayLocale,
    required this.doAngle,
    required this.boxThresh,
    required this.unclipRatio,
    required this.minConfidence,
    required this.onLanguageChanged,
    required this.onProviderChanged,
    required this.onOverlayLocaleChanged,
    required this.onDoAngleChanged,
    required this.onBoxThreshChanged,
    required this.onUnclipRatioChanged,
    required this.onMinConfidenceChanged,
    required this.onThresholdChangeCommitted,
  });

  final OcrLanguage selectedLanguage;
  final OcrExecutionProvider selectedProvider;
  final DemoOverlayLocale selectedOverlayLocale;
  final bool doAngle;
  final double boxThresh;
  final double unclipRatio;
  final double minConfidence;

  final ValueChanged<OcrLanguage> onLanguageChanged;
  final ValueChanged<OcrExecutionProvider> onProviderChanged;
  final ValueChanged<DemoOverlayLocale> onOverlayLocaleChanged;
  final ValueChanged<bool> onDoAngleChanged;
  final ValueChanged<double> onBoxThreshChanged;
  final ValueChanged<double> onUnclipRatioChanged;
  final ValueChanged<double> onMinConfidenceChanged;
  final VoidCallback onThresholdChangeCommitted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Multilingual Model & Hardware Acceleration (OcrModelConfig)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Active Model Assets for ${selectedLanguage.displayName}:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text('• det: ${selectedLanguage.defaultDetAssetPath}'),
                Text('• rec: ${selectedLanguage.defaultRecAssetPath}'),
                Text('• keys: ${selectedLanguage.defaultKeysAssetPath}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<OcrLanguage>(
          initialValue: selectedLanguage,
          decoration: const InputDecoration(
            labelText: 'OCR Recognition Language (80+ Languages Support)',
            border: OutlineInputBorder(),
          ),
          items: OcrLanguage.values
              .map(
                (OcrLanguage lang) => DropdownMenuItem<OcrLanguage>(
                  value: lang,
                  child: Text(lang.displayName),
                ),
              )
              .toList(),
          onChanged: (OcrLanguage? val) {
            if (val != null) onLanguageChanged(val);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<OcrExecutionProvider>(
          initialValue: selectedProvider,
          decoration: const InputDecoration(
            labelText: 'Execution Provider (Hardware Acceleration)',
            border: OutlineInputBorder(),
          ),
          items: OcrExecutionProvider.values
              .map(
                (OcrExecutionProvider ep) =>
                    DropdownMenuItem<OcrExecutionProvider>(
                      value: ep,
                      child: Text('${ep.name} (${ep.wireName})'),
                    ),
              )
              .toList(),
          onChanged: (OcrExecutionProvider? val) {
            if (val != null) onProviderChanged(val);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<DemoOverlayLocale>(
          initialValue: selectedOverlayLocale,
          decoration: const InputDecoration(
            labelText: 'Live Text Toolbar Language (OcrLiveTextStrings i18n)',
            border: OutlineInputBorder(),
          ),
          items: DemoOverlayLocale.values
              .map(
                (DemoOverlayLocale loc) => DropdownMenuItem<DemoOverlayLocale>(
                  value: loc,
                  child: Text(loc.label),
                ),
              )
              .toList(),
          onChanged: (DemoOverlayLocale? val) {
            if (val != null) onOverlayLocaleChanged(val);
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Detection & Recognition Thresholds (OcrRecognizeOptions)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SwitchListTile(
          title: const Text(
            'Enable 180° / Tilt Angle Classification (doAngle)',
          ),
          value: doAngle,
          onChanged: onDoAngleChanged,
        ),
        _buildSliderRow(
          label:
              'DBNet Box Threshold (boxThresh): ${boxThresh.toStringAsFixed(2)}',
          value: boxThresh,
          min: 0.1,
          max: 0.9,
          onChanged: onBoxThreshChanged,
        ),
        _buildSliderRow(
          label:
              'Polygon Unclip Ratio (unclipRatio): ${unclipRatio.toStringAsFixed(2)}',
          value: unclipRatio,
          min: 1.0,
          max: 2.5,
          onChanged: onUnclipRatioChanged,
        ),
        _buildSliderRow(
          label:
              'Min Confidence Filter (minConfidence): ${minConfidence.toStringAsFixed(2)}',
          value: minConfidence,
          min: 0.0,
          max: 0.95,
          onChanged: onMinConfidenceChanged,
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: (_) => onThresholdChangeCommitted(),
        ),
      ],
    );
  }
}
