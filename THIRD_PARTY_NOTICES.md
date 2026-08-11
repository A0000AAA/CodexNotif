# 第三方组件通知

CodexNotif 自有代码使用 `AGPL-3.0-only`。下列第三方组件继续适用其各自许可证；复制、修改或再分发时必须同时遵守相应条款。本文件用于帮助定位许可信息，不替代原始许可证，也不构成法律意见。

## Flutter / Android 直接依赖

| 组件 | 版本 | 许可证 | 说明 |
| --- | --- | --- | --- |
| Flutter SDK | 构建环境决定 | BSD-3-Clause | 文本：`third_party/licenses/Flutter-SDK.txt` |
| `enough_mail` | 2.1.6 | MPL-2.0 | 完整清单中保留上游文本 |
| `flutter_background` | 1.3.1 | MIT | 完整清单中保留上游文本 |
| `flutter_foreground_task` | 9.2.2 派生版本 | MIT | 源码随仓库分发，保留原作者许可 |
| `flutter_local_notifications` | 19.5.0 | BSD-3-Clause | 完整清单中保留上游文本 |
| `flutter_secure_storage` | 9.2.4 | BSD-3-Clause | 完整清单中保留上游文本 |
| `flutter_lints` | 5.0.0，开发依赖 | BSD-3-Clause | 完整清单中保留上游文本 |
| `flutter_test` | SDK，开发依赖 | BSD-3-Clause | 随 Flutter SDK 许可 |

`mobile/third_party/flutter_foreground_task` 是上游 `flutter_foreground_task` 9.2.2 的修改版。公开版保留其 MIT 许可证和原版权通知；本项目的修改主要涉及 Android 前台服务心跳/恢复状态、持续提醒音频以及项目 MethodChannel 标识。修改后的文件仍需同时保留上游 MIT 通知。

包含所有传递依赖、版本、SPDX 识别结果和许可文件路径的清单见 `docs/flutter-dependency-licenses.md`；对应文本位于 `third_party/licenses/flutter/`。

## Android 构建与测试工具

| 组件 | 版本 | 许可证 | 文本 |
| --- | --- | --- | --- |
| Gradle Wrapper / Gradle | 8.3 | Apache-2.0 | `third_party/licenses/gradle/Gradle-8.3-LICENSE.txt` |
| JUnit | 4.13.2，测试依赖 | EPL-1.0 | `third_party/licenses/junit/JUnit-4.13.2-LICENSE.txt` |

Android SDK、Android Gradle Plugin、Kotlin、Java 运行时和本机安装的构建工具并不作为本仓库自有代码重新许可。构建者仍需遵守各工具发行方条款。

## 服务端 Maven 依赖

服务端直接使用 Spring Boot Web、Validation、Data JPA、Mail 和 H2；Maven 实际解析出 68 个运行时构件。每个构件的坐标、作用域、POM 许可证和 JAR 随附通知见 `docs/server-dependency-licenses.md`。从 JAR 提取的 `LICENSE`、`NOTICE`、`DEPENDENCIES` 等文件位于 `third_party/licenses/maven/`。

H2 2.3.232 的 POM 声明 MPL-2.0 与 EPL-1.0。其他构件可能在 POM 中声明一个或多个可选许可证；应以清单中的上游声明和随附文本为准。

可在 Maven 已生成运行时依赖列表后重新生成报告：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/generate_maven_license_report.ps1
```

脚本遇到未识别或缺失许可证时会失败，不会静默标记为“兼容”。

## Windows 桌面端

当前 WPF 项目没有外部 `PackageReference`，仅使用 .NET 8 和 Windows 桌面框架。构建/运行 .NET 时仍受 Microsoft 对相应 SDK 与运行时的许可条款约束。

## 资源

应用图标、启动占位图和五个内置 WAV 铃声的来源与许可见 `ASSETS.md`。它们不是从第三方铃声包、手机厂商主题或其他应用中提取的。
