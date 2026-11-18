import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/notification/domain/chat_push.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';

/// 대기방 채팅 푸시를 안드로이드 알림창에 그린다. 켜진 앱이 받은 공지도
/// 여기서 그린다([showNotice]) — 플러그인은 앱에서 한 번만 준비할 수 있다.
///
/// 방 하나에 알림 하나를 두고 줄을 쌓는다(카카오톡 단톡방처럼). 제목은 방 제목,
/// 줄마다 이름 칸과 내용이 있다.
///
/// ```
/// 19:30 - 5 km 러닝
/// (사진) 철수   곧 출발해요
/// (아이콘) 안내 영희님이 들어왔어요
/// ```
///
/// ## 두 곳에서 돈다
///
/// | 앱 | 누가 부르나 |
/// |---|---|
/// | 꺼졌거나 뒤에 있음 | FCM 백그라운드 처리기(따로 도는 isolate) |
/// | 켜져 있음 | `PushController` — 팝업 없는 채널로 |
///
/// ⚠️ **isolate끼리 메시지 이력을 나눌 수 없다.** 앞서 그린 줄은 지금 떠 있는
/// 알림에서 다시 읽고, 그리기 순서와 지운 횟수만 각 isolate의 메모리에 둔다.
///
/// ## ⚠️ 앞 줄의 사진은 다시 붙인다
///
/// 떠 있는 알림을 다시 읽으면 이름은 오지만 **비트맵 사진은 오지 않는다**
/// (플러그인 `describeIcon`이 리소스·URI만 돌려준다). 그대로 다시 그리면 새 줄이
/// 올 때마다 앞 사람들 사진이 사라진다. 그래서 사진을 사람별 파일로 캐시해 두고,
/// 사람 key로 찾아 매번 다시 붙인다.
class AndroidChatNotifications {
  AndroidChatNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<OpenedPush>.broadcast();
  Future<bool>? _ready;

  /// 그리기·지우기를 한 줄로 세운다(이 isolate 안에서).
  ///
  /// ⚠️ **떠 있는 알림을 읽고 → 한 줄 더해 → 다시 그리는** 일이라, 둘이 겹치면 같은
  /// 앞 줄을 읽은 두 번째가 첫 번째 줄을 지운다.
  ///
  /// ⚠️ **isolate끼리는 공유하지 않는다(감수).** 앱이 뒤에 있을 때 백그라운드
  /// 처리기가 사진을 받는 몇 초 사이에 앱을 열어 그 채팅에 들어가면, 백그라운드가
  /// 지운 알림을 다시 그릴 수 있다. 막으려면 백그라운드가 살아 있는 앱 본체로 넘기는
  /// 통로가 필요한데, 그 통로가 실패하면 알림이 사라져 더 나쁘다.
  static Future<void> _drawing = Future<void>.value();

  /// 방마다 지운 횟수. 사진을 받는 사이에 채팅 화면에 들어와 지웠으면, 그 뒤에
  /// 끝난 그리기는 버린다 — 이미 읽은 줄이 알림창에 되살아난다.
  static final _clears = <String, int>{};

  static const _channel = 'room_chat';
  static const _quietChannel = 'room_chat_quiet';
  static const _noticeChannel = 'notice';

  /// 공지 알림 번호. **방 번호와 겹치지 않게 음수다** — 플러그인이 이 번호를 누름
  /// 요청 코드로 쓴다([_idOf]). 겹치면 그 방 채팅 알림을 눌렀을 때 공지의 data로
  /// 열려 방으로 가지 않는다. 공지끼리는 tag로 가른다.
  static const _noticeId = -1;

  /// 러닝 위치 알림과 같은 단색 실루엣이다(구현 노트 11-4).
  static const _smallIcon = 'ic_stat_running';
  static const _noticeIcon = 'ic_chat_notice';

  static const _noticeKey = 'notice';
  static const _userKeyPrefix = 'user:';

  /// 사진 한 장을 받는 데 쓰는 전체 시간. 못 받으면 전에 받아 둔 사진을 쓰고,
  /// 그것도 없을 때만 사진 없이 그린다.
  static const _photoTimeout = Duration(seconds: 4);
  static const _photoMaxBytes = 2 * 1024 * 1024;

  /// 캐시에 저장하는 원형 사진의 한 변(px). 알림 아바타는 40dp 안팎이라
  /// xxxhdpi(×4)에서도 모자라지 않는다.
  static const _photoSize = 192;

  /// 이 앱이 그린 채팅 알림을 누른 것. **앱이 살아 있을 때만** 온다 — 꺼진 앱을
  /// 연 누름은 [launchedBy]가 준다.
  Stream<OpenedPush> get taps => _taps.stream;

  /// 플러그인을 준비한다. 처음 한 번만 실제로 부른다.
  ///
  /// [listenTaps]는 앱 쪽만 켠다. 백그라운드 isolate에는 누를 사람이 없다.
  Future<bool> start({bool listenTaps = false}) =>
      _ready ??= _initialize(listenTaps: listenTaps);

  Future<bool> _initialize({required bool listenTaps}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
        ),
        onDidReceiveNotificationResponse: listenTaps ? _onTap : null,
      );
      return true;
    } on Object catch (error) {
      debugPrint('[push] 알림 도구를 준비하지 못했다 · ${error.runtimeType}');
      return false;
    }
  }

  /// 꺼진 앱을 연 채팅 알림. 없으면 `null`이다.
  Future<OpenedPush?> launchedBy() async {
    if (!await start(listenTaps: true)) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return _openedOf(details.notificationResponse?.payload);
    } on PlatformException catch (error) {
      debugPrint('[push] 앱을 연 알림을 읽지 못했다 · ${error.code}');
      return null;
    }
  }

  /// [push]를 그 방 알림에 한 줄 더한다.
  ///
  /// ⚠️ **던지지 않는다.** 부르는 쪽이 기다리지 않는다 — 던지면 처리되지 않은
  /// 오류가 되어 Crashlytics에 치명 오류로 쌓인다.
  Future<void> show(ChatPush push, {required bool quiet}) async {
    final room = push.runningRoomId;
    final clears = _clears[room] ?? 0;
    try {
      if (!await start()) return;
      final photos = await _photoDirectory();
      // 사진은 줄 밖에서 받는다. 느린 사진 하나가 다른 방 알림까지 붙잡지 않게.
      if (push.kind == ChatPushKind.message) {
        await _savePhoto(photos, push.actorId, push.actorProfileImageUrl);
      }
      await _inLine(() async {
        if ((_clears[room] ?? 0) != clears) return;
        await _draw(push, quiet: quiet, photos: photos);
      });
    } on Object catch (error) {
      debugPrint('[push] 채팅 알림을 그리지 못했다 · ${error.runtimeType}');
    }
  }

  /// [job]을 [_drawing] 줄 끝에 세운다. 앞 일이 실패해도 줄은 이어 간다.
  static Future<void> _inLine(Future<void> Function() job) {
    final done = _drawing.then((_) => job());
    _drawing = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<void> _draw(
    ChatPush push, {
    required bool quiet,
    required Directory photos,
  }) async {
    final android = _android;
    if (android == null) return;
    final id = _idOf(push.runningRoomId);
    final tag = _tagOf(push.runningRoomId);
    final shown = await _shownStyle(android, id, tag);
    final person = switch (push.kind) {
      ChatPushKind.message => _withPhoto(
        Person(key: '$_userKeyPrefix${push.actorId}', name: push.actorNickname),
        photos,
      ),
      ChatPushKind.joined => _notice,
    };
    final style = MessagingStyleInformation(
      const Person(key: 'self', name: AppStrings.chatPushSelf),
      conversationTitle: push.title,
      // 여럿이 있는 방이다. 안 켜면 1:1로 보고 제목을 다르게 다룬다.
      groupConversation: true,
      messages: [
        for (final line in shown?.messages ?? const <Message>[])
          Message(line.text, line.timestamp, _withPhoto(line.person, photos)),
        Message(push.body, DateTime.now(), person),
      ],
    );

    await android.show(
      id: id,
      title: push.title,
      body: push.body,
      notificationDetails: AndroidNotificationDetails(
        quiet ? _quietChannel : _channel,
        quiet ? AppStrings.chatPushQuietChannel : AppStrings.chatPushChannel,
        importance: quiet ? Importance.defaultImportance : Importance.high,
        priority: quiet ? Priority.defaultPriority : Priority.high,
        styleInformation: style,
        category: AndroidNotificationCategory.message,
        // 같은 방에 줄이 더해질 때는 다시 울리지 않는다 — 첫 줄만 울린다.
        onlyAlertOnce: true,
        tag: tag,
        icon: _smallIcon,
      ),
      payload: jsonEncode(push.landingData),
    );
  }

  /// 공지를 화면 위 팝업으로 띄우고 알림창에 남긴다. 앱이 켜져 있을 때만
  /// 부른다 — 꺼졌거나 뒤에 있으면 OS가 띄운다. 던지지 않는다([show]와 같은 이유).
  ///
  /// **채팅과 달리 앱을 보고 있어도 팝업을 띄운다.** 공지는 앱 안에 다시 볼 곳이
  /// 없고(알림함·앱 스트림에 없음), 드물게 온다.
  ///
  /// 누르면 앱만 앞으로 온다. 공지에는 갈 화면이 없다.
  Future<void> showNotice({required String title, required String body}) async {
    try {
      if (!await start()) return;
      await _android?.show(
        id: _noticeId,
        title: title,
        body: body,
        notificationDetails: AndroidNotificationDetails(
          _noticeChannel,
          AppStrings.noticePushChannel,
          // ⚠️ 채널 중요도는 채널을 처음 만들 때만 정해진다. 나중에 바꿔도
          // 이미 설치한 폰에는 안 먹는다.
          importance: Importance.high,
          priority: Priority.high,
          // 서버 문구가 500자까지다. 접힌 알림은 한 줄만 보인다.
          styleInformation: BigTextStyleInformation(body),
          // 공지마다 따로 둔다. OS가 띄우는 공지도 하나씩 쌓인다.
          tag: 'notice-${DateTime.now().microsecondsSinceEpoch}',
          icon: _smallIcon,
        ),
      );
    } on Object catch (error) {
      debugPrint('[push] 공지 알림을 그리지 못했다 · ${error.runtimeType}');
    }
  }

  /// 그 방 알림을 지운다. 던지지 않는다([show]와 같은 이유).
  ///
  /// ⚠️ **지우기도 그리기와 같은 줄에 선다.** 줄 밖에서 지우면, 이미 떠 있는 알림을
  /// 읽던 그리기가 지운 뒤에 끝나 알림을 되살린다.
  Future<void> clear(String runningRoomId) async {
    // 줄을 기다리는 그리기가 있으면 지금 버리게 한다.
    _clears[runningRoomId] = (_clears[runningRoomId] ?? 0) + 1;
    try {
      if (!await start()) return;
      await _inLine(
        () async => _android?.cancel(
          id: _idOf(runningRoomId),
          tag: _tagOf(runningRoomId),
        ),
      );
    } on Object catch (error) {
      debugPrint('[push] 채팅 알림을 지우지 못했다 · ${error.runtimeType}');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// 알림 번호는 **방마다 달라야 한다.**
  ///
  /// ⚠️ 플러그인이 이 번호를 누름 요청 코드로 쓴다(`PendingIntent.getActivity(…,
  /// id, …)`, tag는 안 본다). 번호가 같으면 방 둘의 알림이 떠 있을 때 앞 알림을
  /// 눌러도 뒤에 그린 방의 data로 열린다. 방 번호는 서버의 정수 ID라 그대로 쓰고,
  /// 32비트 양수 범위로 접는다.
  static int _idOf(String runningRoomId) =>
      (int.tryParse(runningRoomId) ?? runningRoomId.hashCode) & 0x7fffffff;

  static String _tagOf(String runningRoomId) => 'room-$runningRoomId';

  /// 지금 떠 있는 그 방 알림. 사용자가 밀어 지웠으면 `null`이다 — 새로 시작한다.
  static Future<MessagingStyleInformation?> _shownStyle(
    AndroidFlutterLocalNotificationsPlugin android,
    int id,
    String tag,
  ) async {
    try {
      return await android.getActiveNotificationMessagingStyle(
        id: id,
        tag: tag,
      );
    } on PlatformException catch (error) {
      // 앞 줄을 못 읽어도 새 줄은 그린다. 앞 줄이 사라질 뿐이다.
      debugPrint('[push] 떠 있는 채팅 알림을 읽지 못했다 · ${error.code}');
      return null;
    }
  }

  static const _notice = Person(
    key: _noticeKey,
    name: AppStrings.chatPushNoticeSender,
    icon: DrawableResourceAndroidIcon(_noticeIcon),
  );

  /// 사람 key로 사진을 다시 붙인다. 캐시가 없으면 사진 없이 둔다 — 안드로이드가
  /// 이름 첫 글자로 그린다.
  static Person? _withPhoto(Person? person, Directory photos) {
    final key = person?.key;
    if (person == null || key == null) return person;
    if (key == _noticeKey) return _notice;
    if (!key.startsWith(_userKeyPrefix)) return person;
    final file = _photoFile(photos, key.substring(_userKeyPrefix.length));
    return Person(
      key: key,
      name: person.name,
      icon: file.existsSync() ? BitmapFilePathAndroidIcon(file.path) : null,
    );
  }

  static Future<Directory> _photoDirectory() async {
    final cache = await getTemporaryDirectory();
    return Directory('${cache.path}/chat_push_photos').create(recursive: true);
  }

  /// 사용자 ID는 서버가 준 값이라 파일 이름에 못 쓰는 글자를 걸러 둔다.
  static File _photoFile(Directory photos, String userId) => File(
    '${photos.path}/${userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}',
  );

  /// 보낸 사람 사진을 받아 캐시한다.
  ///
  /// - 주소가 없으면 사진을 지운 사람이다 → 캐시도 지운다.
  /// - 받지 못하면(1시간 만료·망) 캐시를 그대로 둔다. 있으면 전에 받은 사진이
  ///   붙고, 없으면 사진 없이 그린다.
  static Future<void> _savePhoto(
    Directory photos,
    String userId,
    String? url,
  ) async {
    final file = _photoFile(photos, userId);
    if (url == null) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final client = HttpClient()..connectionTimeout = _photoTimeout;
    try {
      // ⚠️ **전체에 마감을 건다.** 스트림의 `timeout`은 조각 사이 간격만 잰다 —
      // 조금씩 계속 오면 알림이 수십 초 늦는다. 마감이 지나면 `finally`가 연결을
      // 끊는다.
      final downloaded = await _download(client, url).timeout(_photoTimeout);
      if (downloaded == null) return;
      final circle = await _circleOf(downloaded);
      // 받다 끊긴 파일이 사진 자리에 남지 않게, 다 만든 뒤에 바꿔 끼운다.
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(circle, flush: true);
      await partial.rename(file.path);
    } on Object catch (error) {
      debugPrint('[push] 보낸 사람 사진을 받지 못했다 · ${error.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }

  /// 사진을 받는다. 200이 아니거나 너무 크면 `null`이다.
  static Future<Uint8List?> _download(HttpClient client, String url) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      debugPrint('[push] 보낸 사람 사진을 받지 못했다 · ${response.statusCode}');
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _photoMaxBytes) {
        debugPrint('[push] 보낸 사람 사진이 너무 크다');
        return null;
      }
    }
    return bytes.takeBytes();
  }

  /// 프로필 화면처럼 원형으로 오린 PNG. 가운데를 정사각형으로 잘라 쓴다.
  ///
  /// ⚠️ **안드로이드는 알림 사람 칸의 그림을 원형으로 자르지 않는다** — 받은
  /// 그대로 사각형으로 그린다(Android 15 에뮬레이터에서 확인). 이름 첫 글자로
  /// 그리는 기본 아바타만 원형이라, 사진을 그대로 두면 한 알림에 원과 사각형이
  /// 섞인다.
  static Future<Uint8List> _circleOf(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    // 짧은 변을 알림 크기에 맞춰 줄여서 푼다. 큰 사진을 원본 크기로 풀지 않는다.
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = _photoSize / math.min(width, height);
        return ui.TargetImageSize(
          width: (width * scale).ceil(),
          height: (height * scale).ceil(),
        );
      },
    );
    final image = (await codec.getNextFrame()).image;
    final source = ui.Rect.fromCenter(
      center: ui.Offset(image.width / 2, image.height / 2),
      width: _photoSize.toDouble(),
      height: _photoSize.toDouble(),
    );
    final target = ui.Rect.fromLTWH(
      0,
      0,
      _photoSize.toDouble(),
      _photoSize.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..clipPath(ui.Path()..addOval(target))
      ..drawImageRect(
        image,
        source,
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    final circle = await recorder.endRecording().toImage(
      _photoSize,
      _photoSize,
    );
    final png = await circle.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    circle.dispose();
    // ⚠️ `buffer`는 닫지 않는다 — 코덱을 만들며 이미 닫혔다. 두 번 닫으면
    // 디버그 빌드에서 단언이 터져 사진 없이 그려진다.
    codec.dispose();
    if (png == null) throw StateError('원형 사진을 만들지 못했다');
    return png.buffer.asUint8List();
  }

  void _onTap(NotificationResponse response) {
    final opened = _openedOf(response.payload);
    if (opened != null) _taps.add(opened);
  }

  /// 알림에 실어 둔 data를 [OpenedPush]로 되돌린다.
  ///
  /// `messageId`는 줄 번호로 만든다. FCM 누름과 같은 방식으로 같은 누름을 거른다.
  static OpenedPush? _openedOf(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, Object?>) return null;
      return OpenedPush(messageId: 'chat-${data['chatId']}', data: data);
    } on FormatException {
      return null;
    }
  }
}
