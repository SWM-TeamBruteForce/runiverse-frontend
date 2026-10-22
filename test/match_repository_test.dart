import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('슬롯 하나', () {
    // ⚠️ 목록은 더 이상 앱이 만들지 않는다. **서버가 준다**(명세 No 16,
    // `slot_dto.dart`). 벽시계로 마감을 계산하던 테스트 여덟은 지킬 대상이
    // 없어져 함께 갔다 — 운영에서 아홉 칸이 하루 종일 마감으로 떴던 그 계산이다.
    //
    // 여기 남은 것은 **그 계산과 무관한** 규칙이다.

    test('잠근 사본은 나머지를 그대로 둔다', () {
      final slot = MatchSlot(
        raw: '2026-09-16T18:00:00',
        startAt: DateTime(2026, 9, 16, 18),
        waitingCount: 3,
        selectable: true,
      );

      final closed = slot.closed();

      expect(closed.selectable, isFalse);
      expect(closed.raw, '2026-09-16T18:00:00');
      expect(closed.waitingCount, 3, reason: '대기 인원은 그대로다');
    });
  });

  group('가짜 저장소', () {
    test('⚠️ 신청은 받은 문자열을 손대지 않고 되돌려 보낸다', () {
      // **서버가 준 문자열이 그대로 나가야 한다.** 다시 조립하면 화면에 그린
      // 시각과 서버로 가는 시각이 갈린다.
      final repository = FakeMatchRepository();
      final slot = repository.slotList.first;

      return repository
          .apply(slotRaw: slot.raw, distance: TargetDistance.km5)
          .then((_) {
            expect(repository.appliedSlotRaw, slot.raw);
            expect(repository.appliedDistance, TargetDistance.km5);
          });
    });
  });
}
