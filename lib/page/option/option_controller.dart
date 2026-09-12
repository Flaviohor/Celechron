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
        iOptions: secureStorageIOSOptions);

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
        iOptions: secureStorageIOSOptions);

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

  /// 桌面端没有可写的系统日历，整块能力不可用。
  bool get _calendarAvailable => PlatformFeatures.isMobile;

  // 日历同步相关getter
  bool get calendarSyncEnabled =>
      _calendarAvailable && _calendarManager.calendarSyncEnabled;

  bool get hasCalendarPermission =>
      _calendarAvailable && _calendarManager.hasCalendarPermission;

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) =>
      _calendarManager.toggleCalendarSync(context, enabled);

  void showCalendarSyncDialog(BuildContext context) =>
      _calendarManager.showCalendarSyncDialog(context);

  Map<String, dynamic> getCalendarSyncStatus() {
    if (!_calendarAvailable) {
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
