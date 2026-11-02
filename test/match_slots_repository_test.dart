import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';

/// 슬롯 조회(명세 No 16) — **어떤 요청이 나가고, 실패를 어떻게 읽는가.**
///
/// ## ⚠️ 2026-10-26부터 쿼리가 없다
///
/// 전에는 거리를 필수로 보내 그 거리의 시간대만 받았다. 이제 **아무것도 보내지
/// 않고 모든 거리 × 모든 시간대를 한 번에** 받는다. 쿼리가 하나라도 남아 있으면
/// 명세가 받지 않는 요청이 된다.
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
      TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
    );
  }

  test('⚠️ 16번은 쿼리를 보내지 않는다', () async {
    // 거리는 더 이상 요청에 들어가지 않는다(명세가 받지 않는다). `date`도
    // 보내지 않는다 — 오늘뿐이고, 보내면 형식이 틀렸을 때 400을 자초한다.
    final repo = await repository();
    api.body = {'distances': <Object>[]};

    await repo.slots();

    expect(api.request?.path, '/api/v1/match-rooms/slots');
    expect(api.request?.queryParameters, isEmpty);
  });

  test('Authorization을 붙인다', () async {
    final repo = await repository();
    api.body = {'distances': <Object>[]};

    await repo.slots();

    expect(api.request?.headers['Authorization'], 'Bearer a-1');
  });

  test('받은 판을 그대로 돌려준다', () async {
    final repo = await repository();
    api.body = {
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': 3,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 5000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': 7,
              'selectable': true,
            },
          ],
        },
      ],
    };

    final board = await repo.slots();

    expect(board.distances.map((d) => d.meters), [3000, 5000]);
    expect(board.times.single.waitingTotal, 10, reason: '두 거리를 더한다');
    expect(board.at(raw: '2026-07-25T18:30:00', meters: 5000)?.waitingCount, 7);
  });

  test('⚠️ 404를 "취소할 신청이 없다"로 읽지 않는다', () async {
    final repo = await repository(status: 404);

    await expectLater(
      repo.slots(),
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
      repo.slots(),
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
    // 날짜 형식일 때만 나는데 앱이 `date`를 안 보내므로 정상 경로에서는 안
    // 나온다. 나오면 앱 규칙이 서버와 어긋났다는 신호다.
    final repo = await repository(status: 400);
    api.body = {'code': 'INVALID_REQUEST'};

    await expectLater(
      repo.slots(),
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
      repo.slots(),
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
