import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/data/http_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';

/// 상태 조회 — **앱이 어느 화면으로 갈지 정하는 값이다.**
///
/// 잘못 읽으면 달리는 중인 사람을 홈으로 보내고 기록이 끊긴다. `status`와
/// `type` 두 문자열의 조합이라, 조합마다 무엇으로 읽히는지가 이 테스트의 전부다.
void main() {
  final now = DateTime(2026, 9, 15, 15);

  Map<String, dynamic> body({
    required String status,
    String? type,
    int? roomId = 125,
    String? startAt = '2026-09-15T19:00:00',
    int? target = 5000,
    String? cooldownUntil,
  }) => {
    'status': status,
    'type': type,
    'runningRoomId': roomId,
    'scheduledStartAt': startAt,
    'targetDistanceMeters': target,
    'cooldownUntil': cooldownUntil,
  };

  group('조합을 읽는다', () {
    test('IDLE은 방 정보가 없어도 읽힌다', () {
      // 쉬는 중에는 서버가 나머지를 전부 `null`로 준다.
      final status = HttpUserStatusRepository.statusOf({
        'status': 'IDLE',
        'type': null,
        'runningRoomId': null,
      });

      expect(status, isA<UserStatusIdle>());
    });

    test('WAITING · MATCH', () {
      final status = HttpUserStatusRepository.statusOf(
        body(status: 'WAITING', type: 'MATCH'),
      );

      expect(status, isA<UserStatusWaiting>());
      final waiting = status as UserStatusWaiting;
      expect(waiting.runningRoomId, 125);
      expect(waiting.scheduledStartAt, DateTime(2026, 9, 15, 19));
      expect(waiting.targetDistanceMeters, 5000);
    });

    test('READY · MATCH는 솔로가 아니다', () {
      final status =
          HttpUserStatusRepository.statusOf(
                body(status: 'READY', type: 'MATCH'),
              )
              as UserStatusReady;

      expect(status.isSolo, isFalse);
    });

    test('⚠️ READY · SOLO는 솔로다', () {
      // 같은 READY라도 갈 곳이 다르다. 매칭은 스트림에 붙고 솔로는 준비 화면이다.
      final status =
          HttpUserStatusRepository.statusOf(body(status: 'READY', type: 'SOLO'))
              as UserStatusReady;

      expect(status.isSolo, isTrue);
    });

    test('RUNNING · MATCH', () {
      final status =
          HttpUserStatusRepository.statusOf(
                body(status: 'RUNNING', type: 'MATCH'),
              )
              as UserStatusRunning;

      expect(status.isSolo, isFalse);
      expect(status.runningRoomId, 125);
    });

    test('RUNNING · SOLO', () {
      final status =
          HttpUserStatusRepository.statusOf(
                body(status: 'RUNNING', type: 'SOLO'),
              )
              as UserStatusRunning;

      expect(status.isSolo, isTrue);
    });

    test('목표 없는 솔로 방은 목표가 null이다', () {
      final status =
          HttpUserStatusRepository.statusOf(
                body(status: 'READY', type: 'SOLO', target: null),
              )
              as UserStatusReady;

      expect(status.targetDistanceMeters, isNull);
    });
  });

  group('계약이 깨지면 던진다', () {
    test('⚠️ 모르는 status는 던진다', () {
      // 조용히 IDLE로 읽으면 달리는 중인 사람을 홈으로 보낸다.
      expect(
        () => HttpUserStatusRepository.statusOf(body(status: 'PAUSED')),
        throwsA(isA<UserStatusException>()),
      );
    });

    test('⚠️ 진행 중인데 방 번호가 없으면 던진다', () {
      // 복구할 방을 모르면 화면을 그릴 수 없다.
      expect(
        () => HttpUserStatusRepository.statusOf(
          body(status: 'RUNNING', type: 'SOLO', roomId: null),
        ),
        throwsA(isA<UserStatusException>()),
      );
    });

    test('⚠️ 진행 중인데 시작 시각이 없으면 던진다', () {
      // 경과 시간을 낼 근거가 사라진다 — 서버가 복구 스냅샷을 주지 않는다.
      expect(
        () => HttpUserStatusRepository.statusOf(
          body(status: 'RUNNING', type: 'MATCH', startAt: null),
        ),
        throwsA(isA<UserStatusException>()),
      );
    });
  });

  group('쿨다운', () {
    test('값이 없으면 남은 시간이 0이다', () {
      const status = UserStatusIdle();

      expect(status.remainingCooldown(now: now), Duration.zero);
      expect(status.canApplyMatch(now: now), isTrue);
    });

    test('⚠️ 미래면 남은 시간만큼 막는다', () {
      final status = UserStatusIdle(
        cooldownUntil: DateTime(2026, 9, 15, 15, 20),
      );

      expect(status.remainingCooldown(now: now), const Duration(minutes: 20));
      expect(status.canApplyMatch(now: now), isFalse);
    });

    test('⚠️ 지났으면 0이다. 음수를 돌려주지 않는다', () {
      // 음수를 그대로 내보내면 화면이 "-3분 후"를 그린다.
      final status = UserStatusIdle(
        cooldownUntil: DateTime(2026, 9, 15, 14, 57),
      );

      expect(status.remainingCooldown(now: now), Duration.zero);
      expect(status.canApplyMatch(now: now), isTrue);
    });

    test('⚠️ IDLE이 아니면 제한이 없어도 신청할 수 없다', () {
      // 이미 진행 중인 매칭이 있다. 쿨다운과는 다른 이유로 막힌다.
      final status = UserStatusWaiting(
        runningRoomId: 125,
        scheduledStartAt: DateTime(2026, 9, 15, 19),
      );

      expect(status.remainingCooldown(now: now), Duration.zero);
      expect(status.canApplyMatch(now: now), isFalse);
    });

    test('진행 중인 상태에도 쿨다운이 실릴 수 있다', () {
      // 상태와 따로 본다 — IDLE에서만 오는 값이 아니다.
      final status =
          HttpUserStatusRepository.statusOf(
                body(
                  status: 'RUNNING',
                  type: 'SOLO',
                  cooldownUntil: '2026-09-15T15:20:00',
                ),
              )
              as UserStatusRunning;

      expect(status.remainingCooldown(now: now), const Duration(minutes: 20));
    });
  });
}
