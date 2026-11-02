import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/data/sse_match_stream.dart';

/// 모집 단계(매칭 방·초대 방)의 **주소와 요청 방식**을 못 박는다.
///
/// ## ⚠️ 2026-10-28, 호환 없이 바뀌었다
///
/// 백엔드가 `/running-matches`를 **남기지 않고 지웠다**(BE PR #112). 옛 주소로
/// 보내면 신청·슬롯·스트림·취소가 전부 404다. 화면에는 "네트워크 오류"로만
/// 보여서, 주소가 틀린 것인지 서버가 죽은 것인지 가릴 수가 없다.
///
/// 취소는 **주소와 방식이 함께** 바뀌었다 — `DELETE /running-matches` →
/// `POST /match-rooms/leave`. 주소만 고치고 `DELETE`로 보내면 405다.
void main() {
  late _RecordingAdapter api;

  Future<HttpMatchRepository> repository({
    int status = 200,
    Map<String, dynamic> body = const {},
  }) async {
    api = _RecordingAdapter(status: status)..body = body;
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return HttpMatchRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = api,
      store,
      TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
    );
  }

  test('신청은 POST /api/v1/match-rooms', () async {
    final repo = await repository(
      status: 201,
      body: const {'runningRoomId': 7},
    );

    await repo.apply(slotRaw: '2026-10-29T07:30:00', meters: 3000);

    expect(api.request?.method, 'POST');
    expect(api.request?.path, '/api/v1/match-rooms');
  });

  test('슬롯은 GET /api/v1/match-rooms/slots', () async {
    final repo = await repository(body: const {'distances': <Object>[]});

    await repo.slots();

    expect(api.request?.method, 'GET');
    expect(api.request?.path, '/api/v1/match-rooms/slots');
  });

  test('⚠️ 취소는 POST /api/v1/match-rooms/leave — DELETE가 아니다', () async {
    // 주소만 고치고 방식을 `DELETE`로 두면 405가 돌아온다.
    final repo = await repository(status: 204);

    await repo.cancel();

    expect(api.request?.method, 'POST');
    expect(api.request?.path, '/api/v1/match-rooms/leave');
  });

  group('스트림', () {
    late HttpServer server;
    late SseMatchStream stream;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final store = InMemoryTokenStore();
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'access',
        refreshToken: 'refresh',
        isOnboarded: true,
      );
      stream = SseMatchStream(
        store,
        TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
    });

    tearDown(() => server.close(force: true));

    test('GET /api/v1/match-rooms/stream으로 붙는다', () async {
      final asked = Completer<HttpRequest>();
      server.listen((request) {
        if (!asked.isCompleted) asked.complete(request);
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
      });

      stream.connect().listen((_) {}, onError: (_) {});
      final request = await asked.future;

      expect(request.method, 'GET');
      expect(request.uri.path, '/api/v1/match-rooms/stream');

      await stream.close();
    });
  });
}

/// 나간 요청을 기록하고 정해둔 몸통을 돌려준다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 200});

  final int status;
  RequestOptions? request;
  Map<String, dynamic> body = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
