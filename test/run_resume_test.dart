import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/run_resume.dart';
import 'package:runiverse/features/session/domain/user_status.dart';

/// 상태 → 갈 곳. **여섯 조합이 전부 다뤄지는가.**
///
/// 하나를 빠뜨리면 달리던 사람이 홈에 남거나, 쉬는 사람이 러닝 화면으로 끌려간다.
void main() {
  final startAt = DateTime(2026, 9, 15, 19);

  UserStatus ready({required bool isSolo}) => UserStatusReady(
    runningRoomId: 1,
    isSolo: isSolo,
    scheduledStartAt: startAt,
  );

  UserStatus running({required bool isSolo}) => UserStatusRunning(
    runningRoomId: 1,
    isSolo: isSolo,
    scheduledStartAt: startAt,
  );

  final waiting = UserStatusWaiting(
    runningRoomId: 1,
    scheduledStartAt: startAt,
  );

  group('갈 곳', () {
    test('IDLE은 홈이다', () {
      expect(RunResume.of(const UserStatusIdle()), RunResume.home);
    });

    test('⚠️ 매칭 대기는 홈이다 — 매칭 화면이 아직 없다', () {
      expect(RunResume.of(waiting), RunResume.home);
    });

    test('⚠️ READY는 솔로만 준비 화면으로 간다', () {
      // 같은 READY라도 갈 곳이 다르다. 매칭은 스트림·카운트다운이 필요한데
      // 그 화면이 아직 없다.
      expect(RunResume.of(ready(isSolo: true)), RunResume.soloPrepare);
      expect(RunResume.of(ready(isSolo: false)), RunResume.home);
    });

    test('RUNNING은 둘 다 러닝 화면이다', () {
      // 매칭이든 솔로든 할 일이 같다 — 방에 다시 붙어 이어 달린다.
      expect(RunResume.of(running(isSolo: true)), RunResume.running);
      expect(RunResume.of(running(isSolo: false)), RunResume.running);
    });
  });

  group('매칭 배너', () {
    test('⚠️ 대기·확정이면 띄운다', () {
      // 흔적이 없으면 신청이 사라진 줄 알고 다시 신청하다 409를 맞는다.
      expect(RunResume.showsMatchBanner(waiting), isTrue);
      expect(RunResume.showsMatchBanner(ready(isSolo: false)), isTrue);
    });

    test('솔로에는 띄우지 않는다', () {
      expect(RunResume.showsMatchBanner(ready(isSolo: true)), isFalse);
      expect(RunResume.showsMatchBanner(running(isSolo: true)), isFalse);
    });

    test('⚠️ 달리는 중에는 띄우지 않는다', () {
      // 러닝 화면으로 가 있다. 거기서 "매칭 진행 중"은 지난 이야기다.
      expect(RunResume.showsMatchBanner(running(isSolo: false)), isFalse);
    });

    test('IDLE에는 띄우지 않는다', () {
      expect(RunResume.showsMatchBanner(const UserStatusIdle()), isFalse);
    });
  });
}
