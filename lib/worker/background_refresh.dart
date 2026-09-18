import 'package:pcelechron/utils/platform_features.dart';
import 'background_refresh_desktop.dart';
import 'background_refresh_mobile.dart';
import 'background_refresh_scheduler.dart';

export 'background_refresh_scheduler.dart';

/// 全局唯一的调度器实例。
///
/// 用单例是因为桌面端实现持有定时器——如果每次调用都新建一个实例，
/// 开启/关闭开关反复切换会叠加出多个定时器。
final BackgroundRefreshScheduler backgroundRefreshScheduler =
    PlatformFeatures.hasBackgroundRefresh
        ? MobileBackgroundRefreshScheduler()
        : DesktopBackgroundRefreshScheduler();
