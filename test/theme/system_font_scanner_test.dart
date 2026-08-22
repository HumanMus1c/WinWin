import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/theme/system_font_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemFontScanner Tests', () {
    test('scan() finds fonts on Windows and includes Microsoft YaHei and Microsoft YaHei UI all weights (Regular, Light, Bold)', () async {
      if (!Platform.isWindows) return;

      final fonts = await SystemFontScanner.scan(force: true);
      expect(fonts, isNotEmpty);

      // Verify Microsoft YaHei (Regular)
      final yahei = fonts.where((f) => f.family == 'Microsoft YaHei').toList();
      expect(yahei, isNotEmpty, reason: 'Should find Microsoft YaHei (Regular)');
      expect(yahei.first.label, '微软雅黑');

      // Verify Microsoft YaHei Light
      final yaheiLight = fonts.where((f) => f.family == 'Microsoft YaHei Light').toList();
      expect(yaheiLight, isNotEmpty, reason: 'Should find Microsoft YaHei Light');
      expect(yaheiLight.first.label, '微软雅黑 Light');

      // Verify Microsoft YaHei Bold
      final yaheiBold = fonts.where((f) => f.family == 'Microsoft YaHei Bold').toList();
      expect(yaheiBold, isNotEmpty, reason: 'Should find Microsoft YaHei Bold');
      expect(yaheiBold.first.label, '微软雅黑 Bold');

      // Verify Microsoft YaHei UI (Regular)
      final yaheiUi = fonts.where((f) => f.family == 'Microsoft YaHei UI').toList();
      expect(yaheiUi, isNotEmpty, reason: 'Should find Microsoft YaHei UI (Regular)');
      expect(yaheiUi.first.label, '微软雅黑 UI');

      // Verify Microsoft YaHei UI Light
      final yaheiUiLight = fonts.where((f) => f.family == 'Microsoft YaHei UI Light').toList();
      expect(yaheiUiLight, isNotEmpty, reason: 'Should find Microsoft YaHei UI Light');
      expect(yaheiUiLight.first.label, '微软雅黑 UI Light');

      // Verify Microsoft YaHei UI Bold
      final yaheiUiBold = fonts.where((f) => f.family == 'Microsoft YaHei UI Bold').toList();
      expect(yaheiUiBold, isNotEmpty, reason: 'Should find Microsoft YaHei UI Bold');
      expect(yaheiUiBold.first.label, '微软雅黑 UI Bold');

      // Verify helper getByFamily
      expect(SystemFontScanner.getByFamily('Microsoft YaHei')?.label, '微软雅黑');
      expect(SystemFontScanner.getByFamily('Microsoft YaHei Bold')?.label, '微软雅黑 Bold');
      expect(SystemFontScanner.getByFamily('Microsoft YaHei Light')?.label, '微软雅黑 Light');
      expect(SystemFontScanner.getByFamily('Microsoft YaHei UI')?.label, '微软雅黑 UI');
      expect(SystemFontScanner.getByFamily('Microsoft YaHei UI Bold')?.label, '微软雅黑 UI Bold');
      expect(SystemFontScanner.getByFamily('Microsoft YaHei UI Light')?.label, '微软雅黑 UI Light');
    });
  });
}
