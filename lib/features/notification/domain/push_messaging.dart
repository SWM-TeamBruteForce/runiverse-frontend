/// 푸시 SDK(FCM)에 닿는 문.
///
/// 화면과 provider는 이것만 안다. 진짜(`FirebasePushMessaging`)는 플랫폼 채널을
/// 부르므로 `main.dart`가 끼운다 — 기본값은 [NoopPushMessaging]이다.
abstract interface class PushMessaging {
  /// 알림 권한을 묻는다. **결과는 보지 않는다** — 거절해도 등록은 한다(토큰은
  /// 권한과 상관없이 생긴다). 이미 답한 권한이면 창 없이 끝난다.
  Future<void> requestPermission();

  /// 지금 FCM 등록 토큰. 아직 없거나 못 받았으면 `null`이다.
  Future<String?> token();

  /// 토큰이 처음 생기거나 바뀔 때. **앱을 켤 때마다 오지는 않는다.**
  Stream<String> get tokenRefreshes;

  /// 꺼진 앱을 연 푸시. 없으면 `null`이다. 한 번 읽으면 비워진다.
  Future<OpenedPush?> initialOpened();

  /// 뒤에 있던 앱을 연 푸시.
  Stream<OpenedPush> get opened;
}

/// 눌린 푸시 하나.
class OpenedPush {
  const OpenedPush({required this.messageId, required this.data});

  /// FCM이 메시지마다 붙이는 고유 값. **같은 누름이 두 번 왔는지 이것으로 가린다.**
  final String? messageId;

  final Map<String, Object?> data;
}

/// 아무것도 하지 않는 [PushMessaging]. 토큰이 없으니 등록도 하지 않는다.
///
/// 기본값이다 — 셸을 띄우는 위젯 테스트가 플랫폼 채널 없이 돈다.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<OpenedPush?> initialOpened() async => null;

  @override
  Stream<OpenedPush> get opened => const Stream.empty();
}
