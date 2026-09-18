# AGENTS.md

> PCelechron 项目的 AI 协作守则。被 OpenCode / Codex / Cursor / Devin /
> Gemini CLI / Aider / Claude Code 等所有读取 `AGENTS.md` 的 coding agent
> 在冷启动时加载。后续更新请直接改本文件并随主分支一起 commit。

## 项目速览

- **PCelechron** 是浙大教务 App [Celechron/Celechron](https://github.com/Celechron/Celechron) 的
  PC 桌面端 Flutter 分支。
- 上游基线 `94e0ca6`，本仓库在此基础上移植 Windows / macOS / Linux。
- 主分支：`flaviohor/main`（上游同步）；**所有改动只动 `neo`，不要 push 到 main**。
- 当前维护者：Flaviohor（Windows x86/x64）、Kepler16f（Windows arm64、Mac、Linux）。
- Flutter 3.47.x / Dart 3.13.x；`path_provider` 2.1.6 / `hive` 2.2.3 / `hive_flutter` 1.1.0。
- 详见 [`WINDOWS_PORT.md`](./WINDOWS_PORT.md) —— 这是 PC 移植细节的权威文档。

## 关键守则

### 1. 所有改动只在 `neo` 分支进行

main 是上游同步的镜像，不要在上面提交。push / open PR / 触发 workflow 全部走 neo。

### 2. 每次触发 GitHub Actions 构建前，先问用户

**强制规则。** 任何「跑 `gh workflow run`」、「点 Actions 的 Run workflow」、「push 触发自动构建」之前，
**必须先用 `ask_user` 工具**确认两件事：

1. **目标架构（多选）**：`windows-x64` / `windows-arm64` / `windows-x86` /
   `macos` / `linux-x64` / `linux-arm64` / `all`，用户可任意组合。
2. **版本号**（versionName）：如 `1.3.3`。若用户没明说，提示取 `pubspec.yaml`
   当前值（不带 `+1` build 号那个部分）。

只有用户答复后才能调用：

```
gh workflow run build_desktop.yml --ref neo \
  --field target_platforms=windows-x64,linux-x64 \
  --field version=1.3.3
```

`target_platforms` 是逗号分隔的架构列表；`version` 留空则 workflow 内部会
从 `pubspec.yaml` 解析默认值。详见 `.github/workflows/build_desktop.yml`
的 `workflow_dispatch.inputs` 段。

### 3. 任何 push / PR 之前先确认用户授权

- 远程仓库 `flaviohor` 已配置为 `git@github.com:Flaviohor/Celechron.git`（已迁移到
  `git@github.com:Flaviohor/Pcelechron.git`，旧 URL 自动重定向）。
- 不要 `git push --force` 到 main。
- 涉及 `windows/runner/Runner.rc` / `windows/runner/main.cpp` /
  `linux/flutter/` / `macos/Flutter/` 等自动生成文件的改动，要先用
  `flutter pub get` 重生成，再用 `git checkout HEAD -- <auto-files>` 把它们
  排除在 commit 之外。

### 4. 不要替用户花钱

参考用户 User Memory：「别买证书啊，不准花钱」。
- 不要建议购买代码签名证书（EV/OV）作为解决方案。
- SmartScreen / 公证签名等场景，优先用免费替代（GitHub Releases、SignPath.io OSS、
  Microsoft Store 个人开发者一次性 $19）。

### 5. 改 `pubspec.yaml` 的字体 / 资产声明时

字体走 `assets/fonts/`，不是 `fonts/`。当前家族名 `NotoSansSC`（不带空格），
对应文件 `assets/fonts/NotoSansSC-VF.ttf`。`tool/subset_fonts.py` 是可选
工具，未在 release pipeline 中使用 —— 字体按原样打包，不做子集化。

### 6. 改 `windows/runner/Runner.rc` 时

`VALUE "CompanyName"` / `VALUE "ProductName"` 是 path_provider + secure_storage
**寻找数据目录的依据**。改动这两个字符串会让已保存的登录凭据和缓存全部
「失踪」（每次启动要重新登录）。除非确有必要，**保持上游原值**。

### 7. 测试

- `flutter analyze` 必须 0 错误才算合格；新文件不要引入新的 warning。
- `flutter test` 当前机器（Win ARM64 + Flutter Engine hash 不匹配）跑不起来，
  不要无限重试。本地手动审查代码逻辑即可。
- 跨平台 / 集成类验证靠 `flutter build windows --debug` + GitHub Actions。

## 常用命令

```bash
# 装包（首次）
flutter pub get

# 分析
flutter analyze

# 跑本地构建
./tool/build.sh --debug      # debug 版
./tool/run.sh                # 直接跑（debug + hot reload）

# 打包
python tool/package.py         # dist/Celechron-<ver>-windows-x64-portable.zip
python tool/make_installer.py  # dist/Celechron-<ver>-windows-x64-setup.exe

# 触发 CI（务必先经用户同意 + 拿到架构 + 版本号）
gh workflow run build_desktop.yml --ref neo \
  --field target_platforms=windows-x64 \
  --field version=1.3.3
```

## 关键文件指针

| 关注点 | 路径 |
|---|---|
| Hive 路径解析 + 一次性迁移 | `lib/database/hive_paths.dart` |
| Hive 迁移测试 | `test/hive_paths_test.dart` |
| 字体子集化（可选工具） | `tool/subset_fonts.py` |
| 代码签名脚本 | `tool/sign.ps1` / `tool/sign_dist.ps1` / `tool/make_test_cert.ps1` |
| 安装器脚本（Inno Setup） | `tool/installer.iss` |
| 便携版打包 | `tool/package.py` |
| 单文件安装器 | `tool/make_installer.py` |
| CI 工作流（多架构构建） | `.github/workflows/build_desktop.yml` |
| PC 移植说明 | `WINDOWS_PORT.md` |