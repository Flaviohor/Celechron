import 'dart:async';

import 'package:pcelechron/services/notification_service.dart';
import 'package:pcelechron/worker/background_refresh_scheduler.dart';
import 'package:pcelechron/worker/background_refresh_task.dart';

/// 桌面首次检查的延迟。
///
/// Workmanager 在移动端有 initialDelay = 一个周期；桌面端的应用内定时器如果
/// 也等 15 分钟，用户开一会儿就关掉的话一次都跑不到，所以先做一次快速检查。
const Duration desktopFirstCheckDelay = Duration(seconds: 20);

/// 桌面端（Windows / macOS / Linux）后台刷新调度：应用内定时器。
///
/// 桌面没有系统级后台任务，定时器只在应用运行期间生效（含最小化到托盘）。
/// 这是能力边界，不是 bug——真正需要常驻提醒时应改用 Windows 服务或计划任务。
class DesktopBackgroundRefreshScheduler implements BackgroundRefreshScheduler {
  Timer? _timer;
  Timer? _firstRun;
  bool _enabled = false;

  @override
  Future<void> enable() async {
    if (_enabled) return;
    _enabled = true;
    await NotificationService.ensureInitialized();

    _firstRun?.cancel();
    _firstRun = Timer(desktopFirstCheckDelay, () {
      if (!_enabled) return;
      unawaited(_run());
    });

    _timer?.cancel();
    _timer = Timer.periodic(backgroundScholarFetchInterval, (_) {
      if (!_enabled) return;
      unawaited(_run());
    });
  }

  @override
  Future<void> disable() async {
    _enabled = false;
    _firstRun?.cancel();
    _firstRun = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    // 定时器跑在应用主进程内，这里不再让行前台，否则窗口开着时永远不刷新。
    await refreshScholar(yieldToForeground: false);
  }
}
