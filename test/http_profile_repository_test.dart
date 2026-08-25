import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/profile/data/http_profile_repository.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';

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

  // ── 닉네임 변경 — `PATCH /api/v1/users/me/nickname` (명세 52번) ──────
  //
  // 경로가 `me`다. 본인 것만 바꿀 수 있어 식별자를 받지 않는다.

  group('닉네임 변경', () {
    test('me 경로로 보낸 이름을 싣고 토큰과 함께 나간다', () async {
      final repo = await repositoryReturning({'nickname': '완두콩'});

      await repo.changeNickname('완두콩');

      expect(api.path, '/api/v1/users/me/nickname');
      expect(api.method, 'PATCH');
      expect(api.requestBody, {'nickname': '완두콩'});
      expect(api.headers['Authorization'], 'Bearer a-1');
    });

    test('보낸 값이 아니라 서버가 확정한 값을 돌려준다', () async {
      // 서버가 다듬었다. 보낸 값을 화면에 올리면 화면과 서버가 갈라진다.
      final repo = await repositoryReturning({'nickname': '완두콩'});

      expect(await repo.changeNickname('  완두콩  '), '완두콩');
    });

    test('409 NICKNAME_ALREADY_EXISTS는 taken이다', () async {
      final repo = await repositoryReturning({
        'code': 'NICKNAME_ALREADY_EXISTS',
        'message': '이미 사용 중인 닉네임입니다.',
      }, status: 409);

      expect(
        () => repo.changeNickname('완두콩'),
        throwsA(
          isA<NicknameChangeException>().having(
            (e) => e.failure,
            'failure',
            NicknameChangeFailure.taken,
          ),
        ),
      );
    });

    test('같은 409라도 ONBOARDING_NOT_COMPLETED는 다른 실패다', () async {
      // ⚠️ 묶으면 온보딩을 안 마친 사람에게 "다른 이름을 지어주세요"가 뜬다.
      final repo = await repositoryReturning({
        'code': 'ONBOARDING_NOT_COMPLETED',
        'message': '온보딩을 먼저 완료해 주세요.',
      }, status: 409);

      expect(
        () => repo.changeNickname('완두콩'),
        throwsA(
          isA<NicknameChangeException>().having(
            (e) => e.failure,
            'failure',
            NicknameChangeFailure.notOnboarded,
          ),
        ),
      );
    });

    test('400은 invalid — 앱 규칙이 서버와 어긋났다는 신호다', () async {
      final repo = await repositoryReturning({
        'code': 'INVALID_REQUEST',
      }, status: 400);

      expect(
        () => repo.changeNickname('완두콩'),
        throwsA(
          isA<NicknameChangeException>().having(
            (e) => e.failure,
            'failure',
            NicknameChangeFailure.invalid,
          ),
        ),
      );
    });
  });

  // ── 프로필 수정 — `PATCH /api/v1/users/me/profile` (명세 51번) ───────
  //
  // 부분 수정이다. **보낸 필드만 바뀌고 생략한 것은 그대로 남는다.**

  group('프로필 수정', () {
    test('준 것만 담아 보낸다', () async {
      final repo = await repositoryReturning({});

      await repo.updateProfile(heightCm: 175, weightKg: 70.5);

      expect(api.path, '/api/v1/users/me/profile');
      expect(api.method, 'PATCH');
      // ⚠️ 안 준 필드가 실리면 **다른 기기에서 방금 바꾼 값을 덮는다.**
      expect(api.requestBody, {'weightKg': 70.5, 'heightCm': 175.0});
    });

    test('생년월일은 달력 날짜로 나간다', () async {
      final repo = await repositoryReturning({});

      await repo.updateProfile(birthday: DateTime(1998, 12, 6));

      // 시각·타임존이 붙으면 서버가 400으로 거절한다.
      expect(api.requestBody, {'birthday': '1998-12-06'});
    });

    test('⚠️ 빈 소개글은 빼지 않고 보낸다 — 지우라는 뜻이다', () async {
      final repo = await repositoryReturning({});

      await repo.updateProfile(introduction: '');

      // `null`과 같이 다루면 소개글을 지울 방법이 사라진다.
      expect(api.requestBody, {'introduction': ''});
    });

    test('바꿀 것이 없으면 요청하지 않는다', () async {
      final repo = await repositoryReturning({});

      await repo.updateProfile();

      // 서버에 갔다 와도 결과가 같다.
      expect(api.path, isNull);
    });

    test('409 ONBOARDING_NOT_COMPLETED는 notOnboarded다', () async {
      final repo = await repositoryReturning({
        'code': 'ONBOARDING_NOT_COMPLETED',
      }, status: 409);

      expect(
        () => repo.updateProfile(heightCm: 175),
        throwsA(
          isA<ProfileEditException>().having(
            (e) => e.failure,
            'failure',
            ProfileEditFailure.notOnboarded,
          ),
        ),
      );
    });

    test('400은 invalid — 앱 규칙이 서버와 어긋났다는 신호다', () async {
      final repo = await repositoryReturning({
        'code': 'INVALID_REQUEST',
      }, status: 400);

      expect(
        () => repo.updateProfile(weightKg: 500),
        throwsA(
          isA<ProfileEditException>().having(
            (e) => e.failure,
            'failure',
            ProfileEditFailure.invalid,
          ),
        ),
      );
    });
  });

  group('닉네임 중복확인', () {
    test('토큰 없이 나간다 — 서버가 공개로 열어 둔 경로다', () async {
      final repo = await repositoryReturning({'available': true});

      await repo.isNicknameAvailable('완두콩');

      expect(api.path, '/api/v1/users/nickname/availability');
      expect(api.headers.containsKey('Authorization'), isFalse);
    });

    test('몸통이 기대와 다르면 false가 아니라 null이다', () async {
      // ⚠️ `false`로 떨어뜨리면 멀쩡한 이름이 거절된다.
      final repo = await repositoryReturning({'available': 'yes'});

      expect(await repo.isNicknameAvailable('완두콩'), isNull);
    });
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
