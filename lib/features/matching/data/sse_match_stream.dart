import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/match_stream.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 진짜 서버에 붙는 [MatchStream].
///
/// ## 패키지를 더하지 않았다
///
/// SSE 전용 패키지가 여럿 있지만, 우리가 쓰는 부분은 **`event:`와 `data:` 두
/// 필드와 빈 줄 구분자**가 전부다. `HttpClient`가 이미 바이트 스트림을 주므로
/// 그 위에 40줄을 얹는 편이 의존을 하나 늘리는 것보다 가볍다. `Last-Event-ID`
/// 재개도 쓰지 않는다 — 각 이벤트가 전체 상태라 재개할 것이 없다.
class SseMatchStream implements MatchStream {
  SseMatchStream(this._store, this._auth, {String? baseUrl})
    : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final TokenStore _store;
  final AuthRepository _auth;

  /// 붙을 서버. 테스트만 루프백 서버를 넣는다. 앱은 빌드에 박힌 값을 쓴다.
  final String _baseUrl;

  static const _path = '/api/v1/running-matches/stream';

  StreamSubscription<MatchEvent>? _subscription;
  StreamController<MatchEvent>? _controller;

  @override
  Stream<MatchEvent> connect() {
    final controller = StreamController<MatchEvent>();
    // ⚠️ **`onCancel: close`를 그대로 걸면 안 된다.** 해지를 기다리지 않으므로
    // 이 콜백이 **다시 붙은 뒤에** 뒤늦게 올 수 있는데, 그러면 방금 연 연결을
    // 우리 손으로 닫는다 — 오류도 종료도 없이 조용해져서 30초 뒤 감시가 울리고,
    // 그 재연결이 다시 같은 일을 부른다. 자기 차례일 때만 닫는다.
    controller.onCancel = () => _closeIfCurrent(controller);
    _controller = controller;
    unawaited(_pump(controller));
    return controller.stream;
  }

  /// 그 연결이 아직 현재일 때만 닫는다.
  ///
  /// provider가 같은 인스턴스를 돌려주므로 한 객체가 여러 연결을 잇달아 맡는다.
  /// 지난 연결의 뒷정리가 지금 연결을 건드리지 않게 하는 자물쇠다.
  Future<void> _closeIfCurrent(StreamController<MatchEvent> controller) async {
    if (!identical(_controller, controller)) return;
    await close();
  }

  /// 조용히 죽은 연결을 잡아낸다.
  ///
  /// ## ⚠️ 끊김이 늘 오류로 오지 않는다
  ///
  /// 중간의 프록시·NAT가 연결을 버리면 **소켓은 열린 채로 남고 바이트만 영영
  /// 오지 않는다.** `onError`도 `onDone`도 뜨지 않아 앱은 붙어 있다고 믿는데,
  /// 실제로는 확정 통지도 인원 변동도 받지 못한다(에뮬레이터에서 3분간 무음
  /// 상태를 확인했다 — 화면은 포그라운드, 프로세스도 살아 있었다).
  ///
  /// 서버가 15초마다 `:ping`을 보내는 이유가 이것이다. **침묵 자체가 신호다** —
  /// 두 번 연속 놓치면 죽은 것으로 보고 오류를 만들어 재연결을 깨운다.
  ///
  /// 이벤트가 아니라 **바이트**로 잰다. keep-alive는 이벤트를 만들지 않으므로
  /// 이벤트로 재면 조용한 방이 죽은 것으로 오해된다.
  static Stream<List<int>> _watched(Stream<List<int>> bytes) => bytes.timeout(
    _silence,
    onTimeout: (sink) {
      debugPrint('[sse] ${_silence.inSeconds}초 동안 아무것도 오지 않았다');
      sink.addError(const MatchStreamException(MatchStreamFailure.network));
    },
  );

  /// keep-alive 간격(서버 `match-stream.keep-alive-interval` = 15초)의 두 배.
  ///
  /// **이 값이 곧 갱신이 늦는 시간의 하한이다.** 연결이 조용히 죽으면 여기까지는
  /// 아무것도 모르고, 그 뒤에야 다시 붙어 현재 상태를 받는다. 45초로 두었더니
  /// 합류·이탈이 화면에 닿기까지 50초가 걸렸다.
  ///
  /// 한 번 놓친 것(15초)으로 끊으면 잠깐 느려진 망에 매번 다시 붙는다.
  /// 두 번 놓치면 살아 있는 연결일 가능성이 낮고, 헛되이 다시 붙어도 비용은
  /// 요청 두 번이다 — 확정 통지를 놓치는 것보다 싸다.
  static const _silence = Duration(seconds: 30);

  Future<void> _pump(StreamController<MatchEvent> controller) async {
    try {
      final stored = await _store.read();
      // ⚠️ 기다리는 동안 닫혔으면 여기서 끝난다. 닫힌 컨트롤러에 넣으면 던진다.
      if (controller.isClosed) return;
      var token = stored.accessToken;
      if (token == null) {
        throw const MatchStreamException(MatchStreamFailure.sessionExpired);
      }

      final client = HttpClient()
        // 열어두는 연결이다. 짧은 요청에 맞춘 제한을 그대로 쓰면 조용할 때 끊긴다.
        ..idleTimeout = const Duration(minutes: 30)
        ..connectionTimeout = const Duration(seconds: 10);
      _client = client;

      HttpClientResponse body;
      try {
        body = await _open(client, token);
      } on MatchStreamException catch (error) {
        // 401이면 한 번만 갱신하고 다시 붙는다 — 다른 저장소와 같은 규칙이다.
        if (error.failure != MatchStreamFailure.sessionExpired) rethrow;
        token = await _refreshed(stored.refreshToken);
        if (controller.isClosed) return;
        body = await _open(client, token);
      }

      // ⚠️ **연결하는 사이에 닫혔을 수 있다.** 응답을 기다리는 동안 사용자가
      // 나가면 `close()`가 먼저 돈다. 그 뒤에 온 응답은 쓸 곳이 없고, 살려두면
      // 서버에 주인 없는 연결이 남는다.
      if (controller.isClosed) {
        client.close(force: true);
        return;
      }

      _subscription = decode(_watched(body)).listen(
        controller.add,
        onError: (Object error, StackTrace stack) {
          // 도중에 끊긴 것이다. 스스로 다시 붙지 않는다.
          controller.addError(
            const MatchStreamException(MatchStreamFailure.network),
          );
          unawaited(controller.close());
        },
        onDone: () => unawaited(controller.close()),
      );
    } on MatchStreamException catch (error) {
      // 닫힌 뒤에 끝난 요청이다. 결과는 누구의 것도 아니다.
      if (controller.isClosed) return;
      controller.addError(error);
      await controller.close();
    } on IOException {
      // 서버에 닿지 못했다. 소켓·DNS·TLS가 전부 여기로 온다.
      if (controller.isClosed) return;
      controller.addError(
        const MatchStreamException(MatchStreamFailure.network),
      );
      await controller.close();
    }
  }

  /// 이 스트림만 쓰는 클라이언트. **앱의 [Dio]를 함께 쓰지 않는다.**
  ///
  /// 연동 가이드도 SSE에는 전용 클라이언트를 두고 다시 붙을 때마다 새로
  /// 만든다. 성격이 정반대라서다 — 보통 요청은 짧고 시간 제한이 있어야 하는데
  /// 이 연결은 몇 시간을 열어둔 채 조용해도 살아 있어야 한다. 같은 풀을 쓰면
  /// 한쪽에 맞춘 설정이 다른 쪽을 끊는다.
  HttpClient? _client;

  Future<HttpClientResponse> _open(
    HttpClient client,
    String accessToken,
  ) async {
    debugPrint('[api] → GET $_path');
    final request = await client.getUrl(Uri.parse('$_baseUrl$_path'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $accessToken')
      ..set(HttpHeaders.acceptHeader, 'text/event-stream')
      // 프록시가 중간에 모아서 보내면 이벤트가 늦게 도착한다.
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');

    final response = await request.close();
    debugPrint('[api] ← ${response.statusCode} $_path');
    if (response.statusCode == 200) return response;

    // 몸통을 버려야 연결이 반납된다.
    unawaited(response.drain<void>());
    throw MatchStreamException(switch (response.statusCode) {
      // 본문이 없는 유일한 응답이다. 상태 코드로만 판단한다.
      404 => MatchStreamFailure.noActiveMatch,
      401 => MatchStreamFailure.sessionExpired,
      _ => MatchStreamFailure.unknown,
    });
  }

  @override
  Future<void> close() async {
    // 다음 연결이 이 자리를 곧바로 다시 채울 수 있다. 지금 것만 들고 간다.
    final subscription = _subscription;
    _subscription = null;
    final client = _client;
    _client = null;
    final controller = _controller;
    _controller = null;

    // ⚠️ **해지를 먼저 끝내고 소켓을 끊는다.** 순서를 바꾸면 dart:io가 아직
    // 살아 있는 내부 구독으로 "Connection closed while receiving data"를
    // 던지는데, 받을 곳이 없어 처리되지 않은 예외로 남는다 — `decode`가
    // `async*`라 해지가 한 틱 늦게 내려가서 생기는 틈이다.
    //
    // 다만 **끝없이 기다리지는 않는다.** 서버가 연결을 붙잡고 있으면 해지가
    // 늦어질 수 있고, 그동안 나가기를 누른 화면이 안 닫힌다. 상한을 넘기면
    // 지금까지처럼 강제로 끊는다.
    if (subscription != null) {
      await subscription
          .cancel()
          .timeout(_cancelGrace, onTimeout: () {})
          .catchError((_) {});
    }

    // ⚠️ **클라이언트까지 닫는다.** 소켓이 남으면 다시 붙을 때마다 서버에
    // 죽은 연결이 쌓인다. `force`가 붙어야 열려 있는 스트림도 함께 끊긴다.
    client?.close(force: true);

    if (controller != null && !controller.isClosed) await controller.close();
  }

  /// 해지를 기다려 주는 상한. 정상이면 한 틱에 끝난다.
  static const _cancelGrace = Duration(seconds: 1);

  /// 바이트 스트림을 이벤트로 옮긴다. **테스트가 직접 부른다.**
  ///
  /// 빈 줄이 하나의 이벤트를 닫는다. `:`로 시작하는 줄은 프록시 유휴 타임아웃을
  /// 막는 keep-alive라 버린다.
  static Stream<MatchEvent> decode(Stream<List<int>> bytes) async* {
    // ⚠️ `cast`를 남겨둔다. 구현체가 `Stream<Uint8List>`를 줄 때
    // `utf8.decoder`(`StreamTransformer<List<int>, String>`)에 그대로 물리면
    // 런타임에 터진다 — `StreamTransformer`는 입력 타입에 공변이 아니라서
    // 컴파일은 통과하고 첫 바이트가 들어오는 순간 죽는다.
    final lines = bytes
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? name;
    final data = StringBuffer();

    await for (final line in lines) {
      if (line.isEmpty) {
        final event = eventOf(name, data.toString());
        name = null;
        data.clear();
        if (event != null) yield event;
        continue;
      }
      if (line.startsWith(':')) continue;

      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final field = line.substring(0, colon);
      var value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      if (field == 'event') {
        // 무엇이 실제로 도착했는지 남긴다. 화면이 안 바뀔 때 "안 왔다"와
        // "왔는데 못 썼다"를 가르는 첫 단서가 이 한 줄이다.
        debugPrint('[sse] < $value');
        name = value;
      } else if (field == 'data') {
        if (data.isNotEmpty) data.write('\n');
        data.write(value);
      }
    }
  }

  /// 이벤트 하나를 만든다. **읽을 수 없으면 `null`이다.**
  ///
  /// ⚠️ 던지지 않고 버린다. 이벤트 하나가 이상하다고 스트림을 끊으면 그 뒤에
  /// 올 확정 통지까지 놓친다 — 다음 이벤트가 어차피 전체 상태를 다시 나른다.
  static MatchEvent? eventOf(String? name, String raw) {
    if (name == null || raw.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      debugPrint('[sse] 해석하지 못한 이벤트를 버렸다 · $name');
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    switch (name) {
      case 'MATCH_STARTED':
        final room = roomOf(decoded);
        return room == null ? null : MatchStarted(room);
      case 'MATCH_ROOM_UPDATED':
        final room = roomOf(decoded);
        return room == null ? null : MatchRoomUpdated(room);
      case 'RUNNING_READY':
        return readyOf(decoded);
      default:
        debugPrint('[sse] 모르는 이벤트를 버렸다 · $name');
        return null;
    }
  }

  /// 방 정보를 읽는다. **테스트가 직접 부른다.**
  static RoomInfo? roomOf(Map<String, dynamic> body) {
    final roomId = body['runningRoomId'];
    final status = RoomStatus.of(body['status']);
    final startAt = _dateOrNull(body['scheduledStartAt']);
    // 이 셋 중 하나라도 없으면 화면을 그릴 수 없다. 특히 status를 아무 값으로
    // 뭉개면 취소된 방에 사람을 묶어두거나 멀쩡한 방에서 쫓아낸다.
    if (roomId is! int || status == null || startAt == null) {
      debugPrint('[sse] 읽을 수 없는 방 정보를 버렸다');
      return null;
    }

    final players = body['players'];
    return RoomInfo(
      runningRoomId: roomId,
      status: status,
      scheduledStartAt: startAt,
      closeAt: _dateOrNull(body['closeAt']),
      targetDistanceMeters: _intOrNull(body['targetDistanceMeters']),
      teamAveragePaceSecondsPerKm: _intOrNull(
        body['teamAveragePaceSecondsPerKm'],
      ),
      players: players is List
          ? [for (final player in players) ?_playerOf(player)]
          : const [],
    );
  }

  static RoomPlayer? _playerOf(Object? wire) {
    if (wire is! Map) return null;
    final id = wire['userId'];
    final nickname = wire['nickname'];
    if (id is! String || nickname is! String) return null;

    return RoomPlayer(
      userId: id,
      nickname: nickname,
      // 탈퇴 표시가 없으면 보통 사람으로 본다. 서버가 이미 익명 처리해서
      // 주므로, 빠졌다고 해서 이름이 새지는 않는다.
      isDeleted: wire['isDeleted'] == true,
      profileImageUrl: _stringOrNull(wire['profileImageUrl']),
      introduction: _stringOrNull(wire['introduction']),
      averagePaceSecondsPerKm: _intOrNull(wire['averagePaceSecondsPerKm']),
    );
  }

  /// 시작 통지를 읽는다. **테스트가 직접 부른다.**
  static RunningReady? readyOf(Map<String, dynamic> body) {
    final roomId = body['runningRoomId'];
    final startAt = _dateOrNull(body['scheduledStartAt']);
    final startsIn = body['startsInMs'];
    if (roomId is! int || startAt == null || startsIn is! int) return null;

    return RunningReady(
      runningRoomId: roomId,
      scheduledStartAt: startAt,
      // ⚠️ 음수는 0으로 본다. 서버도 눌러 보내지만, 새면 발사 시각이
      // 시작 시각보다 앞서고 서버가 거절한다.
      startsInMs: startsIn < 0 ? 0 : startsIn,
    );
  }

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const MatchStreamException(MatchStreamFailure.sessionExpired);
    }
    try {
      final tokens = await _auth.refresh(refreshToken);
      // ⚠️ 회전된 refreshToken도 반드시 덮어쓴다. 안 하면 다음 갱신이 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      throw MatchStreamException(
        error.failure == AuthFailure.sessionExpired
            ? MatchStreamFailure.sessionExpired
            : MatchStreamFailure.network,
      );
    }
  }

  /// 서버는 시간대 없는 한국 시각을 준다. [KstTime]이 그것을 기기 시각으로
  /// 옮긴다 — 기기가 한국이 아니어도 남은 시간이 맞는다.
  static DateTime? _dateOrNull(Object? value) => KstTime.parse(value);

  static int? _intOrNull(Object? value) => value is int ? value : null;

  static String? _stringOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value;
  }
}
