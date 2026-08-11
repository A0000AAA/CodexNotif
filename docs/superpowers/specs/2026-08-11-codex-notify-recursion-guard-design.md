# Codex 完成通知递归防护设计

## 问题

Codex Desktop 的 `notify` 命令可能是一个包装器，并通过
`--previous-notify` 携带原通知命令的 JSON 数组。如果该数组再次指向
CodexNotif 的 `--codex-notify` 模式，CodexNotif 保存并转发这个包装器后，
会形成“CodexNotif → 包装器 → CodexNotif”的递归进程链。一次主任务完成因此
被误看成许多子进程完成通知，并最终触发服务端限流。

## 目标

- 把“包装器内部最终指向当前 CodexNotif”的命令识别为已安装，避免重复安装。
- 转发旧通知程序前，移除会再次启动任意 CodexNotif `--codex-notify` 模式的
  `--previous-notify <json>` 参数，同时保留包装器自己的通知行为。
- 对普通旧通知命令、非 CodexNotif 的 `--previous-notify`、无效 JSON 保持原行为。
- 使用最多 8 层的有界解析，避免畸形或恶意嵌套导致无限递归。

## 设计

新增 `CodexNotifyCommand`，集中负责命令识别、嵌套 JSON 解析与转发命令净化。
`CodexNotifyConfiguration` 用它判断直接安装和包装安装；
`CodexNotifyForwarder` 用它生成安全命令后再启动进程。

净化规则只删除完整的 `--previous-notify` 与其后一个 JSON 参数。当嵌套命令
包含 `--codex-notify` 时删除该参数对；否则原样保留。若待转发命令本身就是
`--codex-notify` 命令，则跳过转发并记录防护日志。

## 验证

- 自测试复现实际包装器命令形状，先证明旧实现误判并透传递归参数。
- 修复后验证包装安装幂等、递归参数被删除、普通转发参数与 payload 不变。
- 运行桌面端自测试、Release 构建和仓库敏感信息检查。
