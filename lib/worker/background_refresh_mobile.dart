import 'dart:async';
import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/worker/background_refresh_scheduler.dart';
import 'package:celechron/worker/background_refresh_task.dart';

/// Workmanager 的 isolate 入口。必须是顶层函数并标记 vm:entry-point。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case backgroundScholarFetchTask:
        await refreshScholar();
        break;
      default:
        break;
    }
    return Future.value(true);
  });
}

/// 移动端（Android / iOS）后台刷新调度：交给系统级 Workmanager。
class MobileBackgroundRefreshScheduler implements BackgroundRefreshScheduler {
  @override
  Future<void> enable() async {
    try {
      final workmanager = Workmanager();
      await workmanager.initialize(callbackDispatcher);
      // Android 的周期任务会跨 App 启动持久化；不要每次页面控制器初始化时
      // 重新排一个 10 秒后的任务。iOS 仍需提交 BGAppRefresh 请求，但最早
      // 执行时间与正常周期一致，并由前台租约做最终保护。
      if (Platform.isAndroid &&
          await workmanager
              .isScheduledByUniqueName(backgroundScholarFetchTask)) {
        return;
      }
      await workmanager.registerPeriodicTask(
        backgroundScholarFetchTask,
        backgroundScholarFetchTask,
        frequency: backgroundScholarFetchInterval,
        initialDelay: backgroundScholarFetchInterval,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '后台刷新',
        operation: 'schedule',
        message: '后台刷新任务注册失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> disable() async {
    try {
      await Workmanager().cancelByUniqueName(backgroundScholarFetchTask);
      if (Platform.isIOS) await Workmanager().printScheduledTasks();
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '后台刷新',
        operation: 'cancel',
        message: '后台刷新任务取消失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
