import 'dart:async' show FutureOr;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/utils/utils.dart';
import 'package:crypto/crypto.dart' show Digest;

abstract final class LoginUtils {
  /// No-op stub: in PiliPlus this pushed cookies into the system WebView.
  /// WinWin does not embed a WebView in Phase 1.
  static FutureOr<void> setWebCookie([Account? account]) async {
    debugPrint('setWebCookie: skipped (no WebView in Phase 1)');
  }

  static Future<void> onLoginMain() async {
    // TODO: Phase 2 — fetch user info via UserHttp and persist to GStorage.
    // For now just mark as logged-in.
    debugPrint('onLoginMain: account logged in');
  }

  static Future<void> onLogoutMain() async {
    debugPrint('onLogoutMain: account logged out');
  }

  static String generateBuvid() {
    final md5Str = Digest(
      List.generate(16, (_) => Utils.random.nextInt(256)),
    ).toString();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  static String get buvid => Pref.buvid;

  static String genDeviceId() {
    // https://github.com/bilive/bilive_client/blob/2873de0532c54832f5464a4c57325ad9af8b8698/bilive/lib/app_client.ts#L62
    final time = DateTime.now();

    final List<int> bytes = [
      ...Iterable.generate(16, (_) => Utils.random.nextInt(256)),
      _dec2bcd(time.year ~/ 100),
      _dec2bcd(time.year % 100),
      _dec2bcd(time.month),
      _dec2bcd(time.day),
      _dec2bcd(time.hour),
      _dec2bcd(time.minute),
      _dec2bcd(time.second),
      ...Iterable.generate(8, (_) => Utils.random.nextInt(256)),
    ];
    final check = (bytes.sum & 0xFF).toRadixString(16).padLeft(2, '0');

    return Digest(bytes).toString() + check;
  }

  static int _dec2bcd(int dec) {
    assert(0 <= dec && dec < 100);
    return ((dec ~/ 10) << 4) | (dec % 10);
  }
}

extension _IntSum on List<int> {
  int get sum => fold(0, (a, b) => a + b);
}
