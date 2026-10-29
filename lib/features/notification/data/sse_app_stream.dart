import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/network/dio_client.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/version/app_version_headers.dart';
import 'package:runiverse/core/version/installed_app_version.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/notification/data/notification_dto.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';

/// 다시 붙기까지 기다리는 간격.
///
/// ## ⚠️ 즉시 재연결을 반복하면 두 기기가 서로를 밀어낸다
///
/// 같은 계정으로 같은 서버에 붙으면 **기존 연결이 끊길 수 있다.** 양쪽이 끊김을
/// 보고 바로 다시 붙으면 둘이 번갈아 서로를 쫓아내며 영원히 돈다. 간격을 두고,
/// 반복되면 늘린다.
class AppStreamBackoff {
  Duration _current = first;

  static const first = Duration(seconds: 2);

  /// 상한. 끝없이 늘리면 하루 뒤에 깨어나는 연결이 된다.
  static const max = Duration(minutes: 2);

  /// 다음에 기다릴 시간. 부를 때마다 두 배가 되고 [max]에서 멈춘다.
  Duration next() {
    final value = _current;
    final doubled = _current * 2;
    _current = doubled > max ? max : doubled;
    return value;
  }

  /// 붙었다. 다음 끊김은 처음 간격부터다.
  void reset() => _current = first;
}

/// 진짜 서버에 붙는 [AppStream].
///
/// `SseMatchStream`과 같은 방식이다 — `HttpClient` 위에 `event:`·`data:`·빈 줄
/// 만 읽는다. **`EventSource`를 쓸 수 없는 이유가 여기 있다**: 서버가
/// `Authorization`·`X-App-Version`·`X-App-Platform` 셋을 요구하는데 그쪽은
/// 임의 헤더를 실을 수 없다.
///
/// ## 매칭 스트림과 나누는 이유
///
/// 싣는 것이 다르고(알림 대 방 정보), 생명주기가 다르다 — 이쪽은 로그인한 동안
/// 늘 열려 있고 저쪽은 방에 있을 때만 열린다. 한 클래스가 둘을 맡으면 한쪽
/// 사정으로 다른 쪽을 끊는 날이 온다.
class SseAppStream implements AppStream {
  SseAppStream(this._store, this._auth, {String? baseUrl})
    : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final TokenStore _store;
  final AuthRepository _auth;
  final String _baseUrl;

  static const _path = '/api/v1/app/stream';

  /// keep-alive 간격(`:ping` 15초)의 두 배. 침묵 자체가 끊김의 신호다 —
  /// `SseMatchStream`과 같은 판단이다.
  static const _silence = Duration(seconds: 30);

  static const _cancelGrace = Duration(seconds: 1);

  StreamSubscription<AppNotification>? _subscription;
  StreamController<AppNotification>? _controller;
  HttpClient? _client;

  @override
  Stream<AppNotification> connect() {
    final controller = StreamController<AppNotification>();
    // 지난 연결의 뒷정리가 지금 연결을 닫지 않게 한다 — `SseMatchStream`이
    // 같은 함정을 적어 뒀다.
    controller.onCancel = () => _closeIfCurrent(controller);
    _controller = controller;
    unawaited(_pump(controller));
    return controller.stream;
  }

  Future<void> _closeIfCurrent(
    StreamController<AppNotification> controller,
  ) async {
    if (!identical(_controller, controller)) return;
    await close();
  }

  Future<void> _pump(StreamController<AppNotification> controller) async {
    try {
      final stored = await _store.read();
      if (controller.isClosed) return;
      var token = stored.accessToken;
      if (token == null) {
        throw const AppStreamException(AppStreamFailure.sessionExpired);
      }

      final client = HttpClient()
        // 서버가 30분(운영값)에 끊는다. 짧은 요청에 맞춘 제한을 쓰면 그보다
        // 먼저 조용할 때 끊긴다.
        ..idleTimeout = const Duration(minutes: 35)
        ..connectionTimeout = const Duration(seconds: 10);
      _client = client;

      HttpClientResponse body;
      try {
        body = await _open(client, token);
      } on AppStreamException catch (error) {
        if (error.failure != AppStreamFailure.sessionExpired) rethrow;
        token = await _refreshed(stored.refreshToken);
        if (controller.isClosed) return;
        body = await _open(client, token);
      }

      if (controller.isClosed) {
        client.close(force: true);
        return;
      }

      _subscription = decode(_watched(body)).listen(
        controller.add,
        onError: (Object error, StackTrace stack) {
          controller.addError(
            const AppStreamException(AppStreamFailure.network),
          );
          unawaited(controller.close());
        },
        onDone: () => unawaited(controller.close()),
      );
    } on AppStreamException catch (error) {
      if (controller.isClosed) return;
      controller.addError(error);
      await controller.close();
    } on IOException {
      if (controller.isClosed) return;
      controller.addError(const AppStreamException(AppStreamFailure.network));
      await controller.close();
    }
  }

  static Stream<List<int>> _watched(Stream<List<int>> bytes) => bytes.timeout(
    _silence,
    onTimeout: (sink) {
      debugPrint('[app-stream] ${_silence.inSeconds}초 동안 아무것도 오지 않았다');
      sink.addError(const AppStreamException(AppStreamFailure.network));
    },
  );

  Future<HttpClientResponse> _open(
    HttpClient client,
    String accessToken,
  ) async {
    debugPrint('[api] → GET $_path');
    final request = await client.getUrl(Uri.parse('$_baseUrl$_path'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $accessToken')
      ..set(HttpHeaders.acceptHeader, 'text/event-stream')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');

    // ⚠️ **이 경로는 두 헤더가 없으면 403으로 거절한다.** 다른 경로는 없으면
    // 그냥 통과시키는데(공통 규칙) 여기만 다르고, 버전 검사가 토큰 검사보다
    // 먼저다. 못 읽었을 때의 처리는 [failureOf]에 있다.
    AppVersionHeaders.current.forEach(request.headers.set);

    final response = await request.close();
    debugPrint('[api] ← ${response.statusCode} $_path');
    if (response.statusCode == 200) return response;

    // ⚠️ **403만 본문을 읽는다.** 코드가 여럿이라 보지 않으면 멀쩡한 앱을
    // 업데이트 화면으로 보낸다. 나머지는 몸통을 버려야 연결이 반납된다.
    Object? body;
    if (response.statusCode == 403) {
      body = await _readJson(response);
    } else {
      unawaited(response.drain<void>());
    }

    throw AppStreamException(
      failureOf(
        response.statusCode,
        body,
        versionKnown: InstalledAppVersion.current != null,
      ),
      code: body is Map ? body['code'] as String? : null,
    );
  }

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  ///
  /// ## ⚠️ [versionKnown]이 없으면 업데이트 화면으로 보내지 않는다
  ///
  /// 설치 버전을 못 읽으면 `AppVersionHeaders.current`가 **빈 맵**이라 두
  /// 헤더가 빠지고, 이 경로는 그것을 `403 APP_UPDATE_REQUIRED`로 거절한다.
  /// 그대로 믿으면 **멀쩡한 최신 앱이 영영 업데이트 화면에 갇힌다** —
  /// `installed_app_version.dart`가 "`null`을 `0.0.0`으로 눌러선 안 된다"고
  /// 적어 둔 것과 같은 함정이다.
  ///
  /// 그래서 버전을 모르는 채 받은 403은 [AppStreamFailure.unknown]으로 둔다.
  /// 알림을 포기하는 것이 앱을 못 쓰게 만드는 것보다 낫다.
  ///
  /// ⚠️ **404는 이 경로에 없다.** 매칭 스트림의 404(수락 전 연결)와 구분한다.
  static AppStreamFailure failureOf(
    int? statusCode,
    Object? body, {
    required bool versionKnown,
  }) {
    if (statusCode == 401) return AppStreamFailure.sessionExpired;
    if (statusCode == 403) {
      if (!isUpdateRequired(403, body)) return AppStreamFailure.unknown;
      return versionKnown
          ? AppStreamFailure.updateRequired
          : AppStreamFailure.unknown;
    }
    // 5xx는 사용자가 할 일이 네트워크 실패와 같다 — 다시 붙어 보는 것뿐이다.
    if (statusCode != null && statusCode >= 500) {
      return AppStreamFailure.network;
    }
    return AppStreamFailure.unknown;
  }

  static Future<Object?> _readJson(HttpClientResponse response) async {
    try {
      return jsonDecode(await response.transform(utf8.decoder).join());
    } on Object catch (error) {
      debugPrint('[app-stream] 오류 본문을 읽지 못했다 · ${error.runtimeType}');
      return null;
    }
  }

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const AppStreamException(AppStreamFailure.sessionExpired);
    }
    try {
      final tokens = await _auth.refresh(refreshToken);
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      throw AppStreamException(
        error.failure == AuthFailure.sessionExpired
            ? AppStreamFailure.sessionExpired
            : AppStreamFailure.network,
      );
    }
  }

  /// 바이트를 알림으로 옮긴다. **테스트가 직접 부른다.**
  ///
  /// `:`로 시작하는 줄은 주석이라 버린다 — 연결 직후의 `:connected`와 15초마다
  /// 오는 `:ping`이 그것이다. **알림으로 세면 배지가 혼자 올라간다.**
  static Stream<AppNotification> decode(Stream<List<int>> bytes) async* {
    final lines = bytes
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? name;
    final data = StringBuffer();

    await for (final line in lines) {
      if (line.isEmpty) {
        final one = eventOf(name, data.toString());
        name = null;
        data.clear();
        if (one != null) yield one;
        continue;
      }
      if (line.startsWith(':')) continue;

      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final field = line.substring(0, colon);
      var value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      if (field == 'event') {
        debugPrint('[app-stream] < $value');
        name = value;
      } else if (field == 'data') {
        if (data.isNotEmpty) data.write('\n');
        data.write(value);
      }
    }
  }

  /// 한 이벤트를 알림으로 읽는다. **테스트가 직접 부른다.**
  static AppNotification? eventOf(String? name, String raw) {
    if (name == null || raw.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      debugPrint('[app-stream] 해석하지 못한 이벤트를 버렸다 · $name');
      return null;
    }
    return notificationFromEvent(name, decoded);
  }

  @override
  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    final client = _client;
    _client = null;
    final controller = _controller;
    _controller = null;

    if (subscription != null) {
      await subscription
          .cancel()
          .timeout(_cancelGrace, onTimeout: () {})
          .catchError((_) {});
    }
    client?.close(force: true);
    if (controller != null && !controller.isClosed) await controller.close();
  }
}
