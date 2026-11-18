import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';

/// 홈 공지 띠의 줄 순서.
///
/// ## ⚠️ 한 번 돌고 멈춘다
///
/// 30초마다 오는 값마다 처음부터 돌리면 첫 줄만 보게 된다. 처음 보는 완주가
/// 왔을 때만 그 줄을 보여 주고 다시 멈춘다. 워치 줄은 늘 한 바퀴에 한 번
/// 지나가고, 소식이 없으면 그 줄에 머문다.
void main() {
  final since = DateTime(2026, 11, 15);
  final updateWeek = DateTime(2026, 11, 17);
  final afterUpdate = DateTime(2026, 11, 30);

  FinishedRun run(int id, {String nickname = '철**', int meters = 5000}) =>
      FinishedRun(
        runningRecordId: id,
        nickname: nickname,
        distanceMeters: meters,
      );

  HomeActivity activity({
    int now = 0,
    List<FinishedRun> runs = const [],
    int today = 0,
    int yesterday = 0,
  }) => HomeActivity(
    runningNowCount: now,
    todayFinishedRuns: runs,
    todayFinishedCount: today,
    yesterdayFinishedCount: yesterday,
  );

  HomeNoticeReel reel() => HomeNoticeReel(updateSince: since);

  /// 멈출 때까지 넘기며 본 줄을 모은다.
  List<HomeNoticeLine> playOut(HomeNoticeReel reel) {
    final seen = [reel.current];
    while (!reel.stopped) {
      reel.advance();
      seen.add(reel.current);
    }
    return seen;
  }

  List<Type> kinds(List<HomeNoticeLine> lines) => [
    for (final l in lines) l.runtimeType,
  ];

  group('한 바퀴', () {
    test('업데이트 → 지금 달리는 수 → 오늘 완주 → 워치 → 오늘 수에서 멈춘다', () {
      final it = reel()
        ..restart(
          activity(now: 3, runs: [run(2), run(1)], today: 20, yesterday: 12),
          updateWeek,
        );

      final lines = playOut(it);

      expect(kinds(lines), [
        HomeNoticeUpdate,
        HomeNoticeRunningNow,
        HomeNoticeFinished,
        HomeNoticeFinished,
        HomeNoticeWatch,
        HomeNoticeToday,
      ]);
      expect((lines[2] as HomeNoticeFinished).run.runningRecordId, 2);
      expect((lines.last as HomeNoticeToday).count, 20);
    });

    test('업데이트는 나온 날부터 1주일만 맨 앞에 선다', () {
      final it = reel()..restart(activity(now: 1, today: 2), afterUpdate);

      expect(it.current, isA<HomeNoticeRunningNow>());
    });

    test('업데이트 날짜가 없으면 업데이트 줄이 없다', () {
      final it = HomeNoticeReel()..restart(activity(now: 1), updateWeek);

      expect(kinds(playOut(it)), [HomeNoticeRunningNow, HomeNoticeWatch]);
    });

    test('⚠️ 마지막 줄에서 더 넘기지 않는다', () {
      final it = reel()..restart(activity(today: 5), afterUpdate);
      playOut(it);
      final turns = it.turns;

      it.advance();

      expect(it.current, isA<HomeNoticeToday>());
      expect(it.turns, turns);
    });

    test('오늘이 어제보다 적으면 어제 수에서 멈춘다', () {
      // 아침에 `오늘 1명`을 띄우면 앱이 죽어 보인다.
      final it = reel()
        ..restart(activity(today: 1, yesterday: 12), afterUpdate);

      expect((playOut(it).last as HomeNoticeYesterday).count, 12);
    });

    test('오늘과 어제가 같으면 오늘이다', () {
      final it = reel()..restart(activity(today: 7, yesterday: 7), afterUpdate);

      expect(playOut(it).last, isA<HomeNoticeToday>());
    });

    test('오늘·어제 수가 없으면 워치 줄에서 멈춘다', () {
      final it = reel()..restart(activity(now: 3), afterUpdate);

      expect(kinds(playOut(it)), [HomeNoticeRunningNow, HomeNoticeWatch]);
    });

    test('소식이 하나도 없으면 워치 한 줄이다', () {
      final it = reel()..restart(activity(), afterUpdate);

      expect(it.current, isA<HomeNoticeWatch>());
      expect(it.stopped, isTrue);
    });

    test('소식이 없어도 업데이트 기간이면 업데이트 → 워치', () {
      final it = reel()..restart(null, updateWeek);

      expect(kinds(playOut(it)), [HomeNoticeUpdate, HomeNoticeWatch]);
    });

    test('⚠️ 워치 한 줄 바퀴는 홈에 다시 들어와도 같은 문장을 다시 넘기지 않는다', () {
      final it = reel()..restart(activity(), afterUpdate);
      final turns = it.turns;

      it.restart(null, afterUpdate);

      expect(it.current, isA<HomeNoticeWatch>());
      expect(it.turns, turns);
    });
  });

  group('30초마다 오는 값', () {
    test('⚠️ 같은 값이 다시 와도 처음으로 돌아가지 않는다', () {
      final value = activity(now: 3, runs: [run(1)], today: 20);
      final it = reel()
        ..restart(value, afterUpdate)
        ..advance();
      final turns = it.turns;

      it.receive(value, afterUpdate);

      expect(it.current, isA<HomeNoticeFinished>());
      expect(it.turns, turns);
    });

    test('멈춘 뒤 처음 보는 완주가 오면 그 줄만 보여 주고 다시 멈춘다', () {
      final it = reel()
        ..restart(activity(now: 3, runs: [run(1)], today: 20), afterUpdate);
      playOut(it);

      it.receive(
        activity(
          now: 2,
          runs: [
            run(9, nickname: '영**'),
            run(1),
          ],
          today: 21,
        ),
        afterUpdate,
      );
      final lines = playOut(it);

      expect(lines, hasLength(2));
      expect((lines.first as HomeNoticeFinished).run.nickname, '영**');
      expect((lines.last as HomeNoticeToday).count, 21);
    });

    test('⚠️ 도는 중에 처음 보는 완주가 오면 남은 줄은 그대로 두고 워치 앞에 끼운다', () {
      // 처음부터 다시 깔면 이번 바퀴에 남은 완주가 안 뜨고, 이미 본 것으로
      // 쳐져 다시도 안 나온다.
      final it = reel()
        ..restart(
          activity(now: 3, runs: [run(3), run(2), run(1)], today: 20),
          afterUpdate,
        );
      final turns = it.turns;

      it.receive(
        activity(now: 2, runs: [run(4), run(3), run(2)], today: 21),
        afterUpdate,
      );

      expect(it.current, isA<HomeNoticeRunningNow>());
      expect(it.turns, turns);
      final lines = playOut(it);
      expect(
        [
          for (final l in lines)
            if (l is HomeNoticeFinished) l.run.runningRecordId,
        ],
        [3, 2, 1, 4],
      );
      expect(kinds(lines.sublist(lines.length - 2)), [
        HomeNoticeWatch,
        HomeNoticeToday,
      ]);
      expect((lines.last as HomeNoticeToday).count, 21);
    });

    test('도는 중에 오면 아직 안 본 지금 달리는 수도 새 값으로 바꾼다', () {
      final it = reel()
        ..restart(activity(now: 3, today: 5), updateWeek); // 업데이트에 서 있음

      it.receive(activity(now: 2, today: 6), updateWeek);
      final lines = playOut(it);

      expect((lines[1] as HomeNoticeRunningNow).count, 2);
      expect((lines.last as HomeNoticeToday).count, 6);
    });

    test('멈춘 줄의 숫자는 넘기지 않고 바꾼다', () {
      final it = reel()..restart(activity(today: 20), afterUpdate);
      playOut(it);
      final turns = it.turns;

      it.receive(activity(today: 21), afterUpdate);

      expect((it.current as HomeNoticeToday).count, 21);
      expect(it.turns, turns);
    });

    test('워치에 멈춘 띠는 오늘 수가 생기면 그리로 옮긴다', () {
      final it = reel()..restart(activity(now: 3), afterUpdate);
      playOut(it);
      final turns = it.turns;

      it.receive(activity(now: 2, today: 1), afterUpdate);

      expect((it.current as HomeNoticeToday).count, 1);
      expect(it.turns, greaterThan(turns));
    });

    test('⚠️ 멈춘 띠는 소식이 모두 사라지면 워치로 돌아간다', () {
      // 안 돌아가면 0명이 된 뒤에도 지난 숫자가 선다.
      final it = reel()..restart(activity(now: 3, today: 2), afterUpdate);
      playOut(it);

      it.receive(activity(), afterUpdate);

      expect(it.current, isA<HomeNoticeWatch>());
    });

    test('⚠️ 도는 중에 소식이 모두 사라지면 남은 숫자를 띄우지 않고 워치로 간다', () {
      // 남겨 두면 다음 차례에 지난 `어제 5명`이 뜨고 거기서 멈춘다(자정 넘김,
      // 코덱스 부계정 리뷰 지적).
      final it = reel()..restart(activity(now: 2, yesterday: 5), afterUpdate);
      expect(it.stopped, isFalse);

      it.receive(activity(), afterUpdate);

      expect(kinds(playOut(it)), [HomeNoticeWatch]);
    });

    test('업데이트를 보여 주는 중에 소식이 사라지면 업데이트 → 워치로 잇는다', () {
      final it = reel()..restart(activity(now: 2, today: 3), updateWeek);
      final turns = it.turns;

      it.receive(activity(), updateWeek);

      expect(it.current, isA<HomeNoticeUpdate>());
      expect(it.turns, turns);
      expect(kinds(playOut(it)), [HomeNoticeUpdate, HomeNoticeWatch]);
    });

    test('⚠️ 처음 값이 홈에 들어온 뒤에 오면 그때 한 바퀴 돈다', () {
      // 연결 직후에는 값이 없다(최대 30초). 그동안 띠는 워치 줄이다.
      final it = reel()..restart(null, afterUpdate);

      it.receive(activity(now: 3, today: 20), afterUpdate);

      expect(it.current, isA<HomeNoticeRunningNow>());
      expect(it.stopped, isFalse);
    });

    test('⚠️ 기다리던 업데이트 줄은 첫 값이 와도 다시 넘기지 않는다', () {
      // 넘기면 같은 문장이 한 번 더 밀려 올라온다(에뮬레이터에서 봄).
      final it = reel()..restart(null, updateWeek);
      final turns = it.turns;

      it.receive(activity(now: 3, today: 20), updateWeek);

      expect(it.current, isA<HomeNoticeUpdate>());
      expect(it.turns, turns);
      expect(it.stopped, isFalse);
    });

    test('소식 없는 값이 계속 와도 워치 줄 그대로다', () {
      final it = reel()..restart(null, afterUpdate);
      final turns = it.turns;

      it.receive(activity(), afterUpdate);

      expect(it.current, isA<HomeNoticeWatch>());
      expect(it.turns, turns);
    });

    test('⚠️ 업데이트 주간에 도는 중 값이 끊겨도 업데이트 줄을 다시 띄우지 않는다', () {
      // 바탕 바퀴를 처음부터 깔면 `업데이트 → 지금 2명 → 업데이트 → 워치`가
      // 된다(두 번째 Claude 재리뷰 지적).
      final it = reel()
        ..restart(activity(now: 2, today: 3), updateWeek)
        ..advance();

      it.receive(null, updateWeek);

      expect(kinds(playOut(it)), [HomeNoticeWatch]);
    });

    test('⚠️ 소식이 사라졌다 다시 생겨도 이번 방문에 본 업데이트 줄은 다시 안 뜬다', () {
      // 두 번째 Claude 재리뷰 지적: 1명 → 0명 → 1명이면 업데이트가 두 번 떴다.
      final it = reel()
        ..restart(activity(now: 1), updateWeek)
        ..advance();

      it.receive(activity(), updateWeek);
      it.receive(activity(now: 1), updateWeek);

      expect(kinds(playOut(it)), [HomeNoticeRunningNow, HomeNoticeWatch]);
    });

    test('홈에 다시 들어오면 업데이트 줄이 다시 맨 앞에 선다', () {
      final it = reel()..restart(activity(now: 1), updateWeek);
      playOut(it);

      it.restart(activity(now: 1), updateWeek);

      expect(it.current, isA<HomeNoticeUpdate>());
    });

    test('값이 끊기면 소식 없는 바퀴로 돌아간다', () {
      final it = reel()..restart(activity(now: 3, today: 20), afterUpdate);

      it.receive(null, afterUpdate);

      expect(it.current, isA<HomeNoticeWatch>());
    });

    test('홈에 다시 들어오면 본 완주도 한 바퀴에 다시 나온다', () {
      final value = activity(runs: [run(1)], today: 1);
      final it = reel()..restart(value, afterUpdate);
      playOut(it);

      it.restart(value, afterUpdate);

      expect(it.current, isA<HomeNoticeFinished>());
    });
  });
}
