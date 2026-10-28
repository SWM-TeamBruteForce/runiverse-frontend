import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/data/http_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';

/// 친구 API의 실패를 갈래로 읽는다.
///
/// ## ⚠️ 상태 코드만 보면 안 되는 곳이 하나 있다
///
/// 친구 요청은 상대가 먼저 요청해 뒀으면 `201`이 아니라 **`200` + `FRIEND`**로
/// 온다. 코드로 갈라서 "요청을 보냈다"로 읽으면, 이미 친구가 된 사람에게
/// "요청 취소" 버튼이 선다.
void main() {
  DioException httpError(int status, {Map<String, Object?>? body}) {
    final request = RequestOptions(path: '/api/v1/users/u1/friend-request');
    return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, Object?>>(
        requestOptions: request,
        statusCode: status,
        data: body,
      ),
    );
  }

  group('실패 갈래', () {
    test('코드별로 읽는다', () {
      expect(
        HttpFriendRepository.exceptionOf(httpError(401)).failure,
        FriendFailure.sessionExpired,
      );
      expect(
        HttpFriendRepository.exceptionOf(httpError(404)).failure,
        FriendFailure.notFound,
      );
      expect(
        HttpFriendRepository.exceptionOf(
          httpError(409, body: {'code': 'FRIEND_REQUEST_ALREADY_EXISTS'}),
        ).failure,
        FriendFailure.alreadyExists,
      );
      expect(
        HttpFriendRepository.exceptionOf(
          httpError(400, body: {'code': 'CANNOT_FRIEND_SELF'}),
        ).failure,
        FriendFailure.cannotFriendSelf,
      );
    });

    test('⚠️ 응답이 아닌 실패는 네트워크다', () {
      // 터널이 내려가면 연결 타임아웃으로 온다. 이것을 unknown 으로 읽으면
      // 사용자에게 "알 수 없는 오류"라고 말하게 된다.
      expect(
        HttpFriendRepository.exceptionOf(
          DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.connectionTimeout,
          ),
        ).failure,
        FriendFailure.network,
      );
    });

    test('모르는 400 은 unknown 이다', () {
      expect(
        HttpFriendRepository.exceptionOf(
          httpError(400, body: {'code': 'INVALID_REQUEST'}),
        ).failure,
        FriendFailure.unknown,
      );
    });

    test('5xx 는 네트워크와 같다', () {
      // 사용자가 할 일이 같다 — 다시 눌러 보는 것뿐이다.
      expect(
        HttpFriendRepository.exceptionOf(httpError(503)).failure,
        FriendFailure.network,
      );
    });
  });

  group('⚠️ 요청 응답은 상태 코드가 아니라 관계로 읽는다', () {
    test('201 이면 보낸 요청이다', () {
      expect(
        HttpFriendRepository.relationOf(const {
          'relationshipType': 'FRIEND_REQUEST_SENT',
        }),
        FriendRelation.requestSent,
      );
    });

    test('200 이면 바로 친구다', () {
      // 상대가 먼저 요청해 둔 경우다. 서로 요청한 건 이미 합의된 것이라
      // 서버가 한 번 더 수락을 요구하지 않는다.
      expect(
        HttpFriendRepository.relationOf(const {'relationshipType': 'FRIEND'}),
        FriendRelation.friend,
      );
    });

    test('⚠️ 관계를 못 읽으면 unknown 으로 던진다', () {
      // 조용히 none 으로 두면 방금 요청한 사람에게 "친구 요청" 버튼이 다시
      // 뜬다. 눌러 봐야 409 만 돌아온다.
      expect(
        () => HttpFriendRepository.relationOf(const {}),
        throwsA(
          isA<FriendException>().having(
            (e) => e.failure,
            'failure',
            FriendFailure.unknown,
          ),
        ),
      );
    });
  });

  group('가짜 저장소', () {
    test('부른 것을 기록한다', () async {
      final fake = FakeFriendRepository(
        searchResults: const [FriendEntry(userId: 'u1', nickname: '철수')],
      );

      await fake.search(query: '철', limit: 20);
      await fake.search(query: '철', limit: 50);

      expect(fake.searchLimits, [20, 50]);
      expect(fake.searchQueries, ['철', '철']);
    });

    test('요청하면 보낸 요청이 된다', () async {
      final fake = FakeFriendRepository();

      expect(await fake.request('u1'), FriendRelation.requestSent);
      expect(fake.requested, ['u1']);
    });

    test('⚠️ 심어 둔 실패를 던진다', () async {
      // 404·409 갈래를 화면 테스트가 재현할 수 있어야 한다.
      final fake = FakeFriendRepository(failure: FriendFailure.notFound);

      expect(() => fake.accept('u1'), throwsA(isA<FriendException>()));
    });
  });
}
