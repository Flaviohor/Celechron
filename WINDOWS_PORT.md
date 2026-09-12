# Celechron → Windows 移植说明

把 [Celechron/Celechron](https://github.com/Celechron/Celechron)（浙大教务 App，Flutter）移植到 Windows 桌面端。

仓库位置：`E:\celechron-windows`，分支 `windows-port`。
上游基线：`94e0ca6`（Merge pull request #168）。

---

## 一、当前进度

| 阶段 | 状态 |
|---|---|
| Flutter SDK 3.47.4 + Dart 3.13.3（`E:\flutter`） | ✅ 已装 |
| 依赖解析（134 个包） | ✅ 通过 |
| `flutter analyze` | ✅ **0 error**（剩余 26 条为上游原有的 warning/info） |
| Windows 适配代码 | ✅ 已完成（见第四节） |
| `flutter build windows` | ⛔ **卡在用户侧环境**，见第二节 |

剩下 26 条警告全部落在上游文件里（`calendar_to_system.dart`、`refresh_coordinator.dart`、`grs_spider.dart` 等），与本移植无关。**本次改动的文件零告警。**

---

## 二、你要做的两件事（否则编不出 exe）

这两项都需要管理员权限，我这边做不了。

### 1. 开启开发者模式

Flutter 在 Windows 上靠**符号链接**把插件挂进构建目录。我实测过，当前权限不足：

```
Dart 符号链接: 失败 -> 1314 客户端没有所需的特权
```

开法（二选一）：

```
start ms-settings:developers
```

或「设置 → 隐私和安全性 → 开发者选项 → 开发人员模式 = 开」。

### 2. 安装 Visual Studio 2022

勾选 **「使用 C++ 的桌面开发」** 工作负载（约 6～10GB）。只要这个工作负载，不需要装完整 VS。

装完跑 `flutter doctor` 应该能看到 `[√] Visual Studio - develop Windows apps`。

---

## 三、构建与运行

环境变量已经收敛进 `tool/env.sh`，不用每次手动导出。

```bash
cd /e/celechron-windows

./tool/run.sh              # 直接跑（调试）
./tool/build.sh            # 出 release
./tool/build.sh --debug    # 出 debug
```

产物：`build/windows/x64/runner/Release/Celechron.exe`

---

## 四、改了什么

### 1. 后台刷新：从「插件绑定」改成「平台可插拔」

**这是整个移植里最核心的一处。**

上游的后台刷新、成绩推送、DDL 提醒全部依赖作者自己 fork 的 `workmanager`，而它只声明了 `android` / `ios` 两个平台 —— Windows 上完全不可用。

原来只有一份实现（`lib/worker/background_app_refresh.dart`），直接调 `Workmanager`。现在拆成四层：

```
background_refresh.dart            ← 门面，只做平台分发
background_refresh_scheduler.dart  ← 抽象接口
background_refresh_mobile.dart     ← Workmanager 实现（Android / iOS）
background_refresh_desktop.dart    ← 应用内定时器实现（Windows / macOS / Linux）
background_refresh_task.dart       ← 真正干活的逻辑，两端共用
```

`background_refresh_task.dart` 里的抓取与通知逻辑和平台彻底解耦，只多了一个 `yieldToForeground` 开关：

- 移动端的独立 isolate 传 `true` —— 检测到前台活跃就让行，避免和前台刷新重复抓取；
- 桌面端定时器跑在应用主进程内，传 `false` —— 直接执行。

设置页（`option_controller.dart`）里的三个 Workmanager 方法收敛成一个 `_updateBackgroundWorker(bool)`，不再出现任何平台分支。

### 2. 通知：抽出统一服务，补上 Windows Toast

上游的插件版本锁在 `^17.2.4`，而 Windows 支持（C++/WinRT Toast）是 **19.0.0** 才开始的。已升到 `^22.0.0`（实际解析到 22.3.0）。

顺带发现作者其实已经写好了 Windows 的初始化代码，只是被注释掉了 —— 说明他当初就卡在这个版本上。

初始化逻辑原先散在 `main.dart`、`option_controller.dart`、`background_app_refresh.dart` 三处，现在收敛成 `lib/services/notification_service.dart`，包含：

- 四个平台的 `InitializationSettings`（含 Windows 的 `appName` / `appUserModelId` / `guid`）；
- 成绩变动、DDL 提醒两个通知通道的 `NotificationDetails`；
- 幂等的 `ensureInitialized()`；
- 统一的 `show()` 封装。

> 22.x 把 `show()` 的参数从位置参数改成了命名参数，这个封装把 breaking change 挡在一处。

`windowsAppUserModelId` 目前用 `top.celechron.celechron`，**打包成 MSIX / 安装器时必须写同一个值进注册表**，否则 Toast 不会显示。

### 3. 桌面宽屏布局

底部标签栏是按手机竖屏设计的，拉到 1100px 宽后留白过多。`home_page.dart` 现在按宽度分流：

- 宽度 ≥ 700px（桌面）：左侧导航栏 + 内容区，内容区仍复用 `PageView`，只是禁用了拖拽（保留原有的页面保活与滚动位置行为）；
- 宽度 < 700px 或移动端：沿用原来的底部标签栏。

侧边栏用 Cupertino 组件手写，没引 Material 的 `NavigationRail` —— 当前是 `GetCupertinoApp`，混入 Material 主题会打架。

窗口初始尺寸从 `1280×720` 调成 `1100×760`（`windows/runner/main.cpp`）。

### 4. 系统日历：桌面端显式降级

系统日历读写依赖 `device_calendar`，同样只有 Android / iOS 实现。桌面端调用会直接抛 `MissingPluginException`。

处理方式不是删掉，而是**能力开关 + 引导**：

- `option_controller.dart` 新增 `systemCalendarAvailable`，所有日历相关 getter、`toggleCalendarSync`、`showCalendarSyncDialog` 都在这里判定并短路；
- 设置页在桌面端把「同步到系统日历」渲染成不可用状态，并提示改用「导出为iCal文件」。

iCal 导出（`calendar_to_ical.dart`，477 行纯 Dart）在 Windows 上可用 —— 已确认 `share_plus` 12.0.2 在 Windows 上支持分享文件（走 `ShowShareUIForWindow`，Win10 RS5+ / Win11）。

### 5. 深度链接加兜底

`app_links` 的自定义协议在 Windows 上要写注册表（`HKCU\Software\Classes\celechron`）。未注册时不会报错，但插件初始化可能抛异常 —— 而 `_initAppLinks()` 跑在 `initState` 里，异常会直接让首帧渲染失败。

现已整体 try/catch 并记入诊断日志，同时补了 `onError` 和 `dispose` 时的订阅取消。

### 6. 数据库

检查过：**全库零 `sqflite`**，数据层是 Hive + `path_provider`，Windows 原生可用，无需改动。

---

## 五、踩坑记录

### 1. `PUB_CACHE` 必须用正斜杠（最坑的一个）

```
Git error. Command: `git clone --no-checkout E://pub-cache\git\cache\flutter_workmanager-xxx ...`
git: 'remote-E' is not a git command.
```

Git Bash / MSYS 会把环境变量里的 Windows 反斜杠路径改写掉：

| 写成 | Dart 实际收到 | git 的解读 |
|---|---|---|
| `E:\pub-cache` | `E://pub-cache` | ❌ 当成 scheme 为 `E` 的 URL |
| `E:/pub-cache` | `E:/pub-cache` | ✅ 本地路径 |

`tool/env.sh` 里已经写死成正斜杠，并有注释说明原因。

### 2. `PATH` 里不能出现 `E:/...`

同理，`export PATH="E:/flutter/bin:$PATH"` 里的冒号会被 bash 当成 PATH 分隔符，PATH 直接被切成 `E` 和 `/flutter/bin` 两段。必须写 MSYS 风格：

```bash
export PATH="/e/flutter/bin:$PATH"
```

### 3. 关掉 Flutter 的版本检查

SDK 来自 zip 包，本地没有可用的 GitHub 远端，`flutter` 每次启动都会去 `git fetch --tags` 然后卡 ~21 秒。所有命令都加了 `--no-version-check`。

### 4. git 依赖钉死 commit

`workmanager` 是 pubspec 里的 git 依赖。上游写的是 `ref: main`，pub 每次都要联网 fetch 才能把 `main` 解析成具体 commit —— 国内网络下 GitHub 不可达就整个失败。

已改成钉死 SHA `d7e6ba5ef3796fafe54d9739e481f01058751b4d`，pub 直接读本地缓存、跳过 fetch。**升级该依赖时手动改这个 SHA。**

### 5. 别用 `Expand-Archive` 解压 Flutter SDK

PowerShell 的 `Expand-Archive` 解 23000 个文件跑了 12 分钟还没完；换 Python 的 `zipfile.extractall` 一分多钟就好了。

---

## 六、已知限制 / 未验证项

1. **编译未验证。** 卡在开发者模式和 VS2022，这两步做完才能真正编。我写到这一步为止，类型层面已由 `flutter analyze` 全量覆盖（0 error），但 CMake 链接期的问题（比如某个插件的原生代码）只能等真编译才能暴露。
2. **`jni` 出现在 Windows 的 FFI 插件列表里。** 它来自 `path_provider_android` 的传递依赖，但自身声明了 `windows: ffiPlugin: true`，于是被 Flutter 注册进了 Windows。
   检查过它的 CMake：`find_package(JNI)` **不带 `REQUIRED`**，找不到 JDK 就不建 target，属于优雅降级，不会拖垮编译。
3. **`celechron://` 自定义协议未注册。** 付款码快捷方式在 Windows 上不可用，需要安装器写注册表才能启用。
4. **安装包与代码签名未做。** 目前只能出免安装的 exe 目录。不签名的话首次运行会被 SmartScreen 拦。
5. **后台刷新在桌面端是应用内定时器。** 应用没运行就不会刷新 —— 这与移动端的系统级调度语义不同，属于平台能力差异，无法规避。
