import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 슬롯 조회(명세 No 16) — **어떤 요청이 나가고, 실패를 어떻게 읽는가.**
///
/// ## ⚠️ 신청용 에러 매핑을 그대로 쓰지 않는다
///
/// `HttpMatchRepository.exceptionOf`는 404를 `nothingToCancel`로 묶는다.
/// 취소에만 맞는 해석이라, 조회에 그대로 쓰면 목록을 못 받은 사람에게
/// **"취소할 활성 신청이 없어요"**가 뜬다.
void main() {
  late _RecordingAdapter api;

  Future<HttpMatchRepository> repository({int status = 200}) async {
    api = _RecordingAdapter(status: status);
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
      FakeAuthRepository(latency: Duration.zero),
    );
  }

  test('16번은 거리를 쿼리로 보낸다', () async {
    final repo = await repository();
    api.body = {'slots': <Object>[]};

    await repo.slots(distance: TargetDistance.km5);

    expect(api.request?.path, '/api/v1/running-matches/slots');
    expect(api.request?.queryParameters['targetDistanceMeters'], 5000);
  });

  test('⚠️ date는 보내지 않는다 — 오늘뿐이다', () async {
    // 보내면 형식이 틀렸을 때 400을 자초한다. 생략하면 서버가 오늘로 읽는다.
    final repo = await repository();
    api.body = {'slots': <Object>[]};

    await repo.slots(distance: TargetDistance.km3);

    expect(api.request?.queryParameters.containsKey('date'), isFalse);
  });

  test('Authorization을 붙인다', () async {
    final repo = await repository();
    api.body = {'slots': <Object>[]};

    await repo.slots(distance: TargetDistance.km3);

    expect(api.request?.headers['Authorization'], 'Bearer a-1');
  });

  test('받은 목록을 그대로 돌려준다', () async {
    final repo = await repository();
    api.body = {
      'slots': [
        {
          'scheduledStartAt': '2026-07-25T18:30:00',
          'waitingCount': 3,
          'selectable': true,
        },
      ],
    };

    final slots = await repo.slots(distance: TargetDistance.km10);

    expect(slots, hasLength(1));
    expect(slots.single.waitingCount, 3);
  });

  test('⚠️ 404를 "취소할 신청이 없다"로 읽지 않는다', () async {
    final repo = await repository(status: 404);

    await expectLater(
      repo.slots(distance: TargetDistance.km3),
      throwsA(
        isA<SlotLoadException>().having(
          (e) => e.failure,
          'failure',
          SlotLoadFailure.unknown,
        ),
      ),
    );
  });

  test('401은 세션 만료다', () async {
    // 가짜 인증은 모르는 토큰으로 갱신을 요청받으면 거절한다.
    final repo = await repository(status: 401);

    await expectLater(
      repo.slots(distance: TargetDistance.km3),
      throwsA(
        isA<SlotLoadException>().having(
          (e) => e.failure,
          'failure',
          SlotLoadFailure.sessionExpired,
        ),
      ),
    );
  });

  test('400은 invalidRequest다 — 앱 규칙이 어긋났다는 신호', () async {
    final repo = await repository(status: 400);
    api.body = {'code': 'INVALID_REQUEST'};

    await expectLater(
      repo.slots(distance: TargetDistance.km3),
      throwsA(
        isA<SlotLoadException>().having(
          (e) => e.failure,
          'failure',
          SlotLoadFailure.invalidRequest,
        ),
      ),
    );
  });

  test('못 닿으면 network다', () async {
    final repo = await repository();
    api.throwNetwork = true;

    await expectLater(
      repo.slots(distance: TargetDistance.km3),
      throwsA(
        isA<SlotLoadException>().having(
          (e) => e.failure,
          'failure',
          SlotLoadFailure.network,
        ),
      ),
    );
  });
}

/// 나간 요청을 기록하고 정해둔 몸통을 돌려준다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 200});

  final int status;
  RequestOptions? request;
  Map<String, dynamic> body = const {};
  bool throwNetwork = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (throwNetwork) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: '끊겼다',
      );
    }
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
