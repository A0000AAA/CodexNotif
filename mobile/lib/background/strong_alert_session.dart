import '../models/strong_alert.dart';

StrongAlert mergeStrongAlert(StrongAlert? active, StrongAlert latest) {
  if (active == null) return latest.copyWith(count: 1);
  return latest.copyWith(
    notificationId: active.notificationId,
    sessionToken: active.sessionToken,
    soundUri: active.soundUri,
    count: active.count + 1,
  );
}
