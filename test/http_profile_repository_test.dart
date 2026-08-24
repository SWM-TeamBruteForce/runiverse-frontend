import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/profile/data/http_profile_repository.dart';

/// 프로필 요약 — `GET /api/v1/users/{userId}` (명세 37번).
///
/// **본인·타인이 같은 엔드포인트를 쓴다.** 그래서 경로에 식별자를 받고,
/// 저장소에서 꺼내 쓰지 않는다 — 꺼내 쓰면 남의 프로필을 열어도 내 것이 나온다.
///
/// 서버를 띄우지 않고 dio 어댑터만 갈아끼워 실제로 나가는 요청을 본다.
void main() {
  late _CannedAdapter api;

  Future<HttpProfileRepository> repositoryReturning(
    Map<String, dynamic> body, {
    int status = 200,
  }) async {
    api = _CannedAdapter(body, status: status);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return HttpProfileRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = api,
      store,
      FakeAuthRepository(latency: Duration.zero),
    );
  }

  Map<String, dynamic> bodyFor(String userId) => {
    'userId': userId,
    'isMe': true,
    'nickname': '러너42',
    'profileImageUrl': 'https://cdn.test/a.png',
    'introduction': '아침에 달려요',
    'friendCount': 7,
    'friendStatus': null,
    // 이번 화면이 쓰지 않는 값들도 함께 온다. 읽지 않고 흘려보낸다.
    'mileageTotalMeters': 320500,
    'runningCount': 78,
  };

  test('요청한 userId 경로로 나간다', () async {
    final repo = await repositoryReturning(bodyFor('u-9'));

    await repo.fetch('u-9');

    // ⚠️ 저장소의 userId가 아니라 **인자로 받은 것**이어야 한다.
    expect(api.path, '/api/v1/users/u-9');
  });

  test('화면이 쓰는 값만 읽는다', () async {
    final repo = await repositoryReturning(bodyFor('u-1'));

    final summary = await repo.fetch('u-1');

    expect(summary.userId, 'u-1');
    expect(summary.nickname, '러너42');
    expect(summary.profileImageUrl, 'https://cdn.test/a.png');
    expect(summary.introduction, '아침에 달려요');
    expect(summary.friendCount, 7);
  });

  test('온보딩 전이면 닉네임과 소개가 null로 온다', () async {
    final repo = await repositoryReturning({
      'userId': 'u-2',
      'isMe': true,
      'nickname': null,
      'profileImageUrl': null,
      'introduction': null,
      'friendCount': 0,
    });

    final summary = await repo.fetch('u-2');

    expect(summary.nickname, isNull);
    expect(summary.profileImageUrl, isNull);
    expect(summary.introduction, isNull);
    expect(summary.friendCount, 0);
  });

  test('토큰을 실어 보낸다', () async {
    final repo = await repositoryReturning(bodyFor('u-1'));

    await repo.fetch('u-1');

    // 명세 37번은 `권한: YES`다. 사진 조회(49번)와 다르다.
    expect(api.headers['Authorization'], 'Bearer a-1');
  });

}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body, {this.status = 200});

  final Map<String, dynamic> body;
  final int status;
  String? path;
  String? method;
  Object? requestBody;
  Map<String, dynamic> headers = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    method = options.method;
    requestBody = options.data;
    headers = options.headers;
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
