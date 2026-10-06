import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/settings/data/http_settings_repository.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';

/// 회원 탈퇴 — `DELETE /api/v1/users/me` (명세 57번).
///
/// ## ⚠️ 이 그물이 없었다
///
/// 탈퇴는 **화면부터 저장소까지 다 만들어져 있었는데 가짜로 돌려져 있었다**
/// (`StagedSettingsRepository`). 위젯 테스트는 그 가짜만 지나서, 진짜로 나가는
/// 요청이 어떻게 생겼는지 **한 번도 확인된 적이 없다.** 카카오 로그인에서
/// 401 이름이 조용히 어긋났던 것과 같은 자리다.
///
/// 서버를 띄우지 않고 dio 어댑터만 갈아끼워 실제로 나가는 요청을 본다.
void main() {
  late _Recorder api;

  Future<HttpSettingsRepository> repository({
    List<_Reply> replies = const [_Reply(204)],
  }) async {
    api = _Recorder(replies);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    final auth = FakeAuthRepository(latency: Duration.zero)
      // 401을 받으면 이 토큰으로 갱신을 시도한다. 심어 두지 않으면 갱신이
      // 만료로 끝나서 **재시도 경로를 못 본다.**
      ..seedSession(accessToken: 'a-1', refreshToken: 'r-1');

    return HttpSettingsRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = api,
      store,
      auth,
    );
  }

  test('DELETE로 /api/v1/users/me에 나간다', () async {
    final repo = await repository();

    await repo.withdraw();

    expect(api.requests.single.method, 'DELETE');
    expect(api.requests.single.path, '/api/v1/users/me');
  });

  test('요청 본문이 없다', () async {
    final repo = await repository();

    await repo.withdraw();

    // 명세: "요청 본문 없음". 빈 맵이라도 실으면 서버 설정에 따라 400이 난다.
    expect(api.requests.single.body, isNull);
  });

  test('토큰을 싣는다', () async {
    final repo = await repository();

    await repo.withdraw();

    expect(api.requests.single.headers['Authorization'], 'Bearer a-1');
  });

  test('⚠️ 204 빈 응답을 성공으로 읽는다', () async {
    // 성공은 **몸통이 없다.** 몸통을 파싱하려 들면 여기서 죽는데,
    // 그 증상은 "탈퇴했는데 실패했다고 뜬다"로 나타난다 — 계정은 이미 없다.
    final repo = await repository(replies: [const _Reply(204)]);

    await expectLater(repo.withdraw(), completes);
  });

  test('503이면 server로 전해진다', () async {
    // 명세: `ACCOUNT_DELETION_UNAVAILABLE` — 진행 중인 러닝을 정리하다 난
    // 일시적 오류다. **탈퇴는 처리되지 않았으므로** 다시 시도하게 해야 한다.
    final repo = await repository(
      replies: [
        const _Reply(503, body: '{"code":"ACCOUNT_DELETION_UNAVAILABLE"}'),
      ],
    );

    await expectLater(
      repo.withdraw(),
      throwsA(
        isA<SettingsException>().having(
          (it) => it.failure,
          'failure',
          SettingsFailure.server,
        ),
      ),
    );
  });

  test('⚠️ 401이면 갱신하고 한 번만 다시 보낸다', () async {
    final repo = await repository(
      replies: [const _Reply(401), const _Reply(204)],
    );

    await repo.withdraw();

    // 두 번 나갔고, **두 번째는 갱신된 토큰으로** 나갔다.
    expect(api.requests.length, 2);
    expect(api.requests.first.headers['Authorization'], 'Bearer a-1');
    expect(
      api.requests.last.headers['Authorization'],
      isNot('Bearer a-1'),
      reason: '갱신한 토큰을 안 쓰면 같은 401이 한 번 더 온다',
    );
  });

  test('연결하지 못하면 network로 전해진다', () async {
    final repo = await repository(replies: [const _Reply.offline()]);

    await expectLater(
      repo.withdraw(),
      throwsA(
        isA<SettingsException>().having(
          (it) => it.failure,
          'failure',
          SettingsFailure.network,
        ),
      ),
    );
  });
}

/// 돌려줄 답 하나.
class _Reply {
  const _Reply(this.status, {this.body = ''}) : offline = false;
  const _Reply.offline() : status = 0, body = '', offline = true;

  final int status;
  final String body;

  /// 서버까지 닿지 못한 경우.
  final bool offline;
}

/// 나간 요청을 적어 두고 [replies]를 순서대로 돌려준다.
///
/// 순서가 필요한 이유는 **401 뒤 재시도**를 봐야 해서다. 하나만 돌려주는
/// 어댑터로는 "다시 보냈는가"를 볼 수 없다.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.replies);

  final List<_Reply> replies;
  final List<_Request> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _Request(
        method: options.method,
        path: options.path,
        body: options.data,
        headers: options.headers,
      ),
    );

    final reply = replies[requests.length - 1];
    if (reply.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: '테스트',
      );
    }
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Request {
  _Request({
    required this.method,
    required this.path,
    required this.body,
    required this.headers,
  });

  final String method;
  final String path;
  final Object? body;
  final Map<String, dynamic> headers;
}
