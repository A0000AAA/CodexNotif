# Android 发布加固与划掉停止设计

## 目标

发布 `CodexNotif v0.1.0-beta.2`，降低小米安全软件把 Android 客户端识别为 FakeApp/Spyware 的风险，并把后台生命周期调整为：应用处于前台或普通后台时继续监听，用户从最近任务划掉应用后停止监听且不自动恢复。

## 已确认边界

- Android 唯一包名保持 `org.codexnotif.mobile`。
- Android 可见版本名、Git 标签和 GitHub Release 标题都显示完整的 `v0.1.0-beta.2`。
- Android 内部版本号为 `2`；Dart 语义版本为 `0.1.0-beta.2+2`。
- 保留用户主动选择的强提醒、全屏提醒和声音能力。
- 不再追求应用被划掉后的持续监听；不开机自启、不在更新后自动启动、不自动复活。
- 移除直接申请忽略电池优化的权限和交互。
- 发布 APK 必须使用仓库外的独立发布密钥，缺少密钥时 Release 构建必须失败，不能退回 Debug 证书。
- 密钥、密码、真实服务器地址、邮箱配置、日志和本地路径不得提交或上传。

## 生命周期设计

前台服务只承担用户明确开启的 QQ IMAP 监听。`ForegroundTaskOptions` 固定使用：

- `autoRunOnBoot: false`
- `autoRunOnMyPackageReplaced: false`
- `allowAutoRestart: false`
- `stopWithTask: true`

应用进入普通后台时 Activity 任务仍存在，前台服务继续运行。用户从最近任务划掉应用后，Android 触发 task removed，插件按 `stopWithTask` 停止服务。插件提供的开机接收器从最终 Manifest 移除，避免系统重启或包更新后恢复监听。

## 权限设计

移除 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 和开机接收器带来的 `RECEIVE_BOOT_COMPLETED`。保留以下核心功能所需能力：网络、前台服务、通知、振动、WakeLock，以及只用于用户主动开启“强提醒”的全屏通知。

全屏提醒仍需用户在系统设置中明确授权；普通通知不使用全屏能力。应用不申请短信、联系人、通话记录、定位、相机、麦克风或外部文件读取权限。

## 身份与签名设计

Gradle 从以下环境变量加载正式签名：

- `CODEXNOTIF_ANDROID_KEYSTORE`
- `CODEXNOTIF_ANDROID_STORE_PASSWORD`
- `CODEXNOTIF_ANDROID_KEY_ALIAS`
- `CODEXNOTIF_ANDROID_KEY_PASSWORD`

仅在四项均有效时配置 Release signingConfig。任何 Release 任务缺少配置都立即报错。密钥保存在仓库外并单独备份；仓库继续忽略 `*.jks`、`*.keystore` 和 `key.properties`。

发布证书使用不含个人信息的主体名称。生成后的 APK 必须通过 `apksigner verify --verbose --print-certs`，证书不得包含 `Android Debug`。

## 版本与迁移

`pubspec.yaml` 使用 `0.1.0-beta.2+2`，Gradle 把 Android `versionName` 设置为 `v` 加 Flutter build name，因此系统显示 `v0.1.0-beta.2`。

历史测试包使用临时包名和 Debug 证书，不能作为新版升级来源。用户应安装 `org.codexnotif.mobile` 新版、重新填写 QQ 邮箱授权码和规则，确认工作正常后卸载旧包。两个包名不同，可在迁移期间短暂共存。

## 发布内容

GitHub 创建公开预发布 `v0.1.0-beta.2`，标题为 `CodexNotif v0.1.0-beta.2`。Release 资产包括 Windows x64 自包含包、Java 17 服务端包、正式签名 Android APK 和统一 SHA-256 清单。

Release 简介必须写明三端部署顺序、服务器访问密钥、Windows Codex 监听、Android QQ IMAP 配置、后台/划掉语义、旧包迁移、签名与校验方式，不得包含真实配置。

## 验证

- Flutter 全量测试和静态分析通过。
- 新增测试验证生命周期选项、Manifest 中不再含电池白名单权限和开机接收器、Gradle 不再使用 Debug 签名、版本完整显示。
- 构建 Release APK 后用 `aapt2` 核对包名、版本名、权限，用 `apksigner` 核对证书。
- 在小米真机安装后确认：后台监听继续；从最近任务划掉后进程和前台服务停止；不会自动恢复。
- 桌面端自测试、服务端 Maven 测试、仓库工作区与历史脱敏审计全部通过。
- GitHub 草稿资产回下载校验通过后再公开，公开后再匿名下载校验一次。
