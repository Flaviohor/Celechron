import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知服务的统一入口。
///
/// 原先 Android / iOS 的初始化与通知通道分散在 `main.dart`、
/// `option_controller.dart` 和 `background_app_refresh.dart` 三处，各自只配了
/// 移动端平台。移植到桌面后必须补上 Windows（Toast）配置，因此收敛到这里，
/// 三个调用点共用同一份初始化逻辑。
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  /// Windows Toast 通知所需的固定标识。
  ///
  /// - [appUserModelId] 必须与打包时（MSIX / 安装器）写入注册表的值一致，
  ///   否则通知不会显示。
  /// - [guid] 任意固定 GUID 即可，用于 Windows 通知的内部标识。
  static const String windowsAppName = 'PCelechron';
  static const String windowsAppUserModelId = 'top.celechron.celechron';
  static const String windowsGuid = '7c85e25b-fa7d-489e-9b10-b4c22a3458f0';

  static bool _initialized = false;

  static Future<void> init() async {
    const darwinSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: windowsAppName,
      appUserModelId: windowsAppUserModelId,
      guid: windowsGuid,
    );
    const settings = InitializationSettings(
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: windowsSettings,
    );
    await plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// 发一条通知。
  ///
  /// `flutter_local_notifications` 22.x 把 `show()` 由位置参数改成了命名参数
  /// （`id` / `title` / `body` / `notificationDetails` / `payload`），
  /// 把调用收敛到这里，插件后续再改 API 也只需要动这一个地方。
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    String? payload,
  }) async {
    await ensureInitialized();
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// 幂等初始化：多处调用只有第一次真正执行。
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await init();
  }

  /// 请求通知权限。Android 13+ 需要显式授权，Windows / iOS 已在 init 中处理。
  static Future<void> requestPermission() async {
    await ensureInitialized();
  }

  /// 成绩变动提醒通道
  static const NotificationDetails gradeChangeDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      sound: 'default',
      badgeNumber: 0,
    ),
    macOS: DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      sound: 'default',
      badgeNumber: 0,
    ),
    windows: WindowsNotificationDetails(),
  );

  /// DDL 截止提醒通道
  static const NotificationDetails ddlReminderDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      sound: 'default',
      badgeNumber: 0,
    ),
    macOS: DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      sound: 'default',
      badgeNumber: 0,
    ),
    windows: WindowsNotificationDetails(),
  );
}
