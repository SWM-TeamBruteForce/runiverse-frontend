import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/runner_status.dart';

/// 파티원의 진행과 콤보를 **어떻게 읽는가.**
///
/// 둘 다 고빈도 메시지라 이름도 사진도 오지 않는다. 읽기에 실패해도 러닝을
/// 끊을 수 없어, 무엇을 버리고 무엇을 살리는지가 전부다.
void main() {
  group('진행', () {
    test('값을 그대로 옮긴다', () {
      final progress = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 1520,
        'targetDistanceMeters': 5000,
        'currentPaceSecondsPerKm': 345,
        'status': 'RUNNING',
      })!;

      expect(progress.userId, 'u-1');
      expect(progress.distanceMeters, 1520);
      expect(progress.currentPaceSecondsPerKm, 345);
      expect(progress.status, RunnerStatus.running);
    });

    test('페이스를 못 잰 경우가 있다', () {
      // 단말이 못 재면 null로 온다. 0으로 읽으면 "0초/km"가 화면에 뜬다.
      final progress = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 100,
        'currentPaceSecondsPerKm': null,
      })!;

      expect(progress.currentPaceSecondsPerKm, isNull);
    });

    test('⚠️ 멈춘 것·끊긴 것·끝난 것을 느려진 것과 가른다', () {
      // 셋을 구분하지 못하면 화면에서 전부 "갑자기 뒤처진 사람"으로 보인다.
      // ⚠️ 1.1.0 전에는 `paused`(bool) 하나뿐이라 끊김·종료를 못 가렸다.
      for (final (wire, want) in [
        ('PAUSED', RunnerStatus.paused),
        ('DISCONNECTED', RunnerStatus.disconnected),
        ('FINISHED', RunnerStatus.finished),
      ]) {
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 100,
          'status': wire,
        })!;

        expect(progress.status, want, reason: wire);
      }
    });

    test('⚠️ status 가 없어도 읽기를 포기하지 않는다', () {
      // 옛 서버가 안 보낼 수 있다. 진행 통지 하나를 통째로 버리면 그 사람의
      // 거리가 화면에서 멈춘다 — 상태 하나보다 거리가 더 중요하다.
      final progress = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 100,
      })!;

      expect(progress.distanceMeters, 100);
      expect(progress.status, RunnerStatus.running);
    });

    test('필수 값이 빠지면 읽지 않는다', () {
      expect(RunProgress.of({'userId': 'u-1'}), isNull);
      expect(RunProgress.of({'distanceMeters': 10}), isNull);
    });

    group('진행률', () {
      test('목표 대비로 낸다', () {
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 2500,
          'targetDistanceMeters': 5000,
        })!;

        expect(progress.ratio, 0.5);
      });

      test('⚠️ 목표를 넘겨도 1을 넘지 않는다', () {
        // 막대가 칸 밖으로 나간다.
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 6000,
          'targetDistanceMeters': 5000,
        })!;

        expect(progress.ratio, 1);
      });

      test('⚠️ 목표를 모르면 그리지 않는다', () {
        // 임의의 값으로 막대를 그리면 거짓말이 된다.
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 2500,
        })!;

        expect(progress.ratio, isNull);
      });
    });
  });

  group('콤보', () {
    test('관계마다 하나씩 읽는다', () {
      final combo = RunCombo.of({
        'peers': [
          {
            'userId': 'u-1',
            'gapMeters': -18,
            'comboCount': 12,
            'maxComboCount': 30,
          },
          {
            'userId': 'u-2',
            'gapMeters': 42,
            'comboCount': 3,
            'maxComboCount': 3,
          },
        ],
      })!;

      expect(combo.peers, hasLength(2));
      // 음수면 상대가 뒤에 있다.
      expect(combo.peers.first.gapMeters, -18);
      expect(combo.peers.first.maxComboCount, 30);
    });

    test('⚠️ 빈 목록은 "아무와도 안 겹친다"는 사실이다', () {
      final combo = RunCombo.of({'peers': <Object>[]})!;

      expect(combo.peers, isEmpty);
    });

    test('⚠️ 못 읽은 것은 빈 목록과 다르다', () {
      // 빈 목록으로 읽으면 멀쩡한 콤보가 화면에서 사라진다.
      expect(RunCombo.of({}), isNull);
      expect(RunCombo.of({'peers': null}), isNull);
    });

    test('읽을 수 없는 상대만 건너뛴다', () {
      final combo = RunCombo.of({
        'peers': [
          {'gapMeters': 10},
          {'userId': 'u-2'},
        ],
      })!;

      expect(combo.peers, hasLength(1));
      expect(combo.peers.single.userId, 'u-2');
      // 값이 빠지면 0으로 읽는다 — 겹쳐 있다는 사실 자체는 서버가 보낸 것이다.
      expect(combo.peers.single.comboCount, 0);
    });
  });
}
