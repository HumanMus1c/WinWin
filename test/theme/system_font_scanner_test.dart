import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/theme/system_font_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemFontScanner Tests', () {
    test('scan() finds fonts on Windows and includes Microsoft YaHei and Microsoft YaHei UI', () async {
      if (!Platform.isWindows) return;

      final fonts = await SystemFontScanner.scan(force: true);
      expect(fonts, isNotEmpty);

      // Verify Microsoft YaHei
      final yahei = fonts.where((f) => f.family == 'Microsoft YaHei').toList();
      expect(yahei, isNotEmpty, reason: 'Should find Microsoft YaHei font');
      expect(yahei.first.label, '微软雅黑');

      // Verify Microsoft YaHei UI
      final yaheiUi = fonts.where((f) => f.family == 'Microsoft YaHei UI').toList();
      expect(yaheiUi, isNotEmpty, reason: 'Should find Microsoft YaHei UI font');
      expect(yaheiUi.first.label, '微软雅黑 UI');

      // Verify helper getByFamily
      final yaheiInfo = SystemFontScanner.getByFamily('Microsoft YaHei');
      expect(yaheiInfo, isNotNull);
      expect(yaheiInfo!.label, '微软雅黑');

      final yaheiUiInfo = SystemFontScanner.getByFamily('Microsoft YaHei UI');
      expect(yaheiUiInfo, isNotNull);
      expect(yaheiUiInfo!.label, '微软雅黑 UI');
    });
  });
}
