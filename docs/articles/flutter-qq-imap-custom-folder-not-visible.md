# Flutter 通过 QQ IMAP 监听邮件时看不到自定义文件夹：一次完整排障记录

> 摘要：Flutter 邮件提醒应用能够正常登录 QQ IMAP，也会持续轮询，但始终检测不到被规则移动到自定义文件夹的新邮件。进一步检查发现，IMAP 只返回了 `INBOX` 等五个系统文件夹。本文记录从客户端轮询、UID、`LIST/LSUB`、中文文件夹编码一路排查到 QQ 邮箱“收取我的文件夹”开关的全过程，并给出一套更稳健的 Dart 实现思路。

## 一、问题现象

项目是一个 Flutter 编写的 Android 邮件提醒应用，通过 QQ 邮箱 IMAP 获取新邮件的发件人和主题，并在命中规则后发送本地通知。

最初看到的现象很矛盾：

- QQ IMAP 登录测试成功；
- Android 前台服务仍在运行；
- 最近检查时间持续更新；
- 根收件箱 UID 没有变化；
- QQ 邮箱网页端和官方客户端中确实存在新邮件；
- App 始终显示“没有新邮件”。

后来发现，QQ 邮箱中的收信规则会把目标邮件自动移动到一个自定义文件夹，例如“任务通知”。App 一直监听 `INBOX`，自然无法发现已经被移动走的邮件。

于是给 App 增加“监听文件夹”设置，但文件夹列表中仍然只有以下内容：

```text
INBOX
Deleted Messages
Drafts
Junk
Sent Messages
```

网页端已经创建的自定义文件夹依旧没有出现。

## 二、先证明不是后台服务停止

遇到“没有收到提醒”时，很容易直接怀疑 Android 后台保活。但在本次问题中，后台服务并不是第一根因。

可以先检查三类证据：

1. 最近一次 IMAP 检查时间是否持续变化；
2. 当前连接是否仍能完成 `NOOP`、`SELECT` 或 UID 查询；
3. 服务端最新 UID 与本地已保存 UID 是否变化。

如果检查时间持续更新，而且每次查询都正常返回，就说明轮询链路仍然工作。此时应继续确认“正在监听哪个邮箱文件夹”，而不是马上修改后台服务。

这一步很重要：**连接正常不等于监听位置正确，轮询成功也不等于能看到目标邮件。**

## 三、为什么默认的文件夹列表可能不完整

### 1. `LIST "%"` 与 `LIST "*"` 的区别

IMAP 的 `LIST` 命令支持 `%` 和 `*` 两种通配符：

- `%` 不跨越层级分隔符，通常只列出当前层级；
- `*` 可以匹配多层路径，用于递归列出邮箱树。

部分邮件库的高级接口默认只获取顶层文件夹。如果自定义文件夹位于更深层级，就可能被客户端漏掉。因此，仅调用一次普通的 `listMailboxes()` 并不能证明服务器没有其他文件夹。

更稳妥的做法是同时执行：

```text
LIST "" "*"
LSUB "" "*"
```

然后按服务器返回的完整路径合并结果。

### 2. `LSUB` 不是完整文件夹列表

`LSUB` 返回的是“已订阅文件夹”，并不等同于账户中的全部文件夹。一个自定义文件夹可能真实存在，但没有被订阅，因此只补一次 `LSUB` 仍然可能看不到它。

正确关系应当是：

- 递归 `LIST` 是主要来源；
- 递归 `LSUB` 是兼容性补充；
- 合并时使用服务器返回的精确路径去重。

## 四、中文文件夹还有一个编码陷阱

为了绕过列表缺失，我曾尝试按界面名称直接执行：

```text
SELECT "任务通知"
```

服务器返回：

```text
Folder not exist!
```

这里存在一个容易误判的问题：IMAP4rev1 的非 ASCII 文件夹名通常需要使用 Modified UTF-7 编码。把中文名称直接写进命令，不一定是有效的 IMAP 路径。

使用 `enough_mail` 时，可以按路径层级分别编码：

```dart
String encodeImapMailboxPath(String path, String separator) {
  return path
      .split(separator)
      .map((segment) => Mailbox.encode(segment, separator))
      .join(separator);
}
```

不过，修正编码后服务器仍然返回 `Folder not exist!`。这说明中文编码只是客户端兼容问题，并不是本次故障的最终根因。

## 五、真正根因：QQ 没有向 IMAP 开放“我的文件夹”

最后的关键证据是：

- 顶层 `LIST` 只有五个系统文件夹；
- 递归 `LIST "" "*"` 仍然只有这五个；
- 递归 `LSUB "" "*"` 没有补出自定义文件夹；
- 使用正确编码直接 `SELECT` 仍返回文件夹不存在；
- 同一个自定义文件夹在 QQ 网页端可以正常访问。

这表明自定义文件夹只存在于 QQ 网页端当前可见范围，尚未开放给第三方 IMAP 客户端。

QQ/腾讯邮箱提供了独立的“收取我的文件夹”选项。未开启时，即使 IMAP/SMTP 服务本身已经开启，第三方客户端也只能看到系统文件夹。

网页端的入口可能会随版本调整，一般可按以下路径寻找：

```text
QQ 邮箱网页版
  → 设置
  → 账户设置 / 安全设置 / 收发信设置
  → POP3/IMAP/SMTP 服务
  → 收取选项
  → 勾选“收取我的文件夹”
  → 保存
```

保存后需要让客户端断开并重新建立 IMAP 连接。仅刷新旧连接，服务器可能仍返回缓存的文件夹列表。

## 六、Flutter 客户端的稳健实现

### 1. 递归读取并合并文件夹

以下代码保留了核心逻辑，错误处理可以根据项目需求继续完善：

```dart
Future<List<Mailbox>> listAllMailboxes(MailClient client) async {
  final topLevel = await client.listMailboxes();
  final incoming = client.lowLevelIncomingMailClient;
  if (incoming is! ImapClient) return topLevel;

  var result = topLevel;

  try {
    final recursive = await incoming.listMailboxes(recursive: true);
    result = mergeMailboxes(result, recursive);
  } catch (_) {
    // 服务器不支持递归 LIST 时保留顶层结果。
  }

  try {
    final subscribed = await incoming.listSubscribedMailboxes(
      recursive: true,
    );
    result = mergeMailboxes(result, subscribed);
  } catch (_) {
    // LSUB 只是兼容性补充，不应影响已有 LIST 结果。
  }

  return result;
}

List<Mailbox> mergeMailboxes(
  Iterable<Mailbox> first,
  Iterable<Mailbox> second,
) {
  final byPath = <String, Mailbox>{};
  for (final mailbox in [...first, ...second]) {
    byPath.putIfAbsent(mailbox.path, () => mailbox);
  }
  return byPath.values.toList();
}
```

### 2. 不要静默显示一个“不完整列表”

如果 QQ 只返回五个常见系统文件夹，设置页应明确提示：

```text
QQ IMAP 未开放自定义文件夹。
请先在 QQ 邮箱网页版的“收取选项”中开启“收取我的文件夹”。
```

这比只展示五个选项更合理。否则用户会认为 App 读取失败，或者以为自己没有创建文件夹。

### 3. 手动输入只能作为兼容入口

可以提供“手动指定文件夹”，但保存前必须实际执行 `SELECT`：

```dart
Future<Mailbox> validateManualMailbox(
  ImapClient client,
  String displayPath,
) async {
  final separator = client.serverInfo.pathSeparator ?? '/';
  final encodedPath = encodeImapMailboxPath(displayPath.trim(), separator);
  return client.selectMailboxByPath(encodedPath);
}
```

验证失败时不能保存，更不能悄悄回退后仍显示为自定义文件夹。需要把服务端错误明确展示给用户。

需要注意：手动输入无法突破服务端权限。如果 QQ 没有开放“我的文件夹”，输入完全正确的名称也会失败。

### 4. 按账户、文件夹和 UIDVALIDITY 隔离游标

切换监听文件夹后，不能继续共用 `INBOX` 的 UID。建议把游标键设计为：

```text
账户 + 文件夹完整路径 + UIDVALIDITY
```

首次选择新文件夹时，可以把该文件夹当前最新 UID 作为初始值，避免把历史邮件全部当作新邮件提醒。以后只获取：

```text
lastSeenUid + 1 : *
```

只有在本地通知成功后才提交新 UID，这样通知失败的邮件仍可在下次轮询中重试。

### 5. 文件夹失效时安全回退

自定义文件夹可能被用户改名或删除。后台重新连接时如果选择失败，应当：

1. 回退到 `INBOX`；
2. 清除已失效的文件夹配置；
3. 在 App 和前台服务通知中显示回退原因；
4. 不把临时网络错误误判为文件夹已删除。

只有在连接仍然有效、且服务器明确拒绝目标文件夹时，才适合执行回退。

## 七、建议的验证流程

完成设置和代码修改后，可以按以下顺序验证：

1. 在 QQ 网页端开启“收取我的文件夹”并保存；
2. 完全断开旧 IMAP 连接，再重新登录；
3. 执行递归 `LIST`，确认返回自定义文件夹的完整路径；
4. 在 App 中选择该文件夹；
5. 确认状态栏显示正在监听正确的文件夹；
6. 发送一封新的测试邮件，并让 QQ 规则把它移动到目标文件夹；
7. 确认该文件夹 UID 增加；
8. 确认 App 捕获邮件并显示通知；
9. 再发送一封测试邮件，确认游标提交后不会重复提醒；
10. 临时改名或删除文件夹，验证 App 是否提示并回退 `INBOX`。

测试时应一次只改变一个变量，不要同时修改邮箱规则、App 规则、文件夹和 Android 后台权限，否则很难判断究竟是哪一步生效。

## 八、总结

这次问题表面上是“Flutter 收不到邮件”，实际包含了四层不同问题：

1. 邮件已经被规则移出 `INBOX`；
2. 普通 `LIST` 可能只返回顶层目录；
3. 中文 IMAP 文件夹名涉及 Modified UTF-7；
4. QQ 服务端没有向 IMAP 开放自定义文件夹。

最容易踩的坑，是看到登录成功和轮询成功后，就认定 IMAP 没问题。实际上，邮件监听还必须确认服务器是否向当前连接公开了目标文件夹。

以后再遇到类似问题，可以先记住一句话：

> 先确认邮件实际落在哪个文件夹，再确认这个文件夹是否真的出现在 IMAP `LIST "" "*"` 的结果中。

## 参考资料

- [RFC 3501：IMAP4rev1](https://datatracker.ietf.org/doc/rfc3501)
- [RFC 9051：IMAP4rev2 中 LIST 通配符说明](https://datatracker.ietf.org/doc/html/rfc9051)
- [腾讯邮箱关于“收取我的文件夹”的说明](https://www.qqbizmail.com/help/568.html)

## CSDN 发布建议

- 推荐标题：`Flutter 通过 QQ IMAP 监听邮件时看不到自定义文件夹：从 LIST/LSUB 到“收取我的文件夹”`
- 推荐摘要：`记录 Flutter 邮件提醒应用无法读取 QQ 自定义文件夹的排查过程，涵盖 IMAP LIST/LSUB、递归目录、Modified UTF-7、UID 游标和 QQ 收取选项。`
- 推荐标签：`Flutter`、`Dart`、`IMAP`、`QQ邮箱`、`Android`
