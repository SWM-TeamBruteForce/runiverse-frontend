import 'package:runiverse/features/notification/domain/chat_push.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// 푸시 SDK(FCM)에 닿는 문.
///
/// 화면과 provider는 이것만 안다. 진짜(`FirebasePushMessaging`)는 플랫폼 채널을
/// 부르므로 `main.dart`가 끼운다 — 기본값은 [NoopPushMessaging]이다.
abstract interface class PushMessaging {
  /// 알림 권한을 묻는다. 이미 답한 권한이면 창 없이 지금 상태를 돌려준다.
  ///
  /// **결과는 기록(GA)에만 쓴다** — 거절해도 등록은 한다(토큰은 권한과
  /// 상관없이 생긴다). 묻지 못했으면 `null`이다.
  Future<PermissionAccess?> requestPermission();

  /// 지금 FCM 등록 토큰. 아직 없거나 못 받았으면 `null`이다.
  Future<String?> token();

  /// 토큰이 처음 생기거나 바뀔 때. **앱을 켤 때마다 오지는 않는다.**
  Stream<String> get tokenRefreshes;

  /// 꺼진 앱을 연 푸시. 없으면 `null`이다. 한 번 읽으면 비워진다.
  Future<OpenedPush?> initialOpened();

  /// 뒤에 있던 앱을 연 푸시. 앱이 직접 그린 알림(채팅)을 누른 것도 여기로 온다.
  Stream<OpenedPush> get opened;

  /// **앱이 켜져 있을 때** 받은 푸시. 꺼졌거나 뒤에 있을 때 받은 것은
  /// 여기로 오지 않는다 — 그때는 진짜가 따로 그린다.
  Stream<ReceivedPush> get received;

  /// 채팅 푸시를 그 방 알림에 한 줄 더한다. **안드로이드에서만 그린다** — iOS는
  /// 서버가 알림으로 보내 OS가 띄운다.
  ///
  /// [quiet]면 화면 위로 내려오는 팝업 없이 알림창에만 쌓는다(앱이 켜져 있을 때).
  Future<void> showChat(ChatPush push, {required bool quiet});

  /// 그 방 채팅 알림을 알림창에서 지운다. 채팅 화면에 들어왔을 때 부른다.
  Future<void> clearChat(String runningRoomId);

  /// 공지를 화면 위 팝업으로 띄우고 알림창에 남긴다(앱이 켜져 있을 때). **안드로이드에서만
  /// 그린다.**
  Future<void> showNotice({required String title, required String body});

  /// 앱이 켜져 있을 때 OS가 띄우려는 알림을 어떻게 보일지 [decide]에 묻게 한다.
  ///
  /// **iOS에서만 묻는다** — iOS는 서버가 보낸 알림을 OS가 띄우고 앱은 보일 방식만
  /// 고른다. 안드로이드는 [received]를 듣는 쪽이 [showChat]·[showNotice]로 그린다.
  void decideForeground(ForegroundAlert Function(ReceivedPush push) decide);
}

/// 앱이 켜져 있을 때 받은 푸시를 어떻게 보일까.
enum ForegroundAlert {
  /// 띄우지 않는다.
  none,

  /// 화면 위로 내려오는 팝업 없이 알림창에만 쌓는다. 소리는 폰 설정을 따른다.
  quiet,

  /// 화면 위 팝업을 띄우고 알림창에 남긴다.
  banner,
}

/// 앱이 켜져 있을 때 받은 푸시 하나.
class ReceivedPush {
  const ReceivedPush({required this.data, this.title, this.body});

  final Map<String, Object?> data;

  /// 알림 블록의 제목·내용. **data만 오는 채팅 푸시에는 없다** — 공지처럼 앱이
  /// 꺼져 있으면 OS가 띄우는 푸시에만 있다.
  final String? title;
  final String? body;
}

/// 눌린 푸시 하나.
class OpenedPush {
  const OpenedPush({required this.messageId, required this.data});

  /// **같은 누름이 두 번 왔는지 이것으로 가린다.** FCM이 띄운 알림은 FCM의
  /// 메시지 ID, 앱이 그린 채팅 알림은 `chat-<chatId>`다.
  final String? messageId;

  final Map<String, Object?> data;
}

/// 아무것도 하지 않는 [PushMessaging]. 토큰이 없으니 등록도 하지 않는다.
///
/// 기본값이다 — 셸을 띄우는 위젯 테스트가 플랫폼 채널 없이 돈다.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  Future<PermissionAccess?> requestPermission() async => null;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<OpenedPush?> initialOpened() async => null;

  @override
  Stream<OpenedPush> get opened => const Stream.empty();

  @override
  Stream<ReceivedPush> get received => const Stream.empty();

  @override
  Future<void> showChat(ChatPush push, {required bool quiet}) async {}

  @override
  Future<void> clearChat(String runningRoomId) async {}

  @override
  Future<void> showNotice({
    required String title,
    required String body,
  }) async {}

  @override
  void decideForeground(ForegroundAlert Function(ReceivedPush push) decide) {}
}
