// 为 Flutter 预生成插件链接。
//
// 背景
// ----
// Flutter 构建桌面/移动端时，要求每个插件的平台目录以「符号链接」的形式挂在
//     <platform>/flutter/ephemeral/.plugin_symlinks/<插件名>
// 下（见 flutter_tools/lib/src/flutter_plugins.dart 的
// _createPlatformPluginSymlinks）。它的判断逻辑是：
//
//     final Link link = symlinkDirectory.childLink(name);
//     if (link.existsSync()) continue;   // 已存在就跳过
//     link.createSync(path);             // 否则自己建
//
// 而创建真正的符号链接在 Windows 上需要「开发者模式」或管理员权限。没有权限时
// createSync 会失败，Flutter 抛出：
//     Building with plugins requires symlink support.
//     Please enable Developer Mode in your system settings.
//
// 绕法
// ----
// 目录联接（junction）不需要任何特权，而且 Dart 的
//     FileSystemEntity.typeSync(path, followLinks: false)
// 会把 junction 判定为 FileSystemEntityType.link —— 也就是说
//     Link(path).existsSync() == true
// Flutter 因此认为链接已经存在，直接跳过创建，构建得以继续。
//
// 用法
// ----
//     dart run tool/link_plugins.dart
//
// 每次 pub get 之后、build 之前跑一次（build.sh / run.sh 已经自动调用）。

import 'dart:convert';
import 'dart:io';

/// Flutter 会为工程里存在的每个平台目录生成一遍链接，三个都要处理，
/// 否则会在没处理的平台上以同样的方式失败。
const List<String> _platforms = <String>['windows', 'linux', 'macos'];

Future<void> main(List<String> args) async {
  final Directory root = _projectRoot();

  final File depFile = File('${root.path}/.flutter-plugins-dependencies');
  if (!depFile.existsSync()) {
    stderr.writeln('找不到 .flutter-plugins-dependencies，请先执行 flutter pub get');
    exit(1);
  }

  final Map<String, dynamic> dependencies =
      jsonDecode(await depFile.readAsString()) as Map<String, dynamic>;
  final Map<String, dynamic> pluginsByPlatform =
      (dependencies['plugins'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  var created = 0;
  var skipped = 0;

  for (final String platform in _platforms) {
    final Directory platformDir = Directory('${root.path}/$platform');
    if (!platformDir.existsSync()) {
      continue;
    }

    final List<dynamic> plugins =
        (pluginsByPlatform[platform] as List<dynamic>?) ?? <dynamic>[];
    if (plugins.isEmpty) {
      continue;
    }

    final Directory linkDir = Directory(
      '${platformDir.path}/flutter/ephemeral/.plugin_symlinks',
    );
    linkDir.createSync(recursive: true);

    for (final dynamic entry in plugins) {
      final Map<String, dynamic> plugin = entry as Map<String, dynamic>;
      final String name = plugin['name'] as String;
      // .flutter-plugins-dependencies 里的路径被多转义了一层，解出来是
      // `E:\\pub-cache\\...`（双反斜杠）。这里把连续的分隔符一律压成单个。
      final String target = (plugin['path'] as String)
          .replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator)
          .replaceAll(RegExp(r'[\\/]+$'), '');
      final String linkPath =
          '${linkDir.path}${Platform.pathSeparator}$name'.replaceAll(
        RegExp(r'[\\/]+'),
        Platform.pathSeparator,
      );

      if (FileSystemEntity.typeSync(linkPath, followLinks: false) ==
          FileSystemEntityType.link) {
        skipped++;
        continue;
      }

      _removeEntry(linkPath);
      final ProcessResult result = await Process.run('cmd', <String>[
        '/c',
        'mklink',
        '/J',
        linkPath,
        target,
      ]);
      if (result.exitCode != 0) {
        stderr.writeln('创建链接失败 $name -> $target');
        stderr.writeln(result.stderr);
        exit(1);
      }
      created++;
    }
  }

  stdout.writeln('插件链接就绪：新建 $created 个，复用 $skipped 个');
}

Directory _projectRoot() {
  // 本脚本位于 <root>/tool/ 下
  File dir = File.fromUri(Platform.script).absolute;
  return Directory(dir.parent.parent.path);
}

/// 删掉占用链接位置的条目。
///
/// 可能是历史遗留的空目录（早期构建失败留下的），也可能是上一次建的 junction。
/// junction 用 rmdir 删除只会摘掉接驳点、不会动到目标，所以这两种都用 rmdir，
/// 最后才退回 unlink / 递归删除。
void _removeEntry(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return;
  }
  try {
    Directory(path).deleteSync();
    return;
  } on FileSystemException {
    // 不是目录（可能是真符号链接），继续尝试
  }
  try {
    Link(path).deleteSync();
    return;
  } on FileSystemException {
    Directory(path).deleteSync(recursive: true);
  }
}
