class ImapMailboxOption {
  const ImapMailboxOption({
    required this.path,
    required this.displayName,
    required this.isInbox,
  });

  final String path;
  final String displayName;
  final bool isInbox;
}
