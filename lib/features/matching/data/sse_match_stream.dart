import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
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
/// 필드와 빈 줄 구분자**가 전부다. dio가 이미 바이트 스트림을 주므로 그 위에
/// 40줄을 얹는 편이 의존을 하나 늘리는 것보다 가볍다. `Last-Event-ID` 재개도
/// 쓰지 않는다 — 각 이벤트가 전체 상태라 재개할 것이 없다.
class SseMatchStream implements MatchStream {
  SseMatchStream(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _path = '/api/v1/running-matches/stream';

  StreamSubscription<MatchEvent>? _subscription;
  StreamController<MatchEvent>? _controller;

  @override
  Stream<MatchEvent> connect() {
    final controller = StreamController<MatchEvent>(onCancel: close);
    _controller = controller;
    unawaited(_pump(controller));
    return controller.stream;
  }

  Future<void> _pump(StreamController<MatchEvent> controller) async {
    try {
      final stored = await _store.read();
      var token = stored.accessToken;
      if (token == null) {
        throw const MatchStreamException(MatchStreamFailure.sessionExpired);
      }

      ResponseBody body;
      try {
        body = await _open(token);
      } on DioException catch (error) {
        // 401이면 한 번만 갱신하고 다시 붙는다 — 다른 저장소와 같은 규칙이다.
        if (error.response?.statusCode != 401) rethrow;
        token = await _refreshed(stored.refreshToken);
        body = await _open(token);
      }

      _subscription = decode(body.stream).listen(
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
      controller.addError(error);
      await controller.close();
    } on DioException catch (error) {
      controller.addError(MatchStreamException(_failureOf(error)));
      await controller.close();
    }
  }

  Future<ResponseBody> _open(String accessToken) async {
    final response = await _dio.get<ResponseBody>(
      _path,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'text/event-stream',
          // 프록시가 중간에 모아서 보내면 이벤트가 늦게 도착한다.
          'Cache-Control': 'no-cache',
        },
        // 열어두는 연결이다. 받는 시간에 제한을 두면 조용할 때 끊긴다.
        receiveTimeout: Duration.zero,
      ),
    );
    final body = response.data;
    if (body == null) {
      throw const MatchStreamException(MatchStreamFailure.unknown);
    }
    return body;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  /// 바이트 스트림을 이벤트로 옮긴다. **테스트가 직접 부른다.**
  ///
  /// 빈 줄이 하나의 이벤트를 닫는다. `:`로 시작하는 줄은 프록시 유휴 타임아웃을
  /// 막는 keep-alive라 버린다.
  static Stream<MatchEvent> decode(Stream<List<int>> bytes) async* {
    final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());

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
        error.failure == AuthFailure.network
            ? MatchStreamFailure.network
            : MatchStreamFailure.sessionExpired,
      );
    }
  }

  static MatchStreamFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return MatchStreamFailure.network;
    }
    return switch (error.response?.statusCode) {
      // 본문이 없는 유일한 응답이다. 상태 코드로만 판단한다.
      404 => MatchStreamFailure.noActiveMatch,
      401 => MatchStreamFailure.sessionExpired,
      _ => MatchStreamFailure.unknown,
    };
  }

  static DateTime? _dateOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static int? _intOrNull(Object? value) => value is int ? value : null;

  static String? _stringOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value;
  }
}
