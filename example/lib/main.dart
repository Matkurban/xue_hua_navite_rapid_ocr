import 'package:material_ui/material_ui.dart';

import 'pages/ocr_demo_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XueHuaRapidOcrExampleApp());
}

class XueHuaRapidOcrExampleApp extends StatelessWidget {
  const XueHuaRapidOcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XueHua Native RapidOCR Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42A5F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const OcrDemoHomePage(),
    );
  }
}
