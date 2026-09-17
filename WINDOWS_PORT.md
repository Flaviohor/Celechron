# Celechron → Windows 移植说明

把 [Celechron/Celechron](https://github.com/Celechron/Celechron)（浙大教务 App，Flutter）移植到 Windows 桌面端。

- 仓库位置：`E:\celechron-windows`，分支 `windows-port`
- 上游基线：`94e0ca6`（Merge pull request #168）
- 工具链：Flutter 3.47.4 / Dart 3.13.3（`E:\flutter`），pub 缓存 `E:\pub-cache`

---

## 一、当前状态

**已完成，含运行时实测与分发打包。**

| 项目 | 结果 |
|---|---|
| 依赖解析（134 个包） | ✅ 通过 |
| `flutter analyze` | ✅ **0 error**（剩余 26 条为上游原有 warning/info） |
| `flutter build windows --debug` | ✅ 编译成功 |
| `flutter build windows`（release） | ✅ 编译成功 |
| 运行时实测 | ✅ 启动稳定、登录成功、数据抓取正常（结论见下） |
| 便携版 zip | ✅ `dist/Celechron-1.3.0-windows-x64-portable.zip`（14.2 MB） |
| 单文件安装器 | ✅ `dist/Celechron-1.3.0-windows-x64-setup.exe`（11.2 MB，已实测安装） |

Release 包结构完整：`Celechron.exe`、`flutter_windows.dll`（引擎 21MB）、
6 个插件 DLL、`data/app.so`（AOT 快照 8.4MB）、`data/icudtl.dat`、`data/flutter_assets/`。

### 运行时实测结论

实际启动并观察了 60 秒以上，用截图和进程状态校验：

- 窗口以 1100×760 逻辑尺寸创建（`windows/runner/main.cpp` 的改动生效）
- 左侧导航栏正常渲染：接下来 / 日程 / 任务 / 学业 / 设置，图标与中文标签都对
- 窄窗口（< 700px）自动切回底部标签栏，自适应断点生效
- 真实登录成功，`dbuser.hive` 30KB、`dboriginalwebpage.hive` 44KB 落盘 →
  说明浙大服务端抓取链路在 Windows 上完全可用
- 诊断日志出现 `后台刷新检测到活跃前台或同账号任务，已正常让行` →
  后台刷新重构后的让行逻辑真实生效，无异常抛出

> 一个示例截图保存在 `dist/` 之外的会话记录里；界面为深色模式是因为系统主题是深色，
> 与移植改动无关。

> **注意**：本机显示缩放是 200%（DPI 192）。窗口逻辑尺寸 1100×760，
> 物理尺寸 2200×1520；非 DPI 感知的工具（如 PowerShell 直接读 `GetWindowRect`）
> 会报 1100×760 的虚拟化坐标，排查布局问题时别被这个误导。

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

## 三之二、打包分发

```bash
python tool/subset_fonts.py    # 可选：把 fonts/HarmonyOS_Sans_*.ttf 子集化（47MB -> 1.7MB）
python tool/package.py         # 便携版：dist/Celechron-<ver>-windows-x64/ + portable.zip
python tool/make_installer.py  # 单文件安装器：dist/Celechron-<ver>-windows-x64-setup.exe
```

> **字体子集化。** 6 个 HarmonyOS Sans SC 字重原始 ~8MB × 6 ≈ 47MB，
> 子集化（基于项目实际用到的 ~1500 个字符 + 一份安全垫）后单字重 ~290KB，
> 总共 ~1.7MB。备份自动落在 `fonts/_unsorted.bak/`（脚本已自动加入 `.gitignore`）。
> 只需跑一次，结果存盘后下次跳过 —— 但 **新增 UI 字符串 / 改语言文案后需要重跑**
> 否则新加的字会掉成豆腐块。脚本会输出 `build/font-chars.txt` 报告当前字符集，
> 适合提交 PR 时一并 review。

> 安装器未做代码签名，首次运行会被 SmartScreen 拦（点「更多信息 → 仍要运行」）。
> 详见第八节「代码签名：不花钱能做什么」。

### 便携版（zip）

解压即用，无需安装、无需管理员。**自带 VC++ 运行时**——`Celechron.exe` 依赖
`MSVCP140.dll` / `VCRUNTIME140.dll`（用 `dumpbin /dependents` 确认过），干净机器上
没装 VC++ 可再发行包会直接启动失败。所以从 VS 的可再发行目录取官方 CRT 文件做
app-local 部署（微软官方支持的方式），包内自带，不依赖装机环境。

### 安装器（单文件 exe）

**没用 Inno Setup**：本机没装，且当前网络下从 GitHub 拉 10.6MB 安装包屡次被代理
截断（每次响应上限约 512KB，分块/续传都试过）。改用 Windows 内置的 **IExpress**
配合 7-Zip 的 LZMA2 压缩，同样产出单个 Setup.exe。

结构（IExpress 包内**保持扁平、不放子目录**，因为 IExpress 对子目录支持不可靠）：

```
Celechron-1.3.0-windows-x64-setup.exe
  └─ 自解压到临时目录后执行 install.cmd
       ├─ Celechron.7z    整个应用（含 CRT）
       ├─ 7z.exe / 7z.dll 解压用
       ├─ install.cmd     ASCII 入口，转调 PowerShell
       ├─ install.ps1     安装逻辑（UTF-8 BOM 保存，才能写中文）
       └─ uninstall.ps1   卸载逻辑
```

安装动作：解压到 `%LOCALAPPDATA%\Programs\Celechron`（按用户安装，不弹 UAC）→
创建开始菜单和桌面快捷方式 → 注册 `celechron://` 协议到 `HKCU\Software\Classes` →
在「应用和功能」里注册卸载项 → 启动应用。

卸载：结束进程、删快捷方式、清理注册表（协议 + 卸载项），然后由 `%TEMP%` 的
副本删除安装目录（避免脚本删自己所在目录）。**用户数据不删**，只在结束时告知位置。

实测安装结果：28 个文件 / 32.7MB，快捷方式指向正确，协议命令
`"...\Celechron.exe" "%1"` 正确，卸载项字段完整，安装后的程序能正常启动。

> 两个坑：`$env:APPDATA` 在某些执行环境下会是**空值**（`$env:LOCALAPPDATA` 却正常），
> 所以脚本里一律改用 `[Environment]::GetFolderPath()` 取目录，它走 Shell API 不受影响。
> 另外 `.ps1` 要写中文必须存成 **UTF-8 带 BOM**，否则 PowerShell 5.1 按 ANSI 读会乱码
> 甚至报语法错误。

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
（但数据落盘位置有问题，见第七节第 2 条。）

### 7. exe 元信息

`windows/runner/Runner.rc` 原本还是 Flutter 模板占位值（`CompanyName = org.cc`、
`ProductName = celechron`、`FileDescription = celechron`）。已对齐为
`Celechron` / `Celechron - 课程表与学业助手`，翻译代码页从 1252 改成 1200(Unicode)
以支持中文。模板里本来就有 `#pragma code_page(65001)`，所以 `.rc` 写中文不会乱码。

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

## 七、尚未完成 / 已知限制

1. **代码签名只签了「自签」，SmartScreen 仍会拦。** 已新增三个签名脚本：
   - `tool/sign.ps1` —— Authenticode 通用签名工具（找 signtool.exe、RFC3161 时间戳、签后立即校验）
   - `tool/make_test_cert.ps1` —— 生成 5 年有效的自签代码签名证（OpenSSL 风格，绑当前 Windows 账户）
   - `tool/sign_dist.ps1` —— 给 dist 里的 PE 和安装器批量签名，没证书时不阻塞构建

   `package.py` / `make_installer.py` 已经在最后一步自动调用 `sign_dist.ps1`。

   **自签 ≠ 真证。** 微软的 SmartScreen 不会因为「有签名」就放行，自签证和没签名一样拦。
   真正免拦要靠「文件哈希信誉」—— 同一个发布者标识下大量被正常下载运行后才会慢慢放开，
   这个过程数周到数月不等，且 2024 年后 EV 证书也不再有「立即信誉」特权。

   **不花钱的实际缓解办法**（详见第八节）：
   - GitHub Releases 分发：README 写清楚「点更多信息 → 仍要运行」是已知步骤
   - 浙大校内分发：放进 ZJU 软件镜像或校内网盘，受众都是会点忽略的用户
   - SignPath.io OSS 版：开源软件免费 EV 级签名云服务，但需申请审批
   - Microsoft Store 个人开发者：一次性 $19 注册，重新签名 = 完全免拦

2. **应用数据落在「文档」根目录。** `Hive.initFlutter()` 在桌面端解析到
   `getApplicationDocumentsDirectory()`，即 `C:\Users\<用户>\Documents\`，
   于是 7 个 `.hive` 文件直接摊在文档根目录下。Android/iOS 上这个目录是应用私有的，
   原作者不必在意；Windows 上就显得脏。
   **建议改法**：改用 `getApplicationSupportDirectory()`
   （`%APPDATA%\Celechron\Celechron`）并做一次性迁移。
   本次没动 —— 它会移动你已经产生的数据文件，属于需要你确认的改动。

3. **后台刷新在桌面端是应用内定时器。** 应用没运行就不会刷新，成绩推送 /
   DDL 提醒只在程序开着时生效。移动端是系统级调度，语义不同，属平台能力差异。

4. **`jni` 被注册进 Windows 的 FFI 插件列表。** 来自 `path_provider_android`
   的传递依赖，但自身声明了 `windows: ffiPlugin: true`。本机有 JDK，所以
   `dartjni.dll` 正常编出；没有 JDK 时 `find_package(JNI)` 不带 `REQUIRED`，
   会优雅跳过，不影响构建。

5. **验证覆盖偏薄。** 只做了启动 / 登录 / 布局 / 后台让行的冒烟验证。
   以下三条改动过的路径没有被真正触发，需要覆盖到具体场景才能确认：
   - 通知实际弹出（插件 17 → 22 的 API 变更）
   - iCal 导出的系统分享面板（`share_plus` 的 Windows 实现）
   - `celechron://ecardpaypage` 深链跳转（协议已注册，但未验证跳转）

---

## 八、代码签名：不花钱能做什么

| 方案 | 成本 | SmartScreen | 适用 |
|---|---|---|---|
| 不签名（当前） | ¥0 | 警告「未知发布者」 | 内部/小范围 |
| 自签 + sign.ps1 | ¥0 | 同上，自签不算数 | 满足 GPO「必须签」之类策略 |
| GitHub Releases + README 引导 | ¥0 | 同上，但用户知道点「更多信息 → 仍要运行」 | 开源分发 |
| 浙大校内网盘 / 镜像 | ¥0 | 同上 | 校内受众 |
| SignPath.io OSS | ¥0 | 走真实 EV 但需审批 | 开源软件可申请 |
| Microsoft Partner 个人账号 | $19 一次性 | **完全不警告**（微软重签） | 长期稳定分发首选 |

### 现状

`tool/sign.ps1` + `make_test_cert.ps1` 已经能跑通。本机实测：用 `New-SelfSignedCertificate`
生成 5 年自签证，再签名一个最小 PE，signtool verify /pa /v 能正确显示：

```
Issued to: PCelechron Dev Signing (TEST ONLY, not for distribution)
Issued by: PCelechron Dev Signing (TEST ONLY, not for distribution)
Expires:   Wed Sep 17 10:58:02 2031
SHA1 hash: B54C5DACB097F22F04D491942410614520396B25
The signature is timestamped: Thu Sep 17 11:00:25 2026
Timestamp Verified by: DigiCert Assured ID Root CA
```

自签带来的好处：
- 文件右键 → 属性 → 「数字签名」标签里有内容可看；
- 企业环境要求「二进制必须签」类 GPO 不再卡；
- 时间戳服务可用 DigiCert（默认）/ Sectigo / GlobalSign 的 RFC3161 地址，证书过期签名也有效。

自签解决不了的：
- SmartScreen 拦截 —— 微软官方明确说「Self-signed Certificate 跟 No signature 一个待遇」。

### 推荐路线（按工作量从小到大）

1. **先用自签跑起来**：跑 `make_test_cert.ps1`，后续 `package.py` 会自动签。
   - 投入：0
   - 用户体验：SmartScreen 警告 + 文件有签名
2. **改走 GitHub Releases**：在 README 里加一段「首次启动会被 SmartScreen 拦 → 点更多信息 → 仍要运行」的说明，把这个当成「产品教程」的一部分。
   - 投入：半小时改 README
   - 用户体验：同上，但用户预期已对齐
3. **SignPath.io OSS 申请**：填表说明 PCelechron 是 GPL 开源、学生工具，等 1-2 周审批。批下来后他们提供 EV 级云签名服务。
   - 投入：1-2 周等审批
   - 用户体验：**完全不警告**（前提是装机量够大让信誉积累）
4. **Microsoft Store 个人开发者账号**：注册一次 $19，提交 PCelechron 给微软审核。审核通过后用户从 Store 安装，**永远不会有 SmartScreen 警告**（微软会用他们的证书重新签）。
   - 投入：注册 $19 + 提交审核 1-2 周
   - 用户体验：用户从开始菜单「应用」里启动，完全原生

### 拿到真证后怎么接

脚本已经设计成兼容真证。买证后只要：

1. 证书装入 Windows 个人证书库（一般是 p12/pfx 双击导入，选「个人」）；
2. 跑 `tool/sign_dist.ps1` —— 自动按 Code Signing EKU 挑证书；
3. 想强制用某张：`powershell tool/sign_dist.ps1 -Subject 'CN=你的公司名'`。

如果证书配了硬件 UKey（多数 OV/EV 都强制要求），需要先把 UKey 厂商驱动装好，
signtool 会通过 Windows CSP 自动访问。私钥导不出是常态，不是 bug。

### 长期不签名的兜底措辞（参考）

```
首次运行若弹出 SmartScreen 提示，是因为本软件未在微软商店上架（需一次性 $19 注册费），
非恶意软件。选「更多信息 → 仍要运行」即可。
```
