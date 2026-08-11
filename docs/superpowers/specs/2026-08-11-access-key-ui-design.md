# Access Key UI Design

## Goal

在 Windows 客户端“服务器设置”中提供遮罩访问密钥输入，让普通用户无需运行脚本即可配置 `CODEXNOTIF_ACCESS_KEY`。密钥使用 Windows DPAPI 当前用户范围加密保存，不进入普通应用配置文件，并在系统策略允许时兼容同步用户环境变量。

## User Experience

- 服务器地址下方增加 `PasswordBox`，标签为“服务器访问密钥”。
- 密钥框永远不回填真实值；留空表示保留当前安全存储中的值。
- 用户输入新值并点击现有“保存并测试”后，程序先校验不少于 32 个字符且不含空白或控制字符，再保存地址和密钥。
- 成功保存后立即清空输入框，只显示“已保存并加载”或认证结果，不显示密钥、长度或片段。
- 如果服务器尚未同步同一个值，密钥仍保存在本机，界面明确显示服务器认证失败，用户可在宝塔完成同步后再次检查。

## Storage and Data Flow

- `ServerAccessKeyPersistence` 负责校验并使用 Windows DPAPI CurrentUser 加密写入 `%LOCALAPPDATA%\CodexNotif\access-key.dat`，再尽力同步 Windows User 与当前 Process 环境变量。
- `ReadOptional` 优先读取 DPAPI 加密值，再回退读取 Process 与 User 环境变量，使界面和以后启动的通知进程都能取得同一配置，并避免旧进程环境变量覆盖刚保存的新值。
- `AppSettings`、`SettingsService` 和 `%LOCALAPPDATA%\CodexNotif\settings.json` 不增加密钥字段。
- `RelayApiClient` 继续只接收内存中的密钥，并在每个请求上添加访问密钥头。

## Failure Handling

- 无效输入在任何持久化写入前被拒绝。
- 用户环境变量写入被系统策略拒绝时自动使用 DPAPI 加密值继续运行，并在界面说明保存方式；不要求管理员权限，也不输出密钥。
- 地址保存成功但认证失败时保留用户刚保存的密钥，便于随后在宝塔同步；界面不会误报认证成功。
- “恢复默认”只恢复服务器地址来源，不删除访问密钥。

## Security Boundaries

- UI 使用遮罩输入且不回填密钥。
- 密钥不进入源代码、README 示例值、日志、异常详情、`settings.json` 或 Git 历史；DPAPI 文件只能由保存它的 Windows 用户在本机解密。
- 公网服务器地址仍必须为 HTTPS，客户端仍禁止自动重定向。
- 服务端仍通过宝塔环境变量配置完全相同的 `CODEXNOTIF_ACCESS_KEY`。

## Verification

- 自测试覆盖合法/非法密钥校验、DPAPI 加密往返、读取优先级，以及用户环境变量写入被拒绝时的回退行为。
- 桌面 Release 构建验证 XAML 名称和事件处理器可编译。
- 服务端测试、桌面自测试、脱敏审计与生成物检查在推送前全部重跑。
