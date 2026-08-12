# Android Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 发布完整显示为 `v0.1.0-beta.2` 的正式签名 Android 客户端，并让监听在普通后台继续、从最近任务划掉后停止且不再自动恢复。

**Architecture:** `BackgroundService` 集中提供可测试的前台任务生命周期选项，Android Manifest 用合并规则移除插件的开机接收器和不再需要的权限。Gradle 仅从四个环境变量加载仓库外发布密钥，并对缺少签名的 Release 任务失败关闭。

**Tech Stack:** Flutter 3.27 / Dart 3.6、Android Gradle、Java 17、PowerShell、GitHub Releases REST API。

## Global Constraints

- 包名固定为 `org.codexnotif.mobile`。
- Android 可见版本名、Git 标签和 Release 标题必须完整显示 `v0.1.0-beta.2`。
- Dart 版本为 `0.1.0-beta.2+2`，Android `versionCode` 为 `2`。
- 普通后台继续监听；最近任务划掉后停止；不开机启动、不更新后启动、不自动复活。
- 保留用户主动授权的强提醒全屏能力。
- 发布签名私钥和密码只保存在仓库外，不得出现在 Git、日志或 Release。
- 所有发布说明只使用 `notify.example.com`、占位符和通用路径。

---

### Task 1: 前台服务生命周期

**Files:**
- Modify: `mobile/test/background_service_lifecycle_test.dart`
- Modify: `mobile/lib/services/background_service.dart`

**Interfaces:**
- Produces: `BackgroundService.createForegroundTaskOptions()` 返回唯一的 `ForegroundTaskOptions` 配置。

- [ ] **Step 1: Write the failing test**

测试调用 `BackgroundService.createForegroundTaskOptions()`，断言四个生命周期字段分别为 `false`、`false`、`false`、`true`。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/background_service_lifecycle_test.dart`

Expected: FAIL，因为该方法尚不存在或旧选项与目标不一致。

- [ ] **Step 3: Write minimal implementation**

新增静态工厂并让 `initialize()` 使用它：

```dart
static ForegroundTaskOptions createForegroundTaskOptions() =>
    ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
      allowAutoRestart: false,
      stopWithTask: true,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/background_service_lifecycle_test.dart`

Expected: PASS。

### Task 2: Manifest、版本和正式签名策略

**Files:**
- Create: `mobile/test/android_release_policy_test.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/android/app/build.gradle`
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/lib/screens/home_page.dart`
- Modify: `mobile/lib/services/background_service.dart`

**Interfaces:**
- Consumes: 四个 `CODEXNOTIF_ANDROID_*` 环境变量。
- Produces: Android 包名 `org.codexnotif.mobile`、可见版本 `v0.1.0-beta.2`、无 Debug 回退的 Release 签名。

- [ ] **Step 1: Write the failing policy test**

读取真实配置文件并断言：版本为 `0.1.0-beta.2+2`；Gradle 不含 `signingConfigs.debug` 且包含四个环境变量和 `v${flutter.versionName}`；Manifest 不含 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，并移除 `RebootReceiver`；首页不再调用电池白名单请求。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/android_release_policy_test.dart`

Expected: FAIL，指出旧版本、Debug 签名、白名单权限或接收器策略仍存在。

- [ ] **Step 3: Implement release policy**

Gradle 配置四个环境变量，仅在全部存在时创建 Release 签名；当任务名包含 `release` 且配置不完整时抛出 `GradleException`。Manifest 增加 `tools` 命名空间并通过 `tools:node="remove"` 移除 `RebootReceiver`，删除白名单权限。删除首页的白名单请求和对应服务方法。

- [ ] **Step 4: Run policy and full tests**

Run: `flutter test test/android_release_policy_test.dart test/background_service_lifecycle_test.dart`

Expected: PASS。

### Task 3: 文档、构建和真机验证

**Files:**
- Modify: `README.md`
- Modify: `mobile/README.md`（若存在）
- Modify: `THIRD_PARTY_NOTICES.md` only if dependency evidence changes.

- [ ] **Step 1: Generate repository-external signing identity**

在仓库外生成独立 PKCS12/JKS，证书主题使用 `CN=CodexNotif Release,O=CodexNotif`。密码随机生成并用 Windows 当前用户 DPAPI 加密保存，构建过程中只注入进程环境变量。

- [ ] **Step 2: Build and inspect APK**

Run: `flutter build apk --release --no-pub`

Expected: 生成正式签名 APK；`apksigner` 显示签名有效且证书不含 `Android Debug`；`aapt2` 显示包名 `org.codexnotif.mobile`、版本名 `v0.1.0-beta.2`，且没有电池白名单与开机权限。

- [ ] **Step 3: Verify on Xiaomi device**

安装新版后检查普通后台仍存在前台服务；从最近任务划掉后 `pidof org.codexnotif.mobile` 为空、服务不再运行，并等待确认不会自动恢复。

- [ ] **Step 4: Run regression and audit**

运行 Flutter 全量测试、`flutter analyze`、桌面自测试、Maven 测试、`tools/audit_public_repo.ps1 -Scope Worktree` 和 `-Scope History`，全部要求退出码 0。

### Task 4: 提交、推送与 GitHub Release

**Files:**
- Commit all tracked source, test and documentation changes.
- Do not commit APK, ZIP, keystore, DPAPI secrets, build directories or release notes staging files.

- [ ] **Step 1: Commit in Chinese**

提交设计/计划，再提交实现与测试，提交信息使用中文且不包含个人信息。

- [ ] **Step 2: Push main**

确认工作区干净、HEAD 与待发布提交一致后推送 `origin/main`。

- [ ] **Step 3: Build sanitized release assets**

生成 Windows x64 自包含 ZIP、Java 服务端 ZIP、正式签名 Android APK 和 `SHA256SUMS.txt`；解压/扫描所有资产，禁止真实服务器、账号、密钥、日志、数据库、证书私钥和本地路径。

- [ ] **Step 4: Create and verify draft release**

创建标签和草稿 `v0.1.0-beta.2`，标题 `CodexNotif v0.1.0-beta.2`。简介写清服务端、Windows、Android、迁移和划掉停止的使用方法。上传后回下载逐个核对大小和 SHA-256。

- [ ] **Step 5: Publish and anonymously verify**

草稿验证通过后公开为 prerelease；不带认证访问公开 API 和下载地址，再次核对标签、标题、资产数量和哈希。
