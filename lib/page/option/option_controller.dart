import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/cupertino.dart';

import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/worker/ecard_widget_messenger.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:celechron/worker/background_refresh.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/model/calendar_to_system.dart';
import 'package:celechron/model/calendar_to_ical.dart';

import 'package:celechron/utils/utils.dart';

class OptionController extends GetxController {
  final _option = Get.find<Option>(tag: 'option');
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _fuse = Get.find<Rx<Fuse>>(tag: 'fuse');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  late final RxInt allowTimeLength = _option.allowTime.length.obs;

  // 日历管理器
  late final CalendarToSystemManager _calendarManager;

  @override
  void onInit() {
    super.onInit();
    _calendarManager = CalendarToSystemManager(scholar.value);

    _updateBackgroundWorker(
        _option.pushOnGradeChange.value || _option.pushOnDdlReminder.value);

    ever(courseIdMappingList, (value) {
      _db.setCourseIdMappingList(value);
    });

    // 系统日历同步依赖 device_calendar，只有 Android / iOS 提供了实现。
    // 桌面端插件未注册，调用会直接抛 MissingPluginException，因此整块跳过。
    if (PlatformFeatures.isMobile) {
      _calendarManager.checkInitialCalendarSyncStatus();
    }
  }

  Duration get workTime => _option.workTime.value;

  set workTime(Duration value) {
    _option.workTime.value = value;
    _db.setWorkTime(value);
  }

  Duration get restTime => _option.restTime.value;

  set restTime(Duration value) {
    _option.restTime.value = value;
    _db.setRestTime(value);
  }

  Map<DateTime, DateTime> get allowTime => _option.allowTime;

  set allowTime(Map<DateTime, DateTime> value) {
    _option.allowTime.value = value;
    _db.setAllowTime(value);
    allowTimeLength.value = value.length;
  }

  GpaStrategy get gpaStrategy => _option.gpaStrategy.value;

  set gpaStrategy(GpaStrategy value) {
    _option.gpaStrategy.value = value;
    _db.setGpaStrategy(value);
  }

  bool get pushOnGradeChange => _option.pushOnGradeChange.value;

  set pushOnGradeChange(bool value) {
    _option.pushOnGradeChange.value = value;
    _db.setPushOnGradeChange(value);
    // 同步到 SecureStorage 供后台任务读取
    _db.secureStorage.write(
        key: 'pushOnGradeChange',
        value: value.toString(),
        iOptions: secureStorageIOSOptions,
        mOptions: secureStorageMacOsOptions);

    _updateBackgroundWorker(value || pushOnDdlReminder);
  }

  bool get pushOnDdlReminder => _option.pushOnDdlReminder.value;

  set pushOnDdlReminder(bool value) {
    _option.pushOnDdlReminder.value = value;
    _db.setPushOnDdlReminder(value);
    // 同步到 SecureStorage 供后台任务读取
    _db.secureStorage.write(
        key: 'pushOnDdlReminder',
        value: value.toString(),
        iOptions: secureStorageIOSOptions,
        mOptions: secureStorageMacOsOptions);

    _updateBackgroundWorker(value || pushOnGradeChange);
  }

  void _updateBackgroundWorker(bool enabled) {
    if (enabled) {
      unawaited(backgroundRefreshScheduler.enable());
    } else {
      unawaited(backgroundRefreshScheduler.disable());
    }
  }

  BrightnessMode get brightnessMode => _option.brightnessMode.value;

  set brightnessMode(BrightnessMode value) {
    _option.brightnessMode.value = value;
    _db.setBrightnessMode(value);
  }

  RxList<CourseIdMap> get courseIdMappingList => _option.courseIdMappingList;

  bool get hideHomeGpa => _option.hideHomeGpa.value;

  set hideHomeGpa(bool value) {
    _option.hideHomeGpa.value = value;
    _db.setHideHomeGpa(value);
  }

  bool get asyncRefresh => _option.asyncRefresh.value;

  set asyncRefresh(bool value) {
    _option.asyncRefresh.value = value;
    _db.setAsyncRefresh(value);
  }

  String get celechronVersion => _fuse.value.displayVersion;

  bool get hasNewVersion => _fuse.value.hasNewVersion;

  Future<void> logout() async {
    await scholar.value.logout();
    scholar.refresh();
    pushOnGradeChange = false;
    ECardWidgetMessenger.logout();
  }

  /// calendar_to_ical.dart: 显示导出课程表对话框
  void showExportDialog(BuildContext context) {
    CalendarToIcal.showExportDialog(context, scholar.value);
  }

  /// calendar_to_system.dart: 系统日历同步相关方法

  /// 系统日历读写依赖 `device_calendar`，该插件只实现了 Android / iOS。
  /// 桌面端插件未注册，任何调用都会抛 MissingPluginException，所以整块能力
  /// 直接判定为不可用，UI 侧据此换成 iCal 导出。
  bool get systemCalendarAvailable => PlatformFeatures.isMobile;

  // 日历同步相关getter
  //
  // 注意操作数顺序不能反：把内部 RxBool 放在 && 左边。桌面端
  // systemCalendarAvailable 恒为 false，一旦把它写在前面对 RxBool 的读取就会被
  // 短路掉——依赖这两个 getter 的 Obx（设置页「日程」区块）会一个依赖都建立不
  // 起来，GetX 判定为 improper use 直接抛异常；而那个 Obx 处在 sliver 槽位，
  // 抛错后错误占位组件被塞进 sliver 槽位会引发连锁布局异常，界面卡死直至进程退出。
  bool get calendarSyncEnabled =>
      _calendarManager.calendarSyncEnabled && systemCalendarAvailable;

  bool get hasCalendarPermission =>
      _calendarManager.hasCalendarPermission && systemCalendarAvailable;

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) {
    if (!systemCalendarAvailable) return Future<void>.value();
    return _calendarManager.toggleCalendarSync(context, enabled);
  }

  void showCalendarSyncDialog(BuildContext context) {
    if (!systemCalendarAvailable) return;
    _calendarManager.showCalendarSyncDialog(context);
  }

  Map<String, dynamic> getCalendarSyncStatus() {
    if (!systemCalendarAvailable) {
      return {
        'available': false,
        'enabled': false,
        'hasPermission': false,
        'isLoggedIn': scholar.value.isLogan,
      };
    }
    final stats = _calendarManager.getSyncStats();
    return {
      'available': true,
      'enabled': calendarSyncEnabled,
      'hasPermission': hasCalendarPermission,
      'isLoggedIn': scholar.value.isLogan,
      ...stats,
    };
  }
}
