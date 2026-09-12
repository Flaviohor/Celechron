# Celechron → Windows 移植说明

把 [Celechron/Celechron](https://github.com/Celechron/Celechron)（浙大教务 App，Flutter）移植到 Windows 桌面端。

- 仓库位置：`E:\celechron-windows`，分支 `windows-port`
- 上游基线：`94e0ca6`（Merge pull request #168）
- 工具链：Flutter 3.47.4 / Dart 3.13.3（`E:\flutter`），pub 缓存 `E:\pub-cache`

---

## 一、当前状态

| 项目 | 结果 |
|---|---|
| 依赖解析（134 个包） | ✅ 通过 |
| `flutter analyze` | ✅ **0 error**（剩余 26 条为上游原有 warning/info） |
| `flutter build windows --debug` | ✅ **编译成功** |
| `flutter build windows`（release） | ✅ **编译成功** |
| 产物 | `build/windows/x64/runner/Release/`，32MB |

Release 包结构完整：`Celechron.exe`、`flutter_windows.dll`（引擎 21MB）、
6 个插件 DLL、`data/app.so`（AOT 快照 8.4MB）、`data/icudtl.dat`、`data/flutter_assets/`。

> **运行时尚未实测。** 编译期已全部通过，但「启动是否正常、通知是否弹出、
> 桌面布局效果如何」需要真正跑一次才能确认。见第七节。

---

## 二、构建前置条件

**只需一项**：安装 Visual Studio 2022，勾选「使用 C++ 的桌面开发」工作负载。

本机已满足（VS2022 Enterprise 装在 `E:\Program Files\Microsoft Visual Studio\2022\Enterprise`，
不在默认的 C 盘路径，所以 `ls "/c/Program Files/..."` 查不到，要用 `vswhere.exe` 找）。

> **不需要开启开发者模式。** Flutter 原本要求符号链接权限（会报
> `Building with plugins requires symlink support`），本移植用目录联接绕过了，
> 见第五节第 1 条。

---

## 三、构建与运行

```bash
cd /e/celechron-windows

./tool/build.sh            # 出 release
./tool/build.sh --debug    # 出 debug
./tool/run.sh              # 直接跑（调试）
```

产物：`build/windows/x64/runner/Release/Celechron.exe`

脚本会自动做三件事：加载环境变量、生成插件链接、调用 flutter。

---

## 四、改了什么

### 1. 后台刷新：从「插件绑定」改成「平台可插拔」

**这是整个移植里最核心的一处。**

上游的后台刷新、成绩推送、DDL 提醒全部依赖作者自己 fork 的 `workmanager`，
而它只声明了 `android` / `ios` —— Windows 上完全不可用。

原来只有一份实现（`lib/worker/background_app_refresh.dart`），直接调 `Workmanager`。
现在拆成四层：

| 文件 | 职责 |
|---|---|
| `background_refresh.dart` | 门面，只做平台分发 |
| `background_refresh_scheduler.dart` | 抽象接口 |
| `background_refresh_mobile.dart` | Workmanager 实现（Android / iOS） |
| `background_refresh_desktop.dart` | 应用内定时器实现（Windows / macOS / Linux） |
| `background_refresh_task.dart` | 真正干活的逻辑，两端共用 |

抓取与通知逻辑和平台彻底解耦，只多了一个 `yieldToForeground` 开关：

- 移动端的独立 isolate 传 `true` —— 检测到前台活跃就让行，避免重复抓取；
- 桌面端定时器跑在主进程内，传 `false` —— 直接执行。

设置页里的三个 Workmanager 方法收敛成一个 `_updateBackgroundWorker(bool)`，
不再出现任何平台分支。

### 2. 通知：抽出统一服务，补上 Windows Toast

上游插件版本锁在 `^17.2.4`，而 Windows 支持（C++/WinRT Toast）从 **19.0.0** 才开始。
已升到 `^22.0.0`（实际解析到 22.3.0）。

顺带发现作者其实已经写好了 Windows 初始化代码，只是被注释掉了 —— 他当初就卡在这个版本上。

初始化逻辑原先散在 `main.dart`、`option_controller.dart`、`background_app_refresh.dart`
三处，现在收敛成 `lib/services/notification_service.dart`：四个平台的
`InitializationSettings`、两个通知通道、幂等的 `ensureInitialized()`、
统一的 `show()` 封装。

> 22.x 把 `show()` 的参数从位置参数改成了命名参数，这个封装把 breaking change 挡在一处。

`windowsAppUserModelId` 用 `top.celechron.celechron`（与 iOS bundle id 一致）。
**打包成 MSIX / 安装器时必须写同一个值进注册表**，否则 Toast 不会显示。

### 3. 桌面宽屏布局

`home_page.dart` 按宽度分流：

- 宽度 ≥ 700px：左侧导航栏 + 内容区（内容区仍复用 `PageView`，只禁用了拖拽，
  保留原有的页面保活与滚动位置行为）；
- 宽度 < 700px 或移动端：沿用原来的底部标签栏。

侧边栏用 Cupertino 组件手写，没引 Material 的 `NavigationRail` ——
当前是 `GetCupertinoApp`，混入 Material 主题会打架。

窗口初始尺寸 `1280×720` → `1100×760`（`windows/runner/main.cpp`）。

### 4. 系统日历：桌面端显式降级

系统日历依赖 `device_calendar`，同样只有 Android / iOS 实现，桌面端调用会抛
`MissingPluginException`。

处理方式是**能力开关 + 引导**：`option_controller.dart` 新增
`systemCalendarAvailable`，所有日历 getter、`toggleCalendarSync`、
`showCalendarSyncDialog` 都在这里判定并短路；设置页在桌面端把「同步到系统日历」
渲染成不可用状态，并提示改用「导出为iCal文件」。

iCal 导出（`calendar_to_ical.dart`，477 行纯 Dart）在 Windows 上可用 ——
已确认 `share_plus` 12.0.2 支持 Windows 分享文件（走 `ShowShareUIForWindow`，
Win10 RS5+ / Win11）。

### 5. 深度链接加兜底

`app_links` 的自定义协议在 Windows 上要写注册表（`HKCU\Software\Classes\celechron`）。
未注册时不会报错，但插件初始化可能抛异常 —— 而 `_initAppLinks()` 跑在 `initState` 里，
异常会让首帧渲染失败。现已整体 try/catch 并记入诊断日志，补了 `onError`
和 `dispose` 时的订阅取消。

### 6. 数据库

全库零 `sqflite`，数据层是 Hive + `path_provider`，Windows 原生可用，无需改动。

---

## 五、踩坑记录

### 1. Flutter 要求插件符号链接 → 用目录联接绕过（最花时间的一处）

Flutter 构建时要求每个插件的平台目录以**符号链接**形式挂在

```
<platform>/flutter/ephemeral/.plugin_symlinks/<插件名>
```

下（`flutter_tools/lib/src/flutter_plugins.dart` 的 `_createPlatformPluginSymlinks`）。
它的逻辑是：

```dart
final Link link = symlinkDirectory.childLink(name);
if (link.existsSync()) continue;   // 已存在就跳过
link.createSync(path);             // 否则自己建
```

创建真符号链接在 Windows 上需要开发者模式或管理员权限，否则整个构建直接失败：

```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

**绕法**：目录联接（junction）不需要任何特权，而且 Dart 的
`FileSystemEntity.typeSync(path, followLinks: false)` 会把 junction 判定为
`FileSystemEntityType.link` —— 于是 `Link(path).existsSync() == true`，
Flutter 认为链接已存在，直接跳过创建。

工具：**`tool/link_plugins.dart`**，在构建前跑一次即可（`build.sh` / `run.sh` 已自动调用）。
它会读 `.flutter-plugins-dependencies`，为 `windows` / `linux` / `macos`
三个平台各建一批 junction。

> 三个平台都要处理 —— Flutter 会为工程里存在的**每个**平台目录生成一遍链接，
> 漏掉哪个就在哪个上报错。

### 2. 沙箱 / Git Bash 环境下 `PROGRAMFILES(X86)` 丢失

```
%PROGRAMFILES(X86)% environment variable not found.
```

出处：`flutter_tools/lib/src/windows/visual_studio.dart:264` ——
Flutter 靠这个变量定位 `vswhere.exe`。本会话里 `env | grep -i programfiles`
一条都没有，PowerShell 侧同样为空，是执行环境把它过滤掉了。

bash 不允许 `export` 名字带括号的变量，只能在启动子进程时用 `env` 注入，
所以 `tool/env.sh` 包了一个 **`flutterx`** 函数：

```bash
flutterx build windows        # 而不是 flutter build windows
```

值一律用正斜杠，原因同下一条。

### 3. `PUB_CACHE` 必须用正斜杠

```
Git error. Command: `git clone --no-checkout E://pub-cache\git\cache\flutter_workmanager-xxx`
git: 'remote-E' is not a git command.
```

MSYS 会把环境变量里的反斜杠 Windows 路径改写掉：

| 写成 | Dart 实际收到 | git 的解读 |
|---|---|---|
| `E:\pub-cache` | `E://pub-cache` | ❌ 当成 scheme 为 `E` 的 URL |
| `E:/pub-cache` | `E:/pub-cache` | ✅ 本地路径 |

### 4. `PATH` 里不能出现 `E:/...`

同理，`export PATH="E:/flutter/bin:$PATH"` 里的冒号会被 bash 当成 PATH 分隔符，
PATH 被切成 `E` 和 `/flutter/bin` 两段，flutter 找不到。必须写 MSYS 风格
`/e/flutter/bin`。

### 5. 路径分隔符混用会让 `mklink` 报「无效开关」

`link_plugins.dart` 里用 `Directory('${platformDir.path}/flutter/...')` 拼路径，
得到的是 `E:\celechron-windows/windows/flutter/...` 这种混合写法，
`mklink` 把 `/windows` 当成了命令行开关：

```
无效开关 - "windows"。
```

拼完路径后统一把连续分隔符压成 `Platform.pathSeparator` 即可。

### 6. `.flutter-plugins-dependencies` 里的路径被双重转义

文件里存的是 `E:\\\\pub-cache\\\\...`，JSON 解出来仍是 `E:\\pub-cache\\...`
（双反斜杠）。读出来要再把连续分隔符压成单个。

### 7. MSVC 中文注释报 C4819

```
error C2220: 以下警告被视为错误
warning C4819: 该文件包含不能在当前代码页(936)中表示的字符
```

`main.cpp` 里写了 UTF-8 中文注释，而 MSVC 在中文区域下默认按 GBK 解码源文件；
runner 又开了 `/WX`（警告即错误），直接编译失败。

修法：在 `windows/runner/CMakeLists.txt` 给 runner 目标加 `/utf-8`。
**没有**改 `windows/CMakeLists.txt` 里的 `apply_standard_settings()` ——
那里有注释明确说明插件也会继承，不宜改动。

### 8. git 依赖钉死 commit

`workmanager` 是 pubspec 里的 git 依赖。上游写 `ref: main`，pub 每次都要联网
fetch GitHub 才能把 `main` 解析成 commit —— 国内网络下 GitHub 不可达就整个失败。
已改成钉死 SHA `d7e6ba5ef3796fafe54d9739e481f01058751b4d`，pub 直接读本地缓存。
**升级该依赖时手动改这个 SHA。**

### 9. 关掉 Flutter 的版本检查

SDK 来自 zip 包，本地没有可用的 GitHub 远端，`flutter` 每次启动都会
`git fetch --tags` 然后卡 ~21 秒。`flutterx` 里已经带上 `--no-version-check`。

### 10. 别用 `Expand-Archive` 解压 Flutter SDK

PowerShell 的 `Expand-Archive` 解 23000 个文件跑了 12 分钟还没完；
Python 的 `zipfile.extractall` 一分多钟就好了。

---

## 六、网络

**不需要梯子。**

| 目标 | 结果 |
|---|---|
| `storage.flutter-io.cn`（pub 包 / 引擎产物） | ✅ 通，0.2s |
| `pub.dev` 官方源 | ✅ 通，2.9s |
| `github.com` 直连 | ❌ `:443` 超时 |

pub 包全走国内镜像，实测 0.7MB/s。GitHub 只在 git 依赖那一步需要，钉死 commit 后
构建链路里已经不再依赖它。

挂梯子反而有副作用：若代理把 `*.flutter-io.cn` 也揽过去，国内镜像会被绕到海外
转一圈，更慢。

---

## 七、尚未完成 / 未验证

1. **运行时未实测。** 编译全绿，但没有真正启动过。请跑一次：

   ```bash
   ./tool/run.sh
   ```

   重点看三处（都是我改动过的启动路径）：通知初始化是否报错、
   深度链接兜底是否生效、宽窗口下左侧导航栏是否正常。

2. **`jni` 出现在 Windows 的 FFI 插件列表里。** 它来自 `path_provider_android`
   的传递依赖，但自身声明了 `windows: ffiPlugin: true`，于是被注册进 Windows。
   本机有 JDK，所以 `dartjni.dll` 正常编出来了；没有 JDK 时它的 CMake 是
   `find_package(JNI)`（不带 `REQUIRED`），会优雅跳过，不会拖垮编译。

3. **`celechron://` 自定义协议未注册。** 付款码快捷方式在 Windows 上不可用，
   需要安装器写注册表才能启用。

4. **安装包与代码签名未做。** 目前只能出免安装的 exe 目录。
   不签名的话首次运行会被 SmartScreen 拦。

5. **后台刷新在桌面端是应用内定时器。** 应用没运行就不会刷新 ——
   这与移动端的系统级调度语义不同，属于平台能力差异，无法规避。

6. **窗口标题栏/任务栏图标**沿用模板默认值，`Runner.rc` 里的
   CompanyName / FileDescription 还是 `org.cc` / `celechron`，可后续对齐。
