import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/features/app_update/data/http_app_version_repository.dart';
import 'package:runiverse/features/app_update/domain/app_version_repository.dart';

/// `GET /app/version` — **나가는 요청이 무엇인가.**
///
/// ⚠️ **토큰을 싣지 않는 것이 이 호출의 계약이다.** 공개 API지만 서버는
/// `Authorization`이 있으면 토큰을 검증한다(공통 규칙). 만료된 토큰을 실으면
/// 버전 확인이 401로 막히는데, 하필 **앱을 오래 안 켠 사람**이 그 상태다 —
/// 업데이트가 가장 필요한 사람이 판정을 못 받는다.
///
/// 지금은 `createDio()`에 토큰 인터셉터가 없어 저절로 지켜진다. 나중에 생기면
/// 이 호출만 빠져나가야 하므로 여기서 못 박는다.
void main() {
  (HttpAppVersionRepository, _RecordingAdapter) repositoryAnswering(
    int status,
    Object? body,
  ) {
    final adapter = _RecordingAdapter(status, body);
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
      // 기본 헤더가 있어도 이 호출에는 실리지 않아야 한다.
      ..options.headers['Authorization'] = 'Bearer stale-token'
      ..httpClientAdapter = adapter;
    return (HttpAppVersionRepository(dio), adapter);
  }

  test('플랫폼을 쿼리로 싣고 /app/version을 부른다', () async {
    final (repository, adapter) = repositoryAnswering(200, {
      'minimumVersion': '1.1.0',
      'latestVersion': '1.2.0',
    });

    await repository.fetch();

    final sent = adapter.sent!;
    expect(sent.method, 'GET');
    expect(sent.path, '/api/v1/app/version');
    // 서버가 받는 값은 `IOS`/`ANDROID` 둘뿐이다. 다른 값은 400이다.
    expect(sent.queryParameters['platform'], anyOf('IOS', 'ANDROID'));
  });

  test('⚠️ Authorization을 싣지 않는다', () async {
    final (repository, adapter) = repositoryAnswering(200, {
      'minimumVersion': '1.1.0',
      'latestVersion': '1.2.0',
    });

    await repository.fetch();

    // dio의 기본 헤더에 토큰을 넣어 뒀는데도 나가지 않아야 한다.
    expect(adapter.sent!.headers['Authorization'], isNull);
  });

  test('두 값을 읽어 돌려준다', () async {
    final (repository, _) = repositoryAnswering(200, {
      'minimumVersion': '1.1.0',
      'latestVersion': '1.2.0',
    });

    final policy = await repository.fetch();

    expect(policy.minimum, const AppVersion(1, 1, 0));
    expect(policy.latest, const AppVersion(1, 2, 0));
  });

  test('⚠️ 못 받으면 던진다 — 통과로 눌러 버리지 않는다', () async {
    // 스플래시가 이것을 기다린다. 실패를 "괜찮다"로 바꾸면 구버전 앱이
    // 판정 없이 그대로 들어간다.
    final (repository, _) = repositoryAnswering(500, null);

    await expectLater(
      repository.fetch(),
      throwsA(isA<AppVersionUnavailable>()),
    );
  });

  test('⚠️ 200이어도 몸통이 기대와 다르면 던진다', () async {
    final (repository, _) = repositoryAnswering(200, {
      'minimumVersion': '1.1.0',
    });

    await expectLater(
      repository.fetch(),
      throwsA(isA<AppVersionUnavailable>()),
    );
  });
}

/// 받은 요청을 적어 두고 [status]와 [body]로 답한다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, this.body);

  final int status;
  final Object? body;

  RequestOptions? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent = options;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
