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

  test('⚠️ isOnboarded를 안 주면 false가 아니라 null이다', () async {
    // **`false`로 읽으면 "서버가 아직 안 준 것"과 "서버가 아니라고 답한 것"이
    // 같아진다.** 그 둘이 같아지면 저장된 `true`를 덮어쓸 근거가 생기고,
    // 프로필을 막 채운 사람이 다시 프로필 폼으로 끌려간다.
    //
    // 실제로 2026-08-17 인증 응답이 이 필드를 빼고 왔다.
    final user = await repositoryReturning({
      'userId': 'u-3',
      'nickname': '러너7',
    }).fetchCurrentUser('access-token');

    expect(user.userId, 'u-3');
    expect(user.isOnboarded, isNull);
  });

  test('isOnboarded가 bool이 아니면 답하지 않은 것으로 본다', () async {
    // 문자열 "true"를 참으로 읽어주지 않는다. 규격이 어긋난 것을 넘겨짚으면
    // 서버가 바뀐 것을 아무도 모른 채 지나간다.
    final user = await repositoryReturning({
      'userId': 'u-4',
      'isOnboarded': 'true',
    }).fetchCurrentUser('access-token');

    expect(user.isOnboarded, isNull);
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
