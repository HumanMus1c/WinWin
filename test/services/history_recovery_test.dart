import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/services/history_recovery.dart';

void main() {
  group('HistoryRecoveryService.reasonForCode', () {
    test('区分仅作者可见 / 下架 / 删除 / 审核中', () {
      expect(HistoryRecoveryService.reasonForCode(62012), '仅作者自己可见');
      expect(
        HistoryRecoveryService.reasonForCode(62002),
        '稿件不可见（可能已下架）',
      );
      expect(HistoryRecoveryService.reasonForCode(62004), '稿件正在审核中');
      expect(HistoryRecoveryService.reasonForCode(-404), '稿件已删除');
      expect(HistoryRecoveryService.reasonForCode(-403), '无权访问该稿件');
    });

    test('未知错误码回落为通用不可见', () {
      expect(HistoryRecoveryService.reasonForCode(-1), '稿件不可见');
      expect(HistoryRecoveryService.reasonForCode(0), '稿件不可见');
    });
  });
}
