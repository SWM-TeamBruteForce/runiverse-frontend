import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/record/data/http_run_record_repository.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';

/// 기록 조회가 실패한 **이유를 가르는가.**
///
/// 404·403은 다시 시도해도 같은 답이다. `server`로 뭉치면 화면이 "잠시 뒤 다시"를
/// 권하는데, 기다린다고 없는 기록이 생기지는 않는다.
void main() {
  Future<HttpRunRecordRepository> repositoryReturning(int status) async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return HttpRunRecordRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))
        ..httpClientAdapter = _CannedAdapter(status),
      store,
      _NoRefresher(),
    );
  }

  Future<RunRecordFailure> failureOf(int status) async {
    final repository = await repositoryReturning(status);
    try {
      await repository.byRoom(125);
      fail('던지지 않았다');
    } on RunRecordException catch (error) {
      return error.failure;
    }
  }

  test('⚠️ 없는 기록은 재시도 대상이 아니다', () async {
    expect(await failureOf(404), RunRecordFailure.notFound);
  });

  test('⚠️ 참가자가 아니면 재시도 대상이 아니다', () async {
    expect(await failureOf(403), RunRecordFailure.forbidden);
  });

  test('5xx는 서버 오류다', () async {
    expect(await failureOf(503), RunRecordFailure.server);
  });

  test('400은 앱의 버그다', () async {
    expect(await failureOf(400), RunRecordFailure.invalidRequest);
  });
}

/// 갱신하지 않는다. 이 테스트는 401을 만들지 않는다.
class _NoRefresher implements TokenRefresher {
  @override
  Future<String?> refresh() async => null;

  @override
  void Function()? get onExpired => null;
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(const <String, dynamic>{}),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
