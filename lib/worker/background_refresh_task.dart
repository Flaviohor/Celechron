import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/notification_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:celechron/utils/json_utils.dart';
import 'package:celechron/utils/utils.dart';

/// 后台刷新的实际工作内容：抓取学业数据并按需发出通知。
///
/// 与调度方式解耦——移动端由 Workmanager 的独立 isolate 调用，桌面端由应用内
/// 定时器调用，两端执行的是同一份逻辑。
///
/// [yieldToForeground] 为 true 时（移动端 isolate）检测到前台活跃就让行，
/// 避免和前台刷新重复干活；桌面端定时器跑在应用主进程内，传 false 直接执行。
Future<void> refreshScholar({bool yieldToForeground = true}) async {
  if (yieldToForeground && await RefreshCoordinator.shouldYieldBackground()) {
    DiagnosticLogService.instance.record(
      module: 'refresh',
      operation: 'backgroundYield',
      message: '后台任务启动时检测到活跃前台，已正常让行',
      origin: RefreshOrigin.background,
    );
    return;
  }

  await NotificationService.ensureInitialized();

  var scholar = Scholar();
  var secureStorage = const FlutterSecureStorage();
  scholar.username = await secureStorage.read(
      key: 'username',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);
  scholar.password = await secureStorage.read(
      key: 'password',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);
  var oldGpa = await secureStorage.read(
          key: 'gpa',
          iOptions: secureStorageIOSOptions,
          mOptions: secureStorageMacOsOptions) ??
      '0.0';
  var gradedCourseCount = await secureStorage.read(
          key: 'gradedCourseCount',
          iOptions: secureStorageIOSOptions,
          mOptions: secureStorageMacOsOptions) ??
      '0';
  var pushOnGradeChangeFuse = await secureStorage.read(
      key: 'pushOnGradeChangeFuse',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);
  var pushOnGradeChange = await secureStorage.read(
      key: 'pushOnGradeChange',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);
  var pushOnDdlReminder = await secureStorage.read(
      key: 'pushOnDdlReminder',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);
  var notifiedDdlIdsStr = await secureStorage.read(
      key: 'notifiedDdlIds',
      iOptions: secureStorageIOSOptions,
      mOptions: secureStorageMacOsOptions);

  try {
    var backgroundYielded = false;
    final refreshErrors = await scholar.refresh(
      origin: RefreshOrigin.background,
      onBackgroundYield: () => backgroundYielded = true,
    );
    if (backgroundYielded) return;
    // 后台刷新拿到整体降级结果时不发通知，避免把旧缓存误判为新成绩或新作业。
    if (refreshErrors.whereType<String>().any((error) =>
        isDegradedRefreshText(error) && shortErrorText(error).contains('刷新'))) {
      return;
    }
    bool failed(String interfaceName) => refreshErrors
        .whereType<String>()
        .any((error) => shortErrorText(error).contains(interfaceName));

    // 成绩变动通知
    if (pushOnGradeChange != 'false' && !failed('成绩')) {
      if (pushOnGradeChangeFuse == null) {
        await NotificationService.show(
          id: 0,
          title: '首次成绩推送',
          body: '若有新出分的课程，PCelechron 将会通知您。若不需要此功能，可在 PCelechron 的设置页面中关闭。',
          details: NotificationService.gradeChangeDetails,
        );
        await secureStorage.write(
            key: 'pushOnGradeChangeFuse',
            value: '1',
            iOptions: secureStorageIOSOptions,
            mOptions: secureStorageMacOsOptions);
      } else if (scholar.gpa[0] != double.tryParse(oldGpa) ||
          scholar.gradedCourseCount != int.tryParse(gradedCourseCount)) {
        await NotificationService.show(
          id: 0,
          title: '成绩变动提醒',
          body: '有新出分的课程，可在 PCelechron 的学业页面中刷新查看。',
          details: NotificationService.gradeChangeDetails,
        );
      }
      await secureStorage.write(
          key: 'gpa',
          value: scholar.gpa[0].toString(),
          iOptions: secureStorageIOSOptions,
          mOptions: secureStorageMacOsOptions);
      await secureStorage.write(
          key: 'gradedCourseCount',
          value: scholar.gradedCourseCount.toString(),
          iOptions: secureStorageIOSOptions,
          mOptions: secureStorageMacOsOptions);
    }

    // DDL 截止提醒
    if (pushOnDdlReminder != 'false' && !failed('作业')) {
      Set<String> notifiedDdlIds = {};
      if (notifiedDdlIdsStr != null && notifiedDdlIdsStr.isNotEmpty) {
        final decoded = jsonDecode(notifiedDdlIdsStr);
        notifiedDdlIds = (asDynamicList(decoded) ?? const [])
            .map(asString)
            .whereType<String>()
            .toSet();
      }

      var now = DateTime.now();
      var upcomingTodos = scholar.todos.where((todo) {
        if (todo.endTime == null) return false;
        var timeLeft = todo.endTime!.difference(now);
        // 24 小时内到期且尚未通知过
        return timeLeft.inHours >= 0 &&
            timeLeft.inHours <= 24 &&
            !notifiedDdlIds.contains(todo.id);
      }).toList();

      if (upcomingTodos.isNotEmpty) {
        var notificationId = 1000; // DDL 通知从 1000 开始
        for (var todo in upcomingTodos) {
          var hoursLeft = todo.endTime!.difference(now).inHours;
          var timeDesc = hoursLeft > 0 ? '$hoursLeft 小时后' : '即将';
          await NotificationService.show(
            id: notificationId++,
            title: '作业截止提醒',
            body: '「${todo.course}」的作业「${todo.name}」将于$timeDesc截止',
            details: NotificationService.ddlReminderDetails,
          );
          notifiedDdlIds.add(todo.id);
        }
      }

      // 清理已过期的通知记录，避免无限增长
      notifiedDdlIds.removeWhere((id) {
        var todo = scholar.todos.where((t) => t.id == id);
        if (todo.isEmpty) return true;
        return todo.first.endTime != null && todo.first.endTime!.isBefore(now);
      });

        await secureStorage.write(
            key: 'notifiedDdlIds',
            value: jsonEncode(notifiedDdlIds.toList()),
            iOptions: secureStorageIOSOptions,
            mOptions: secureStorageMacOsOptions);
    }
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('后台学业刷新失败：${error.runtimeType}: $error\n$stackTrace');
    }
    return;
  }
}
