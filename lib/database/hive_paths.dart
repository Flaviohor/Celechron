// Hive 存储路径解析 + 一次性数据迁移。
//
// 现状：
//   - `Hive.initFlutter()`（hive_flutter 包）默认在 Windows / Android / iOS 上调用
//     `getApplicationDocumentsDirectory()`，在桌面端就是
//     `C:\Users\<user>\Documents\`。7 个 .hive 文件直接摊在用户的「文档」根目录里，
//     显得很脏（Windows 是用户的个人空间，Android/iOS 上是应用沙箱，不在意）。
//   - macOS / Linux 上 hive_flutter 已经走 `getApplicationSupportDirectory()`，
//     所以本文件实际只是给 Windows 桌面修这个事。
//
// 策略：
//   - 桌面端统一走 `getApplicationSupportDirectory()`（与 macOS / Linux 一致）。
//   - 移动端保留 `getApplicationDocumentsDirectory()`，不破坏现有数据。
//   - 老用户在 Windows 上 Documents 目录里的 `.hive` 文件，一次性拷到 APPDATA ，
//     写 marker `.celechron_pivot_v1` 避免重入；旧文件保留作为兜底（要清也得用户手动清，
//     脚本不擅自删）。
//   - 失败一律吞掉，不阻塞启动 —— 哪怕迁移失败，APPDATA 里也会出现一份新（空）数据，
//     用户最多丢一次缓存。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HivePaths {
  HivePaths._();

  /// 标记文件，落在新 Hive 根目录下，用于幂等。
  @visibleForTesting
  static const String pivotMarkerFileName = '.celechron_pivot_v1';

  /// 解析 Hive 根目录。桌面用 APPDATA（`%APPDATA%\Celechron\Celechron`），
  /// 移动端保持 Documents（hive_flutter 默认值，不破坏现有数据）。
  static Future<Directory> resolveHiveRoot() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return getApplicationSupportDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  /// 一次性迁移入口。Windows 上把 Documents 下的 .hive 文件搬到新的根目录。
  /// 其它平台直接返回；marker 存在时直接跳过。
  /// 失败不抛 —— 启动不能因为迁移挂掉。
  static Future<void> migrateFromLegacyDocumentsIfNeeded(
    Directory newRoot,
  ) async {
    try {
      if (!_shouldRunOnThisPlatform()) return;
      if (!newRoot.existsSync()) {
        newRoot.createSync(recursive: true);
      }
      Directory oldRoot;
      try {
        oldRoot = await getApplicationDocumentsDirectory();
      } on Object {
        return;
      }
      await migrateFiles(oldRoot: oldRoot, newRoot: newRoot);
    } on Object {
      // 静默吞掉；诊断日志服务如果在场可由调用方补一条。
    }
  }

  /// 纯迁移逻辑：把 [oldRoot] 下「值得迁移的」Hive 数据文件拷到 [newRoot]。
  ///
  /// 规则：
  ///   - 跳过 `.lock` / `.log` 等运行时生成物。
  ///   - 目标已存在则保留目标（多半用户已经在新位置用过；旧的不再覆盖）。
  ///   - 任一文件拷失败不阻塞整体。
  ///   - 同盘（`oldRoot.path == newRoot.path`）直接写 marker 跳过。
  ///   - 新位置已有 marker 视为已迁移，直接返回。
  ///
  /// 返回实际成功拷贝的文件数（不含跳过的）。
  @visibleForTesting
  static Future<int> migrateFiles({
    required Directory oldRoot,
    required Directory newRoot,
  }) async {
    if (!newRoot.existsSync()) {
      newRoot.createSync(recursive: true);
    }

    final marker = File(
      '${newRoot.path}${Platform.pathSeparator}$pivotMarkerFileName',
    );
    if (marker.existsSync()) return 0;

    final oldLower = oldRoot.path.toLowerCase();
    final newLower = newRoot.path.toLowerCase();
    if (oldLower == newLower) {
      _writeMarker(
        marker,
        oldRoot: oldRoot.path,
        newRoot: newRoot.path,
        copied: 0,
      );
      return 0;
    }

    if (!oldRoot.existsSync()) {
      _writeMarker(
        marker,
        oldRoot: oldRoot.path,
        newRoot: newRoot.path,
        copied: 0,
      );
      return 0;
    }

    var copied = 0;
    await for (final ent in oldRoot.list(followLinks: false)) {
      if (ent is! File) continue;
      final name = _basename(ent.path);
      if (!shouldMigrateFile(name)) continue;
      final target =
          File('${newRoot.path}${Platform.pathSeparator}$name');
      if (target.existsSync()) {
        continue;
      }
      try {
        await ent.copy(target.path);
        copied++;
      } on Object {
        // 单个文件失败不阻塞整体；下一启动会再试。
      }
    }

    _writeMarker(
      marker,
      oldRoot: oldRoot.path,
      newRoot: newRoot.path,
      copied: copied,
    );
    return copied;
  }

  /// 测试友好：判断一个文件名是否是值得迁移的 Hive 数据文件。
  /// - 走 `.hive` / `.hive~`（含中间重写的备份）
  /// - 排除 `.lock` / `.log` 这类运行时生成物
  @visibleForTesting
  static bool shouldMigrateFile(String basename) {
    final lower = basename.toLowerCase();
    if (lower.endsWith('.lock') || lower.endsWith('.lock~')) return false;
    if (lower.endsWith('.log')) return false;
    return lower.endsWith('.hive') || lower.contains('.hive.');
  }

  static bool _shouldRunOnThisPlatform() {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  static void _writeMarker(
    File marker, {
    required String oldRoot,
    required String newRoot,
    required int copied,
  }) {
    try {
      marker.writeAsStringSync(
        'celechron pivot v1\n'
        'from: $oldRoot\n'
        'to:   $newRoot\n'
        'copied: $copied\n'
        'at:   ${DateTime.now().toIso8601String()}\n',
        flush: true,
      );
    } on Object {
      // 写不动 marker 也不致命，下一次启动重跑一遍幂等
    }
  }

  static String _basename(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    return i < 0 ? path : path.substring(i + 1);
  }
}