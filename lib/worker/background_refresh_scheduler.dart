/// 后台刷新的调度抽象。
///
/// 移动端（Android / iOS）用 Workmanager 在独立 isolate 里跑，桌面端
/// （Windows / macOS / Linux）没有等价的系统级后台任务机制，改为应用内定时器。
/// 两者执行的是同一份 [refreshScholar] 逻辑。
abstract class BackgroundRefreshScheduler {
  /// 开启周期性刷新。
  Future<void> enable();

  /// 停止周期性刷新。
  Future<void> disable();
}

/// 后台任务的唯一名称，与移动端已注册的任务保持一致，避免升级后残留两个任务。
const String backgroundScholarFetchTask =
    'top.celechron.celechron.backgroundScholarFetch';

/// 后台刷新周期。
const Duration backgroundScholarFetchInterval = Duration(minutes: 15);
