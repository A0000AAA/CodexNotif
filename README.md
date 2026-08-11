# CodexNotif

CodexNotif 将 Codex 主任务的完成事件转换为邮件，并由手机端按规则显示普通通知或持续响铃的强提醒。

仓库包含三个可独立构建的部分：

| 目录 | 用途 |
| --- | --- |
| `mobile/` | Flutter / Android 手机客户端 |
| `desktop/` | .NET 8 WPF 桌面客户端与 Codex notify 配置脚本 |
| `server/` | Java 17 / Spring Boot 邮件中继服务 |

完整的构建、配置、宝塔部署和端到端验证说明将在代码导入并验证后补齐。

本项目自有代码使用 [GNU Affero General Public License v3.0](LICENSE)，SPDX 标识为 `AGPL-3.0-only`。第三方组件继续受各自许可证约束。
