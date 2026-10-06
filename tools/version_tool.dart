/// WinWin 版本管理与审查工具。
///
/// 单一事实源：`pubspec.yaml` 的 `version: <name>+<code>`。
/// 纪律：版本名（name）可持平、可降级；版本代码（code）只增不减。
/// code 采用日期编码 `YYMMDDnn`（当次编译日 + 当日序号），由本工具自动分配；
/// 历史权威 = git 全 refs（HEAD / 分支 / tag / 远端），不维护额外账本文件。
///
/// 用法：
///   dart run tools/version_tool.dart show                  显示当前版本 + 全局历史对照
///   dart run tools/version_tool.dart set x.y.z             设置版本名并自动分配版本代码
///   dart run tools/version_tool.dart set --code N          保持版本名，仅重新分配版本代码
///   dart run tools/version_tool.dart check                 版本纪律审查（CI 门禁，失败退出码 1）
///   dart run tools/version_tool.dart history               版本谱系审计列表
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Android versionCode 上限（int32）。
const int _versionCodeCap = 2100000000;

/// 发布 tag 前缀。
const String _tagPrefix = 'v';

/// git log 提交元信息行的起始标记（`%x01`）。
const String _metaMarker = '\x01';

/// pubspec.yaml 中的 version 行（行内匹配，不吞换行）。
final RegExp _versionLineRe = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

/// 版本名规范：MAJOR.MINOR.PATCH 三段数字，可选预发布后缀（与 pub_semver 兼容）。
final RegExp _versionNameRe = RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$');

/// `git log -p` 输出中新增的 version 行。
final RegExp _diffVersionRe = RegExp(r'^\+version:\s*(.+?)\s*$');

/// 一条版本记录（工作区 / 某个历史变更点）。
class VersionRecord {
  VersionRecord({
    required this.raw,
    required this.commit,
    required this.date,
    required this.subject,
  });

  /// 原始版本字符串（`<name>+<code>`，code 可能缺失）。
  final String raw;

  /// 来源提交（工作区为 `worktree`，HEAD 快照为 `HEAD`）。
  final String commit;

  /// 提交日期（yyyy-MM-dd；工作区为空）。
  final String date;

  /// 提交标题（工作区为空）。
  final String subject;

  String get name {
    final index = raw.indexOf('+');
    return index < 0 ? raw : raw.substring(0, index);
  }

  int? get code {
    final index = raw.indexOf('+');
    if (index < 0) return null;
    return int.tryParse(raw.substring(index + 1));
  }
}

void main(List<String> arguments) {
  final command = arguments.isEmpty ? 'show' : arguments.first;
  final options = arguments.skip(1).toList();
  final root = _projectRoot();

  if (!File('$root/pubspec.yaml').existsSync()) {
    _fatal('未找到 pubspec.yaml（项目根：$root）');
  }

  switch (command) {
    case 'show':
      _show(root);
    case 'set':
      _set(root, options);
    case 'check':
      exitCode = _check(root);
    case 'history':
      _history(root);
    case 'help' || '-h' || '--help':
      _usage();
    default:
      _usage();
      _fatal('未知命令：$command');
  }
}

/// 项目根目录（脚本位于 `tools/` 下）。
String _projectRoot() => File.fromUri(Platform.script).parent.parent.path;

void _usage() {
  stdout.writeln('''
WinWin 版本管理与审查工具（版本名可持平/降级，版本代码只增不减）

用法：dart run tools/version_tool.dart <命令> [参数]

命令：
  show              显示当前版本 + 全局历史对照
  set <x.y.z>       设置版本名并自动分配版本代码（日期编码 YYMMDDnn）
  set --code <N>    保持版本名，仅重新分配版本代码
  check             版本纪律审查（退出码 0 通过 / 1 失败，供 CI 门禁）
  history           版本谱系审计列表''');
}

Never _fatal(String message, [int code = 2]) {
  stderr.writeln('错误：$message');
  exit(code);
}

// ---------------------------------------------------------------------------
// 数据读取
// ---------------------------------------------------------------------------

/// 读取工作区 pubspec.yaml 中的版本。
VersionRecord? _worktreeVersion(String root) {
  final content = File('$root/pubspec.yaml').readAsStringSync();
  final match = _versionLineRe.firstMatch(content);
  if (match == null) return null;
  return VersionRecord(raw: match.group(1)!, commit: 'worktree', date: '', subject: '');
}

/// 读取 HEAD 提交中的版本快照。
VersionRecord? _headVersion(String root) {
  final result = Process.runSync(
    'git',
    ['show', 'HEAD:pubspec.yaml'],
    workingDirectory: root,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) return null;
  final match = _versionLineRe.firstMatch(result.stdout as String);
  if (match == null) return null;
  return VersionRecord(raw: match.group(1)!, commit: 'HEAD', date: '', subject: '');
}

/// 扫描全 refs（HEAD / 分支 / tag / 远端）上的 pubspec 版本变更记录。
///
/// 一次 `git log -p` 遍历 diff,提取每个 "*新增* version 行" 所在的提交；
/// 同提交同值去重。该记录即版本谱系，也是 code 单调性的权威依据。
List<VersionRecord> _scanHistory(String root) {
  final result = Process.runSync(
    'git',
    [
      'log',
      'HEAD',
      '--branches',
      '--tags',
      '--remotes',
      '--date=short',
      '--pretty=format:$_metaMarker%H$_metaMarker%ad$_metaMarker%s',
      '-p',
      '--',
      'pubspec.yaml',
    ],
    workingDirectory: root,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    _fatal('git log 执行失败：${(result.stderr as String).trim()}');
  }

  final records = <VersionRecord>[];
  final seen = <String>{};
  var commit = '';
  var date = '';
  var subject = '';

  for (final line in (result.stdout as String).split('\n')) {
    if (line.startsWith(_metaMarker)) {
      final parts = line.split(_metaMarker);
      if (parts.length >= 4) {
        commit = parts[1];
        date = parts[2];
        subject = parts.sublist(3).join(_metaMarker);
      }
      continue;
    }
    final match = _diffVersionRe.firstMatch(line);
    if (match == null) continue;
    final value = match.group(1)!;
    if (!seen.add('$commit|$value')) continue;
    records.add(VersionRecord(raw: value, commit: commit, date: date, subject: subject));
  }
  return records;
}

/// 历史记录中的最大版本代码（跳过缺失 / 非法值）。
int _maxUsedCode(List<VersionRecord> history) {
  var max = 0;
  for (final record in history) {
    final code = record.code;
    if (code != null) max = math.max(max, code);
  }
  return max;
}

// ---------------------------------------------------------------------------
// 编码辅助
// ---------------------------------------------------------------------------

/// 解码日期编码 `YYMMDDnn` → 可读文本；非日期形态返回 null。
String? _decodeDateCode(int code) {
  final text = code.toString();
  if (text.length != 8) return null;
  final month = int.parse(text.substring(2, 4));
  final day = int.parse(text.substring(4, 6));
  final sequence = int.parse(text.substring(6, 8));
  if (month < 1 || month > 12 || day < 1 || day > 31 || sequence < 1 || sequence > 99) {
    return null;
  }
  return '20${text.substring(0, 2)}-${text.substring(2, 4)}-${text.substring(4, 6)} 第 $sequence 次构建';
}

/// code 在 `base+1..base+99` 内时返回当日序号（1..99），否则返回 0。
int _dailySequence(int code, int base) => (code > base && code < base + 100) ? code - base : 0;

String _truncate(String text, int maxRunes) {
  final runes = text.runes;
  if (runes.length <= maxRunes) return text;
  return '${String.fromCharCodes(runes.take(maxRunes))}…';
}

// ---------------------------------------------------------------------------
// 命令：show
// ---------------------------------------------------------------------------

void _show(String root) {
  final current = _worktreeVersion(root);
  if (current == null) _fatal('pubspec.yaml 中缺少 version 行');
  final history = _scanHistory(root);
  final maxUsed = _maxUsedCode(history);

  stdout.writeln('── 版本状态 ──────────────────────────────────────');
  _printCurrent(current, indent: '工作区：');
  final head = _headVersion(root);
  if (head != null) {
    final same = head.raw == current.raw;
    stdout.writeln('HEAD  ：${head.raw}${same ? '' : '（与工作区不一致：存在未提交的版本变更）'}');
  }
  stdout.writeln('历史  ：${history.length} 条版本变更（全 refs）· 已用最大 code：$maxUsed');

  final code = current.code;
  if (code != null) {
    if (code < maxUsed) {
      stdout.writeln('警告  ：当前 code $code 低于历史最大值 $maxUsed（降级覆盖风险，先 set 重新分配）');
    } else if (code == maxUsed) {
      stdout.writeln('状态  ：code 与历史最大值一致（已提交发布状态）');
    } else {
      stdout.writeln('状态  ：code 高于历史最大值（新分配待提交，或手工跳号）');
    }
  }

  if (history.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('最近版本变更（最多 5 条）：');
    for (final record in history.take(5)) {
      final codeText = record.code?.toString() ?? '（无 code）';
      stdout.writeln(
        '  ${record.date}  ${codeText.padRight(10)}${record.name.padRight(12)}'
        '${record.commit.substring(0, 7)}  ${_truncate(record.subject, 48)}',
      );
    }
  }
}

void _printCurrent(VersionRecord current, {String indent = ''}) {
  final code = current.code;
  final decoded = code == null ? null : _decodeDateCode(code);
  final suffix = decoded == null ? '' : '（$decoded）';
  stdout.writeln(
    '$indent${current.raw}  → name=${current.name}  code=${code ?? '（缺失）'}$suffix',
  );
}

// ---------------------------------------------------------------------------
// 命令：set
// ---------------------------------------------------------------------------

void _set(String root, List<String> options) {
  String? nameArgument;
  int? codeArgument;
  for (var i = 0; i < options.length; i++) {
    final option = options[i];
    if (option == '--code') {
      if (i + 1 >= options.length) _fatal('--code 需要一个整数参数');
      codeArgument = int.tryParse(options[++i]);
      if (codeArgument == null) _fatal('--code 的参数不是合法整数：${options[i]}');
    } else if (option.startsWith('--')) {
      _fatal('未知参数：$option');
    } else {
      if (nameArgument != null) _fatal('只允许一个版本名参数');
      nameArgument = option;
    }
  }

  final current = _worktreeVersion(root);
  if (current == null) _fatal('pubspec.yaml 中缺少 version 行');

  final newName = nameArgument ?? current.name;
  if (!_versionNameRe.hasMatch(newName)) {
    _fatal('版本名不符合规范（MAJOR.MINOR.PATCH 三段数字，可带预发布后缀）：$newName');
  }

  final history = _scanHistory(root);
  final maxUsed = _maxUsedCode(history);

  int newCode;
  var fallback = false;
  if (codeArgument != null) {
    if (codeArgument <= maxUsed || codeArgument <= (current.code ?? 0)) {
      _fatal(
        '指定的 code $codeArgument 必须大于历史最大值 $maxUsed '
        '且大于当前值 ${current.code ?? '（缺失）'}',
      );
    }
    newCode = codeArgument;
  } else {
    final now = DateTime.now();
    final todayBase = (now.year % 100) * 10000 + now.month * 100 + now.day; // YYMMDD
    final base = todayBase * 100;
    var maxSequence = 0;
    for (final record in history) {
      final code = record.code;
      if (code != null) maxSequence = math.max(maxSequence, _dailySequence(code, base));
    }
    maxSequence = math.max(maxSequence, _dailySequence(current.code ?? 0, base));
    final candidate = base + maxSequence + 1;
    newCode = math.max(candidate, math.max(maxUsed, current.code ?? 0) + 1);
    fallback = newCode != candidate;
  }

  if (newCode > _versionCodeCap) {
    _fatal('版本代码 $newCode 超过上限 $_versionCodeCap（Android int32）');
  }

  final file = File('$root/pubspec.yaml');
  final updated = file
      .readAsStringSync()
      .replaceFirst(_versionLineRe, 'version: $newName+$newCode');
  file.writeAsStringSync(updated);

  stdout.writeln('版本已更新：${current.raw} → $newName+$newCode');
  final decoded = _decodeDateCode(newCode);
  stdout.writeln('  code 解码：${decoded ?? '（非日期编码）'}');
  if (fallback) {
    stdout.writeln('  ⚠ 本次 code 由防倒退兜底分配（当日候选已被占用或时钟异常，属正常保护）');
  }
  stdout.writeln('');
  stdout.writeln('下一步：');
  stdout.writeln('  1. dart run tools/version_tool.dart check     # 发布预检');
  stdout.writeln('  2. git add pubspec.yaml && git commit         # 提交版本变更');
  stdout.writeln('  3. git tag $_tagPrefix$newName+$newCode      # 发布标签（触发 Release 工作流）');
}

// ---------------------------------------------------------------------------
// 命令：check
// ---------------------------------------------------------------------------

int _check(String root) {
  final current = _worktreeVersion(root);
  if (current == null) _fatal('pubspec.yaml 中缺少 version 行');

  final history = _scanHistory(root);
  final maxUsed = _maxUsedCode(history);
  final problems = <String>[];
  final warnings = <String>[];
  final notes = <String>[];

  // 1. 版本名规范
  if (!_versionNameRe.hasMatch(current.name)) {
    problems.add('版本名「${current.name}」不符合规范（MAJOR.MINOR.PATCH 三段数字，可带预发布后缀）');
  }

  // 2. 版本代码：合法性 / 上限 / 单调性 / 日期编码形态
  final code = current.code;
  if (code == null || code <= 0) {
    problems.add('版本代码缺失或非正整数：${current.raw}');
  } else {
    if (code > _versionCodeCap) {
      problems.add('版本代码 $code 超过上限 $_versionCodeCap（Android versionCode int32）');
    }
    if (code < maxUsed) {
      problems.add(
        '版本代码 $code 低于历史最大值 $maxUsed —— 存在降级覆盖风险'
        '（旧提交回建 / hotfix 分支须先 set 重新分配）',
      );
    } else if (code > maxUsed) {
      notes.add('版本代码 $code 高于历史最大值 $maxUsed（新分配待提交，或手工跳号）');
    } else {
      notes.add('版本代码 $code 与历史最大值一致（已提交发布状态）');
    }
    if (_decodeDateCode(code) == null) {
      warnings.add('版本代码 $code 不符合 YYMMDDnn 日期编码形态（疑似兜底 / 手工值），请人工确认');
    }
  }

  // 3. 浅克隆检测（历史不完整时扫描结果不可信）
  final shallow = Process.runSync(
    'git',
    ['rev-parse', '--is-shallow-repository'],
    workingDirectory: root,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if ((shallow.stdout as String).trim() == 'true') {
    warnings.add('当前为浅克隆，历史扫描不完整（CI 需 fetch-depth: 0）');
  }

  // 4. HEAD 上的发布 tag 与 pubspec 交叉校验
  final tagsResult = Process.runSync(
    'git',
    ['tag', '--points-at', 'HEAD'],
    workingDirectory: root,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  for (final tag in (tagsResult.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)) {
    if (!tag.startsWith(_tagPrefix)) continue;
    final body = tag.substring(_tagPrefix.length);
    final plus = body.indexOf('+');
    if (plus < 0) {
      warnings.add('tag $tag 未携带版本代码（规范：$_tagPrefix 前缀 + name+code）');
      continue;
    }
    final tagName = body.substring(0, plus);
    final tagCode = body.substring(plus + 1);
    if (tagName != current.name || tagCode != '${current.code}') {
      warnings.add('tag $tag 与 pubspec 版本（${current.raw}）不一致');
    }
  }

  // 5. 工作区与 HEAD 一致性（提示）
  final head = _headVersion(root);
  if (head != null && head.raw != current.raw) {
    notes.add('工作区版本与 HEAD（${head.raw}）不一致（未提交的版本变更）');
  }

  // 报告
  stdout.writeln('── WinWin 版本纪律审查 ───────────────────────────');
  _printCurrent(current, indent: '工作区：');
  if (head != null) stdout.writeln('HEAD  ：${head.raw}');
  stdout.writeln('历史  ：${history.length} 条版本变更 · 已用最大 code $maxUsed');
  stdout.writeln('');
  for (final note in notes) {
    stdout.writeln('  · $note');
  }
  for (final warning in warnings) {
    stdout.writeln('  ⚠ $warning');
  }
  for (final problem in problems) {
    stdout.writeln('  ✗ $problem');
  }
  if (notes.isEmpty && warnings.isEmpty && problems.isEmpty) {
    stdout.writeln('  （无校验信息）');
  }
  stdout.writeln('');
  if (problems.isEmpty) {
    stdout.writeln('结果：✓ 通过（${notes.length} 项记录 · ${warnings.length} 项提示）');
  } else {
    stdout.writeln('结果：✗ 失败（${problems.length} 项问题 · ${warnings.length} 项提示）');
  }
  return problems.isEmpty ? 0 : 1;
}

// ---------------------------------------------------------------------------
// 命令：history
// ---------------------------------------------------------------------------

void _history(String root) {
  final history = _scanHistory(root);
  final sorted = [...history]..sort((a, b) => (a.code ?? -1).compareTo(b.code ?? -1));

  stdout.writeln('── 版本谱系（全 refs · 按 code 升序 · 共 ${sorted.length} 条）──────────');
  stdout.writeln(
    '${'code'.padRight(11)}${'name'.padRight(13)}${'日期'.padRight(12)}${'提交'.padRight(9)}主题',
  );
  for (final record in sorted) {
    final codeText = record.code?.toString() ?? '（无 code）';
    stdout.writeln(
      '${codeText.padRight(11)}${record.name.padRight(13)}${record.date.padRight(12)}'
      '${record.commit.substring(0, 7).padRight(9)}${_truncate(record.subject, 52)}',
    );
  }
}
