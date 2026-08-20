import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/http_auth_repository.dart';

/// `GET /users/me` 응답을 앱이 제대로 읽는가.
///
/// 서버를 띄우지 않고 **dio 어댑터만 갈아끼워** 실제 파싱 코드를 통과시킨다.
/// 새 패키지를 들이지 않으려고 이 방법을 썼다 — `HttpAuthRepository`가
/// `Dio`를 주입받으므로 가능하다.
void main() {
  HttpAuthRepository repositoryReturning(Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
      ..httpClientAdapter = _CannedAdapter(body);
    return HttpAuthRepository(dio);
  }

  test('서버 규격 그대로면 읽힌다', () async {
    // ⚠️ **`email`이 없다.** 서버 규격에 그 필드가 없기 때문이다.
    // 앱이 그것을 필수로 요구하면 200을 받고도 응답을 통째로 버리고,
    // 닉네임도 isOnboarded도 영영 반영되지 않는다.
    final user = await repositoryReturning({
      'userId': 'u-1',
      'nickname': '러너42',
      'profileImageUrl': 'https://cdn.test/u-1.png',
      'introduction': '아침에 달려요',
      'isOnboarded': true,
    }).fetchCurrentUser('access-token');

    expect(user.userId, 'u-1');
    expect(user.nickname, '러너42');
    expect(user.profileImageUrl, 'https://cdn.test/u-1.png');
    expect(user.introduction, '아침에 달려요');
    expect(user.isOnboarded, isTrue);
  });

  test('온보딩 전이면 닉네임이 null로 온다', () async {
    final user = await repositoryReturning({
      'userId': 'u-2',
      'nickname': null,
      'profileImageUrl': null,
      'introduction': null,
      'isOnboarded': false,
    }).fetchCurrentUser('access-token');

    expect(user.nickname, isNull);
    expect(user.isOnboarded, isFalse);
  });
}

/// 요청이 무엇이든 정해둔 몸통을 200으로 돌려준다.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
