import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/http_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';

/// `POST /auth/logout` — **나가는 요청이 무엇인가.**
///
/// 여기서 보는 것은 응답 파싱이 아니라 **요청 쪽**이다. 서버 세션을 끊는 일은
/// 토큰이 헤더에 실려야 되는데, 그것이 빠지면 서버는 401만 돌려주고 앱은
/// 아무것도 모른 채 로그아웃된 것처럼 보인다. 겉으로 차이가 없는 결함이다.
///
/// 서버를 띄우지 않고 **dio 어댑터만 갈아끼운다**(`http_auth_repository_me_test`
/// 와 같은 방법). 새 패키지를 들이지 않는다.
void main() {
  /// 요청을 적어 두고 [status]로 답하는 저장소.
  (HttpAuthRepository, _RecordingAdapter) repositoryAnswering(int status) {
    final adapter = _RecordingAdapter(status);
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
      ..httpClientAdapter = adapter;
    return (HttpAuthRepository(dio), adapter);
  }

  test('토큰을 실어 /auth/logout으로 보낸다', () async {
    final (repository, adapter) = repositoryAnswering(204);

    await repository.signOut('access-token');

    final sent = adapter.sent!;
    expect(sent.method, 'POST');
    expect(sent.path, '/api/v1/auth/logout');
    // 토큰이 없으면 서버가 누구를 끊을지 모른다.
    expect(sent.headers['Authorization'], 'Bearer access-token');
  });

  test('⚠️ 204를 성공으로 본다', () async {
    // 몸통이 없다. 읽을 것을 기대하면 성공한 호출이 실패로 떨어지고,
    // 매번 쓸데없이 갱신하고 다시 부른다.
    final (repository, _) = repositoryAnswering(204);

    await expectLater(repository.signOut('access-token'), completes);
  });

  test('⚠️ 401은 sessionExpired다', () async {
    // 부르는 쪽이 이 값을 보고 갱신한 뒤 한 번 더 부른다. 다른 값으로 올리면
    // 정작 끊어야 할 refreshToken이 살아남는다.
    final (repository, _) = repositoryAnswering(401);

    await expectLater(
      repository.signOut('stale-token'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.failure,
          'failure',
          AuthFailure.sessionExpired,
        ),
      ),
    );
  });

  test('⚠️ 500은 sessionExpired가 아니다', () async {
    // 여기가 갱신으로 가는 갈림길이다. 서버 오류까지 만료로 읽으면 지나가는
    // 실패마다 리프레시 토큰을 괜히 회전시킨다.
    final (repository, _) = repositoryAnswering(500);

    await expectLater(
      repository.signOut('access-token'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.failure,
          'failure',
          isNot(AuthFailure.sessionExpired),
        ),
      ),
    );
  });
}

/// 받은 요청을 적어 두고 [status]로 답한다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status);

  final int status;

  /// 마지막으로 받은 요청. 한 번도 안 왔으면 `null`이다.
  RequestOptions? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent = options;
    // 204에는 몸통이 없다. 실제 서버와 같게 둔다.
    return ResponseBody.fromString('', status);
  }

  @override
  void close({bool force = false}) {}
}
