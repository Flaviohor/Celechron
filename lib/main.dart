import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pcelechron/services/notification_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:path_provider/path_provider.dart';

import 'package:pcelechron/model/scholar.dart';
import 'package:pcelechron/model/option.dart';
import 'package:pcelechron/page/home_page.dart';
import 'package:pcelechron/page/option/ecard_pay_page.dart';
import 'package:pcelechron/services/diagnostic_log_service.dart';
import 'package:pcelechron/services/refresh_coordinator.dart';
import 'package:pcelechron/worker/ecard_widget_messenger.dart';
import 'package:pcelechron/database/database_helper.dart';
import 'package:pcelechron/utils/global.dart';

/// 全局字体 family 名，对应 `pubspec.yaml` 里声明的 Noto Sans SC 可变字体。
///
/// 苹方（PingFang）是苹果的商用字体：Windows 上没有预装，也不能随应用分发，
/// 所以这里用观感接近、可自由分发的 Noto Sans SC（可变字体，单文件覆盖
/// bold / w600 / w500 / normal 等全部字重）。
const String kAppFontFamily = 'NotoSansSC';

/// 套上全局字体的 Cupertino 文本主题。
///
/// Cupertino **没有**「一处设置、全局生效」的字体入口：
///   * [CupertinoThemeData] 根本没有 `fontFamily` 参数；
///   * [CupertinoTextThemeData] 也没有，它的默认样式把 fontFamily 写死成
///     `CupertinoSystemText`，而且是 `inherit: false`——所以单纯改
///     [DefaultTextStyle] 覆盖不到「用了主题样式」的那些文字。
///
/// 因此只能逐个样式 `copyWith` 覆盖字体；其余属性（字号、字重、颜色、
/// letterSpacing）全部沿用系统默认，观感与原生一致。
CupertinoTextThemeData _appTextTheme() {
  final CupertinoTextThemeData base = const CupertinoTextThemeData();
  return CupertinoTextThemeData(
    textStyle: base.textStyle.copyWith(fontFamily: kAppFontFamily),
    actionTextStyle: base.actionTextStyle.copyWith(fontFamily: kAppFontFamily),
    actionSmallTextStyle:
        base.actionSmallTextStyle.copyWith(fontFamily: kAppFontFamily),
    tabLabelTextStyle:
        base.tabLabelTextStyle.copyWith(fontFamily: kAppFontFamily),
    navTitleTextStyle:
        base.navTitleTextStyle.copyWith(fontFamily: kAppFontFamily),
    navLargeTitleTextStyle:
        base.navLargeTitleTextStyle.copyWith(fontFamily: kAppFontFamily),
    navActionTextStyle:
        base.navActionTextStyle.copyWith(fontFamily: kAppFontFamily),
    pickerTextStyle: base.pickerTextStyle.copyWith(fontFamily: kAppFontFamily),
    dateTimePickerTextStyle:
        base.dateTimePickerTextStyle.copyWith(fontFamily: kAppFontFamily),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ECardWidgetMessenger.installNativeHandler();

  // 尽可能早地声明前台活跃，Workmanager isolate 会据此安全让行。
  await RefreshCoordinator.setForegroundActive(true);

  // 初始化数据库
  await Hive.initFlutter();
  // Windows 上若上次进程被强杀，Hive 留下的 .lock 0 字节文件会卡住下一次的
  // openBox（mmap 锁未释放，errno=33）。这里清掉陈旧锁文件。
  await _purgeStaleHiveLocks();
  var db = Get.put(DatabaseHelper(), tag: 'db');
  await db.init();

  // 注入数据观察项（相当于事件总线，更新这些变量将导致Widget重绘
  Get.put((await db.getScholar()).obs, tag: 'scholar');
  Get.put(db.getTaskList().obs, tag: 'taskList');
  Get.put(db.getTaskListUpdateTime().obs, tag: 'taskListLastUpdate');
  Get.put(db.getFlowList().obs, tag: 'flowList');
  Get.put(db.getFlowListUpdateTime().obs, tag: 'flowListLastUpdate');
  Get.put(db.getOption(), tag: 'option');
  Get.put(db.getFuse().obs, tag: 'fuse');

  runApp(const CelechronApp());

  var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  if (scholar.value.isLogan) {
    // 启动恢复只有一个自动刷新入口；会话重建由 Scholar.refresh 内部完成。
    // 用户此时手动刷新会复用并等待这一个 refresh Future。
    // 校园卡使用不同 HttpClient/User-Agent，等 Scholar 认证和抓取
    // 完成后再启动，避免两套 CAS 链路在启动瞬间互相干扰。
    unawaited(
      _refreshRestoredScholar(scholar)
          .whenComplete(ECardWidgetMessenger.update),
    );
  } else {
    unawaited(ECardWidgetMessenger.update());
  }
}

Future<void> _purgeStaleHiveLocks() async {
  try {
    final dir = Directory(await _hiveRootPath());
    if (!dir.existsSync()) return;
    for (final ent in dir.listSync(followLinks: false)) {
      if (ent is! File) continue;
      if (!ent.path.endsWith('.lock')) continue;
      try {
        ent.deleteSync();
      } on Object catch (_) {/* 仍被占用就不动，让 Hive 自行报错 */}
    }
  } on Object catch (_) {/* 失败也无所谓，开不了就让它正常报错 */}
}

Future<String> _hiveRootPath() async {
  try {
    return (await getApplicationDocumentsDirectory()).path;
  } on Object catch (_) {
    return Directory.systemTemp.path;
  }
}

Future<void> _refreshRestoredScholar(Rx<Scholar> scholar) async {
  GlobalStatus.isFirstScreenReq = true;
  try {
    await scholar.value.refresh(onPartialUpdate: scholar.refresh);
  } on Object catch (error, stackTrace) {
    // 启动刷新不阻断缓存数据展示，但异常仍进入诊断日志。
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: 'refresh',
      operation: 'startupRefresh',
      message: '启动自动刷新异常结束',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    GlobalStatus.isFirstScreenReq = false;
    scholar.refresh();
  }
}

class CelechronApp extends StatefulWidget {
  const CelechronApp({super.key});

  @override
  State<CelechronApp> createState() => _CelechronAppState();
}

class _CelechronAppState extends State<CelechronApp>
    with WidgetsBindingObserver {
  Timer? _foregroundLeaseHeartbeat;
  StreamSubscription<Uri>? _appLinksSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundLease();

    // 监听AppLinks，用于跳转至付款码页面
    _initAppLinks();
    // 初始化通知
    _initNotification();
    // 设置Android状态栏和导航栏样式
    if (Platform.isAndroid) {
      _initStatusBar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundLease();
    unawaited(_appLinksSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundLease();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopForegroundLease();
    }
    if (state == AppLifecycleState.paused) {
      ECardWidgetMessenger.update();
    }
  }

  void _startForegroundLease() {
    unawaited(RefreshCoordinator.setForegroundActive(true));
    _foregroundLeaseHeartbeat ??= Timer.periodic(
      RefreshCoordinator.foregroundHeartbeatInterval,
      (_) => unawaited(RefreshCoordinator.setForegroundActive(true)),
    );
  }

  void _stopForegroundLease() {
    _foregroundLeaseHeartbeat?.cancel();
    _foregroundLeaseHeartbeat = null;
    unawaited(RefreshCoordinator.setForegroundActive(false));
  }

  @override
  Widget build(BuildContext context) {
    var brightnessMode = Get.find<Option>(tag: 'option').brightnessMode;
    return Obx(() => GetCupertinoApp(
          theme: CupertinoThemeData(
            brightness: brightnessMode.value == BrightnessMode.system
                ? null
                : brightnessMode.value == BrightnessMode.dark
                    ? Brightness.dark
                    : Brightness.light,
            // 全局字体：Cupertino 没有 fontFamily 入口，只能逐样式覆盖，
            // 详见 _appTextTheme 的注释。
            textTheme: _appTextTheme(),
            scaffoldBackgroundColor: CupertinoColors.systemBackground,
            barBackgroundColor: CupertinoColors.systemBackground,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          locale: const Locale('zh'),
          builder: (context, child) => DefaultTextStyle.merge(
            // 兜底一层：让所有「没写死 fontFamily 且 inherit: true」的样式
            // （例如各处 TextStyle(fontWeight: FontWeight.bold)）也继承到全局字体。
            style: const TextStyle(fontFamily: kAppFontFamily),
            child: MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          ),
          title: 'Pcelechron',
          home: const HomePage(title: 'Pcelechron'),
          initialRoute: '/',
          routes: {
            '/ecardpaypage': (context) => ECardPayPage(),
          },
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
        ));
  }

  /// 监听 `celechron://` 深度链接，用于跳转付款码页面。
  ///
  /// Windows 上这套机制依赖安装器把自定义协议写进注册表
  /// （`HKCU\Software\Classes\celechron`）；未注册时不会有任何事件进来，
  /// 属于功能不可用而非错误。但插件在初始化阶段可能抛异常，而这里跑在
  /// `initState` 里，异常会直接让首帧渲染失败，所以整体兜住并记入诊断日志。
  void _initAppLinks() {
    try {
      final appLinks = AppLinks();
      _appLinksSubscription = appLinks.uriLinkStream.listen(
        (uri) {
          if (uri.toString() == 'celechron://ecardpaypage') {
            navigator?.popUntil((route) =>
                !(route.settings.name?.endsWith('ecardpaypage') ?? false));
            navigator?.pushNamed('/ecardpaypage');
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          DiagnosticLogService.instance.record(
            level: CelechronLogLevel.warning,
            module: 'appLinks',
            operation: 'listen',
            message: '深度链接监听中断，付款码快捷方式不可用',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: 'appLinks',
        operation: 'init',
        message: '当前平台未能初始化深度链接（自定义协议未注册）',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _initStatusBar() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    var brightnessMode = Get.find<Option>(tag: 'option').brightnessMode;
    var dispatcher = SchedulerBinding.instance.platformDispatcher;

    ever(brightnessMode, (mode) {
      if (mode == BrightnessMode.system) {
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarIconBrightness:
              dispatcher.platformBrightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
        ));
        dispatcher.onPlatformBrightnessChanged = () {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarIconBrightness:
                dispatcher.platformBrightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
          ));
        };
      } else {
        dispatcher.onPlatformBrightnessChanged = null;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarIconBrightness:
              mode == BrightnessMode.light ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
        ));
      }
    });
    brightnessMode.refresh();
  }

  /// 通知初始化。各平台的初始化设置集中在 NotificationService 里，
  /// Windows 需要 Toast 的 appUserModelId / guid，之前这里只配了移动端。
  void _initNotification() {
    unawaited(NotificationService.requestPermission());
  }
}
