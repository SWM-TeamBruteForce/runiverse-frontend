import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';

/// 초대 REST.
///
/// ## ⚠️ 실패 문구를 서버에서 가져온다
///
/// 실패 사유가 **상대의 상태**(매칭 중·러닝 중·이미 참여 중)라서 앱이 더 잘 쓸
/// 말이 없다. 명세도 `message`를 그대로 보여 주라고 한다.
void main() {
  DioException badResponse(int status, String? code, {String? message}) =>
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/match-rooms/invite'),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/api/v1/match-rooms/invite'),
          statusCode: status,
          data: {'code': ?code, 'message': ?message},
        ),
      );

  group('실패 코드를 가른다', () {
    test('초대 보내기 409 여섯 가지', () {
      const cases = <(String, InviteFailure)>[
        ('RUNNING_INVITATION_CLOSED', InviteFailure.closed),
        ('NOT_FRIEND', InviteFailure.notFriend),
        ('INVITEE_ALREADY_IN_ROOM', InviteFailure.alreadyInRoom),
        ('INVITEE_IN_MATCHING', InviteFailure.inMatching),
        ('INVITEE_RUNNING', InviteFailure.running),
        ('INVITE_COUNT_EXCEEDED', InviteFailure.countExceeded),
      ];

      for (final (code, expected) in cases) {
        expect(
          HttpMatchRepository.inviteExceptionOf(badResponse(409, code)).failure,
          expected,
          reason: code,
        );
      }
    });

    test('수락 409 다섯 가지', () {
      const cases = <(String, InviteFailure)>[
        ('RUNNING_INVITATION_CLOSED', InviteFailure.closed),
        ('RUNNING_INVITATION_NOT_PENDING', InviteFailure.notPending),
        ('RUNNING_ROOM_FULL', InviteFailure.roomFull),
        ('RUNNING_ALREADY_IN_PROGRESS', InviteFailure.alreadyInProgress),
        ('ONBOARDING_NOT_COMPLETED', InviteFailure.onboardingNotCompleted),
      ];

      for (final (code, expected) in cases) {
        expect(
          HttpMatchRepository.inviteExceptionOf(badResponse(409, code)).failure,
          expected,
          reason: code,
        );
      }
    });

    test('개설 409 — 시작 시각이 범위를 벗어났다', () {
      expect(
        HttpMatchRepository.inviteExceptionOf(
          badResponse(409, 'INVITE_START_AT_OUT_OF_RANGE'),
        ).failure,
        InviteFailure.startAtOutOfRange,
      );
    });

    test('⚠️ 서버 문구를 그대로 들고 온다', () {
      final error = HttpMatchRepository.inviteExceptionOf(
        badResponse(409, 'NOT_FRIEND', message: '친구에게만 초대할 수 있습니다.'),
      );

      expect(error.message, '친구에게만 초대할 수 있습니다.');
    });

    test('문구가 없어도 갈래는 읽는다', () {
      final error = HttpMatchRepository.inviteExceptionOf(
        badResponse(409, 'NOT_FRIEND'),
      );

      expect(error.failure, InviteFailure.notFriend);
      expect(error.message, isNull);
    });

    test('⚠️ 404는 세 가지를 구분하지 않는다', () {
      // 방 없음·초대 방 아님·내가 참가자 아님. 한 문장으로 말한다.
      expect(
        HttpMatchRepository.inviteExceptionOf(badResponse(404, null)).failure,
        InviteFailure.notFound,
      );
    });

    test('⚠️ 404를 nothingToCancel로 묶지 않는다', () {
      // `exceptionOf`(매칭용)를 그대로 쓰면 초대 실패에 "취소할 활성 신청이
      // 없어요"가 뜬다.
      expect(
        HttpMatchRepository.inviteExceptionOf(badResponse(404, null)).failure,
        isNot(InviteFailure.unknown),
      );
    });

    test('400 INVALID_REQUEST', () {
      expect(
        HttpMatchRepository.inviteExceptionOf(
          badResponse(400, 'INVALID_REQUEST'),
        ).failure,
        InviteFailure.invalidRequest,
      );
    });

    test('401은 세션이 끝난 것이다', () {
      expect(
        HttpMatchRepository.inviteExceptionOf(badResponse(401, null)).failure,
        InviteFailure.sessionExpired,
      );
    });

    test('5xx와 망 오류는 다시 해 보는 것뿐이다', () {
      expect(
        HttpMatchRepository.inviteExceptionOf(badResponse(503, null)).failure,
        InviteFailure.network,
      );
      expect(
        HttpMatchRepository.inviteExceptionOf(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionTimeout,
          ),
        ).failure,
        InviteFailure.network,
      );
    });

    test('모르는 코드는 unknown이다', () {
      expect(
        HttpMatchRepository.inviteExceptionOf(
          badResponse(409, 'SOMETHING_NEW'),
        ).failure,
        InviteFailure.unknown,
      );
    });
  });

  group('요청', () {
    late List<RequestOptions> sent;
    late List<Object?> bodies;
    late HttpMatchRepository repo;

    setUp(() async {
      sent = [];
      bodies = [];
      final dio = Dio();
      dio.httpClientAdapter = _RecordingAdapter(sent, bodies);
      final store = InMemoryTokenStore();
      await store.saveTokens(accessToken: 'a', refreshToken: 'r');
      repo = HttpMatchRepository(
        dio,
        store,
        TokenRefresher(FakeAuthRepository(), store),
      );
    });

    test('개설은 시각과 거리만 보낸다', () async {
      await repo.createInviteRoom(
        scheduledStartAt: '2026-10-29T19:30:00',
        meters: 7000,
      );

      expect(sent.single.path, '/api/v1/match-rooms/invite');
      expect(sent.single.method, 'POST');
      expect(sent.single.data, {
        'scheduledStartAt': '2026-10-29T19:30:00',
        'targetDistanceMeters': 7000,
      });
    });

    test('⚠️ 초대는 inviteeId 한 명만 보낸다', () async {
      // 배열이 아니다. 여럿을 고르게 하면 결과를 한 줄씩 보여줄 수 없다.
      await repo.invite(roomId: 130, inviteeId: 'u1');

      expect(sent.single.path, '/api/v1/match-rooms/130/invitations');
      expect(sent.single.data, {'inviteeId': 'u1'});
    });

    test('⚠️ 수락은 본문이 없다', () async {
      await repo.acceptInvitation(130);

      expect(sent.single.path, '/api/v1/match-rooms/130/invitations/accept');
      expect(sent.single.data, isNull);
    });

    test('거절도 본문이 없다', () async {
      await repo.declineInvitation(130);

      expect(sent.single.path, '/api/v1/match-rooms/130/invitations/decline');
      expect(sent.single.data, isNull);
    });

    test('⚠️ 방 번호 없는 201은 unknown이다', () async {
      // 방은 열렸는데 스트림에 붙을 수 없다. 조용히 넘기면 방을 만들어 놓고
      // 아무 소식도 못 받는다.
      final dio = Dio();
      dio.httpClientAdapter = _RecordingAdapter(sent, bodies, body: '{}');
      final store = InMemoryTokenStore();
      await store.saveTokens(accessToken: 'a', refreshToken: 'r');
      final blind = HttpMatchRepository(
        dio,
        store,
        TokenRefresher(FakeAuthRepository(), store),
      );

      await expectLater(
        blind.createInviteRoom(
          scheduledStartAt: '2026-10-29T19:30:00',
          meters: 5000,
        ),
        throwsA(
          isA<InviteException>().having(
            (e) => e.failure,
            'failure',
            InviteFailure.unknown,
          ),
        ),
      );
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.sent, this.bodies, {this.body});

  final List<RequestOptions> sent;
  final List<Object?> bodies;
  final String? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    bodies.add(options.data);
    return ResponseBody.fromString(
      body ?? '{"runningRoomId":130}',
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
