import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 매칭 신청 — **서버가 준 시각을 그대로 되돌려 보내는가.**
///
/// 앱이 "오늘 + 19:00"을 조립하면 자정 근처나 기기 시계가 어긋났을 때 엉뚱한
/// 날짜로 신청된다. 그 값이 틀리면 전혀 다른 시간대에 배정되고, 사용자는
/// 잘못된 것을 알아챌 방법이 없다.
void main() {
  /// 서버가 준 오류 응답을 흉내 낸다.
  DioException httpError(int status, {Map<String, Object?>? body}) {
    final request = RequestOptions(path: '/api/v1/running-matches');
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

  group('거리 환산', () {
    test('화면은 km, 서버는 m', () {
      expect(TargetDistance.km3.meters, 3000);
      expect(TargetDistance.km5.meters, 5000);
      expect(TargetDistance.km10.meters, 10000);
    });

    test('서버가 준 미터를 되읽는다', () {
      expect(TargetDistance.fromMeters(10000), TargetDistance.km10);
    });

    test('⚠️ 셋 밖의 값은 읽지 않는다', () {
      // 가까운 값으로 뭉개면 화면이 서버와 다른 거리를 말한다.
      expect(TargetDistance.fromMeters(4000), isNull);
      expect(TargetDistance.fromMeters(null), isNull);
    });
  });

  group('시간대 목록을 읽는다', () {
    test('세 값을 그대로 옮긴다', () {
      final slots = HttpMatchRepository.slotsOf({
        'slots': [
          {
            'scheduledStartAt': '2026-09-15T19:00:00',
            'waitingCount': 3,
            'selectable': true,
          },
        ],
      });

      expect(slots, hasLength(1));
      // ⚠️ 원문 문자열을 들고 있어야 신청에 그대로 실을 수 있다.
      expect(slots.single.raw, '2026-09-15T19:00:00');
      expect(slots.single.startAt, DateTime(2026, 9, 15, 19));
      expect(slots.single.waitingCount, 3);
      expect(slots.single.selectable, isTrue);
    });

    test('마감된 슬롯도 목록에 남는다', () {
      // 빼면 "18:00이 왜 없지"가 되고, 목록이 줄어드는 것도 이상하게 읽힌다.
      final slots = HttpMatchRepository.slotsOf({
        'slots': [
          {
            'scheduledStartAt': '2026-09-15T18:00:00',
            'waitingCount': 0,
            'selectable': false,
          },
        ],
      });

      expect(slots.single.selectable, isFalse);
    });

    test('⚠️ selectable이 없으면 잠근다', () {
      // 모르는 슬롯을 열어두면 마감된 시간대를 눌러 409를 맞는다.
      final slots = HttpMatchRepository.slotsOf({
        'slots': [
          {'scheduledStartAt': '2026-09-15T18:00:00'},
        ],
      });

      expect(slots.single.selectable, isFalse);
      expect(slots.single.waitingCount, 0);
    });

    test('읽을 수 없는 항목만 건너뛴다', () {
      // 슬롯 하나가 이상하다고 목록을 통째로 버리면 매칭을 못 하게 된다.
      final slots = HttpMatchRepository.slotsOf({
        'slots': [
          {'scheduledStartAt': null, 'selectable': true},
          {'scheduledStartAt': '망가진 값', 'selectable': true},
          {'scheduledStartAt': '2026-09-15T19:00:00', 'selectable': true},
        ],
      });

      expect(slots, hasLength(1));
      expect(slots.single.raw, '2026-09-15T19:00:00');
    });

    test('목록이 없으면 빈 목록이다', () {
      expect(HttpMatchRepository.slotsOf(null), isEmpty);
      expect(HttpMatchRepository.slotsOf({'slots': null}), isEmpty);
    });
  });

  group('실패를 가른다', () {
    test('마감 경합', () {
      final error = HttpMatchRepository.exceptionOf(
        httpError(409, body: {'code': 'MATCH_SLOT_CLOSED'}),
      );

      expect(error.failure, MatchFailure.slotClosed);
    });

    test('⚠️ 쿨다운은 해제 시각을 함께 싣는다', () {
      // 시각이 없으면 "언제까지"를 말할 수 없어 안내가 반쪽이 된다.
      final error = HttpMatchRepository.exceptionOf(
        httpError(
          409,
          body: {
            'code': 'MATCH_COOLDOWN',
            'cooldownUntil': '2026-09-15T19:30:00',
          },
        ),
      );

      expect(error.failure, MatchFailure.cooldown);
      expect(error.cooldownUntil, DateTime(2026, 9, 15, 19, 30));
    });

    test('쿨다운에 시각이 없어도 갈래는 유지한다', () {
      final error = HttpMatchRepository.exceptionOf(
        httpError(409, body: {'code': 'MATCH_COOLDOWN'}),
      );

      expect(error.failure, MatchFailure.cooldown);
      expect(error.cooldownUntil, isNull);
    });

    test('러닝 중 신청도 "이미 진행 중"으로 묶는다', () {
      // 서버 코드는 둘이지만 화면이 할 말은 같다.
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(409, body: {'code': 'MATCH_ALREADY_IN_PROGRESS'}),
        ).failure,
        MatchFailure.alreadyInProgress,
      );
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(409, body: {'code': 'RUNNING_ALREADY_IN_PROGRESS'}),
        ).failure,
        MatchFailure.alreadyInProgress,
      );
    });

    test('온보딩 미완료', () {
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(409, body: {'code': 'ONBOARDING_NOT_COMPLETED'}),
        ).failure,
        MatchFailure.onboardingNotCompleted,
      );
    });

    test('400은 앱의 선택지가 서버와 어긋났다는 신호다', () {
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(400, body: {'code': 'INVALID_REQUEST'}),
        ).failure,
        MatchFailure.invalidRequest,
      );
    });

    test('취소할 것이 없으면 따로 가른다', () {
      // 실패로 알리기보다 이미 원하던 상태인 경우가 많다.
      expect(
        HttpMatchRepository.exceptionOf(httpError(404)).failure,
        MatchFailure.nothingToCancel,
      );
    });

    test('401은 세션 만료다', () {
      expect(
        HttpMatchRepository.exceptionOf(httpError(401)).failure,
        MatchFailure.sessionExpired,
      );
    });

    test('⚠️ 닿지 못한 요청은 network다', () {
      // 신청됐는지 알 수 없는 상태라 다시 보내면 중복 신청이 된다.
      final error = HttpMatchRepository.exceptionOf(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/running-matches'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(error.failure, MatchFailure.network);
    });

    test('모르는 코드는 모른다고 한다', () {
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(409, body: {'code': '처음 보는 코드'}),
        ).failure,
        MatchFailure.unknown,
      );
    });
  });

  group('가짜 저장소', () {
    test('⚠️ 신청은 받은 문자열을 손대지 않고 되돌려 보낸다', () async {
      // ⚠️ 기본 슬롯은 `DateTime.now()`에 기댄다. 밤 10시가 넘어 돌리면 고를
      // 수 있는 자리가 하나도 없어 테스트가 시각에 따라 달라진다.
      final repository = FakeMatchRepository(
        slots: FakeMatchRepository.defaultSlots(now: DateTime(2026, 9, 15, 12)),
      );
      final slot = repository.slots.firstWhere((slot) => slot.selectable);

      await repository.apply(slotRaw: slot.raw, distance: TargetDistance.km5);

      expect(repository.appliedSlotRaw, slot.raw);
      expect(repository.appliedDistance, TargetDistance.km5);
    });

    test('기본 슬롯은 18:00~22:00을 30분 간격으로 채운다', () {
      final slots = FakeMatchRepository.defaultSlots(
        now: DateTime(2026, 9, 15, 12),
      );

      expect(slots, hasLength(9));
      expect(slots.first.startAt, DateTime(2026, 9, 15, 18));
      expect(slots.last.startAt, DateTime(2026, 9, 15, 22));
      expect(slots.first.raw, '2026-09-15T18:00:00');
    });

    test('이미 지난 시간대는 잠긴 채로 온다', () {
      final slots = FakeMatchRepository.defaultSlots(
        now: DateTime(2026, 9, 15, 19, 10),
      );

      expect(slots.first.selectable, isFalse);
      expect(slots.last.selectable, isTrue);
    });
  });
}
