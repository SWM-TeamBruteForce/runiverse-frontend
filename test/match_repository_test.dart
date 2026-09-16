import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/http_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
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

    test('⚠️ 이미 시작한 러닝은 "진행 중"과 가른다', () {
      // 둘 다 "진행 중이라 안 된다"지만 사용자가 할 일이 다르다. 그쪽은 기다리는
      // 것이고, 이쪽은 이미 달리는 중이라 러닝 화면으로 옮겨야 한다.
      expect(
        HttpMatchRepository.exceptionOf(
          httpError(409, body: {'code': 'MATCH_ALREADY_STARTED'}),
        ).failure,
        MatchFailure.alreadyStarted,
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

  group('앱이 만드는 시간대', () {
    // ⚠️ 대기 인원 조회(14번)가 MVP 범위 밖이다. 목록을 못 받아도 신청은
    // 돼야 하므로, 명세가 고정한 규칙으로 앱이 만든다.
    final noon = DateTime(2026, 9, 16, 12);

    test('18:00~22:00을 30분 간격으로 채운다', () {
      final slots = MatchSlot.todayRange(nowWall: noon);

      expect(slots, hasLength(9));
      // ⚠️ **순간(UTC)으로 비교한다.** `startAt`은 기기 시각이라 로컬 벽시계로
      // 비교하면 CI 시간대에 따라 답이 달라진다. 18:00 KST = 09:00 UTC.
      expect(slots.first.startAt.toUtc(), DateTime.utc(2026, 9, 16, 9));
      expect(slots.last.startAt.toUtc(), DateTime.utc(2026, 9, 16, 13));
    });

    test('⚠️ 화면에는 항상 한국 시각이 뜬다', () {
      // 기기가 GMT여도 `18:00 슬롯`이다. 슬롯은 고정된 한국 시각이라
      // 기기 시간대로 옮겨 그리면 있지도 않은 시각이 화면에 뜬다.
      final slots = MatchSlot.todayRange(nowWall: noon);

      expect(AppStrings.matchSlotTime(slots.first.startAt), '18:00');
      expect(AppStrings.matchSlotTime(slots.last.startAt), '22:00');
    });

    test('서버 표기를 그대로 만든다', () {
      // 밀리초가 붙으면 서버 형식과 어긋난다.
      expect(
        MatchSlot.todayRange(nowWall: noon).first.raw,
        '2026-09-16T18:00:00',
      );
    });

    test('⚠️ 대기 인원은 0이 아니라 모름이다', () {
      // 0으로 그리면 아무도 없다고 잘못 알린다.
      expect(MatchSlot.todayRange(nowWall: noon).first.waitingCount, isNull);
    });

    test('지난 시간대는 잠긴 채로 온다', () {
      final slots = MatchSlot.todayRange(
        nowWall: DateTime(2026, 9, 16, 19, 10),
      );

      expect(slots.first.selectable, isFalse);
      expect(slots.last.selectable, isTrue);
    });

    test('⚠️ 마감 오프셋을 앱이 갖지 않는다', () {
      // 진짜 마감은 시작 10분 전이지만 그것은 운영값이다. 시작 직전까지
      // 열어 두고, 마감된 슬롯은 서버가 409로 거절한다.
      final slots = MatchSlot.todayRange(
        nowWall: DateTime(2026, 9, 16, 17, 55),
      );

      expect(slots.first.selectable, isTrue);
    });

    test('잠근 사본은 나머지를 그대로 둔다', () {
      final slot = MatchSlot.todayRange(nowWall: noon).first.closed();

      expect(slot.selectable, isFalse);
      expect(slot.raw, '2026-09-16T18:00:00');
    });
  });

  group('가짜 저장소', () {
    test('⚠️ 신청은 받은 문자열을 손대지 않고 되돌려 보낸다', () {
      final repository = FakeMatchRepository();
      final slot = MatchSlot.todayRange(
        nowWall: DateTime(2026, 9, 15, 12),
      ).firstWhere((slot) => slot.selectable);

      return repository
          .apply(slotRaw: slot.raw, distance: TargetDistance.km5)
          .then((_) {
            expect(repository.appliedSlotRaw, slot.raw);
            expect(repository.appliedDistance, TargetDistance.km5);
          });
    });
  });
}
