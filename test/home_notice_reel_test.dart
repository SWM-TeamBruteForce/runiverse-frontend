import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';

/// 홈 공지 띠의 줄 순서.
///
/// ## ⚠️ 한 번 돌고 멈춘다
///
/// 30초마다 오는 값마다 처음부터 돌리면 첫 줄만 보게 된다. 처음 보는 완주가
/// 왔을 때만 그 줄을 보여 주고 다시 멈춘다.
void main() {
  final since = DateTime(2026, 11, 15);
  final featureWeek = DateTime(2026, 11, 17);
  final afterFeature = DateTime(2026, 11, 30);

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

  /// 멈출 때까지 넘기며 본 줄을 모은다.
  List<HomeNoticeLine> playOut(HomeNoticeReel reel) {
    final seen = [reel.current];
    while (!reel.stopped) {
      reel.advance();
      seen.add(reel.current);
    }
    return seen;
  }

  group('한 바퀴', () {
    test('새 기능 → 지금 달리는 수 → 오늘 완주 → 오늘 수에서 멈춘다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(
          activity(now: 3, runs: [run(2), run(1)], today: 20, yesterday: 12),
          featureWeek,
        );

      final lines = playOut(reel);

      expect(lines.map((l) => l.runtimeType), [
        HomeNoticeFeature,
        HomeNoticeRunningNow,
        HomeNoticeFinished,
        HomeNoticeFinished,
        HomeNoticeToday,
      ]);
      expect((lines[2] as HomeNoticeFinished).run.runningRecordId, 2);
      expect((lines.last as HomeNoticeToday).count, 20);
    });

    test('⚠️ 마지막 줄에서 더 넘기지 않는다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(today: 5), afterFeature);
      final turns = reel.turns;

      reel.advance();

      expect(reel.current, isA<HomeNoticeToday>());
      expect(reel.turns, turns);
    });

    test('새 기능 안내는 나온 날부터 1주일만 맨 앞에 선다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 1, today: 2), afterFeature);

      expect(reel.current, isA<HomeNoticeRunningNow>());
    });

    test('오늘이 어제보다 적으면 어제 수에서 멈춘다', () {
      // 아침에 `오늘 1명`을 띄우면 앱이 죽어 보인다.
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(today: 1, yesterday: 12), afterFeature);

      expect((playOut(reel).last as HomeNoticeYesterday).count, 12);
    });

    test('오늘과 어제가 같으면 오늘이다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(today: 7, yesterday: 7), afterFeature);

      expect(playOut(reel).last, isA<HomeNoticeToday>());
    });

    test('소식이 하나도 없으면 새 기능 안내 한 줄이다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(), afterFeature);

      expect(reel.current, isA<HomeNoticeFeature>());
      expect(reel.stopped, isTrue);
    });

    test('값이 아직 없으면 새 기능 안내 한 줄이다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(null, featureWeek);

      expect(reel.current, isA<HomeNoticeFeature>());
      expect(reel.stopped, isTrue);
    });
  });

  group('30초마다 오는 값', () {
    test('⚠️ 같은 값이 다시 와도 처음으로 돌아가지 않는다', () {
      final value = activity(now: 3, runs: [run(1)], today: 20);
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(value, afterFeature)
        ..advance();
      final turns = reel.turns;

      reel.receive(value, afterFeature);

      expect(reel.current, isA<HomeNoticeFinished>());
      expect(reel.turns, turns);
    });

    test('처음 보는 완주가 오면 그 줄만 보여 주고 다시 멈춘다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3, runs: [run(1)], today: 20), afterFeature);
      playOut(reel);

      reel.receive(
        activity(
          now: 2,
          runs: [
            run(9, nickname: '영**'),
            run(1),
          ],
          today: 21,
        ),
        afterFeature,
      );
      final lines = playOut(reel);

      expect(lines, hasLength(2));
      expect((lines.first as HomeNoticeFinished).run.nickname, '영**');
      expect((lines.last as HomeNoticeToday).count, 21);
    });

    test('⚠️ 도는 중에 처음 보는 완주가 오면 남은 줄 뒤에 이어 붙인다', () {
      // 처음부터 다시 깔면 이번 바퀴에 남은 완주가 안 뜨고, 이미 본 것으로
      // 쳐져 다시도 안 나온다(두 번째 Claude 리뷰 지적).
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(
          activity(now: 3, runs: [run(3), run(2), run(1)], today: 20),
          afterFeature,
        );
      final turns = reel.turns;

      reel.receive(
        activity(now: 3, runs: [run(4), run(3), run(2)], today: 21),
        afterFeature,
      );

      expect(reel.current, isA<HomeNoticeRunningNow>());
      expect(reel.turns, turns);
      final lines = playOut(reel);
      expect(
        [
          for (final l in lines)
            if (l is HomeNoticeFinished) l.run.runningRecordId,
        ],
        [3, 2, 1, 4],
      );
      expect((lines.last as HomeNoticeToday).count, 21);
    });

    test('⚠️ 지금 달리는 수로 끝나던 바퀴에 완주가 오면 그 줄은 ①로 남는다', () {
      // 빼면 이번 바퀴에서 `지금 N명`이 사라진다(두 번째 Claude 재리뷰 지적).
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3), featureWeek);
      expect(reel.stopped, isFalse);

      reel.receive(activity(now: 2, runs: [run(9)], today: 1), featureWeek);

      expect(playOut(reel).map((l) => l.runtimeType), [
        HomeNoticeFeature,
        HomeNoticeRunningNow,
        HomeNoticeFinished,
        HomeNoticeToday,
      ]);
    });

    test('지금 달리는 수로 끝나던 바퀴에 어제 수가 생겨도 ①은 남는다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3), featureWeek);

      reel.receive(activity(now: 2, yesterday: 5), featureWeek);
      final lines = playOut(reel);

      expect((lines[1] as HomeNoticeRunningNow).count, 2);
      expect((lines.last as HomeNoticeYesterday).count, 5);
    });

    test('⚠️ 한 줄짜리 바퀴는 탭에서 돌아와도 같은 문장을 다시 넘기지 않는다', () {
      final value = activity(yesterday: 12);
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(value, afterFeature);
      final turns = reel.turns;

      reel.restart(value, afterFeature);

      expect(reel.current, isA<HomeNoticeYesterday>());
      expect(reel.turns, turns);
    });

    test('멈춘 줄의 숫자는 넘기지 않고 바꾼다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(today: 20), afterFeature);
      final turns = reel.turns;

      reel.receive(activity(today: 21), afterFeature);

      expect((reel.current as HomeNoticeToday).count, 21);
      expect(reel.turns, turns);
    });

    test('⚠️ 지금 달리는 수에서 멈춘 띠는 모두 끝나면 새 기능 안내로 돌아간다', () {
      // 안 돌아가면 0명이 된 뒤에도 `지금 3명이 달리고 있어요`가 선다
      // (코덱스 리뷰 지적).
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3), afterFeature);
      expect(reel.stopped, isTrue);

      reel.receive(activity(), afterFeature);

      expect(reel.current, isA<HomeNoticeFeature>());
    });

    test('지금 달리는 수에서 멈춘 띠는 오늘 수가 생기면 그리로 옮긴다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3), afterFeature);
      final turns = reel.turns;

      reel.receive(activity(now: 2, today: 1), afterFeature);

      expect((reel.current as HomeNoticeToday).count, 1);
      expect(reel.turns, greaterThan(turns));
    });

    test('지금 달리는 수에서 멈춘 띠는 숫자만 바꾼다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3), afterFeature);
      final turns = reel.turns;

      reel.receive(activity(now: 2), afterFeature);

      expect((reel.current as HomeNoticeRunningNow).count, 2);
      expect(reel.turns, turns);
    });

    test('⚠️ 처음 값이 홈에 들어온 뒤에 오면 그때 한 바퀴 돈다', () {
      // 연결 직후에는 값이 없다(최대 30초). 그동안 띠는 새 기능 안내다.
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(null, afterFeature);

      reel.receive(activity(now: 3, today: 20), afterFeature);

      expect(reel.current, isA<HomeNoticeRunningNow>());
      expect(reel.stopped, isFalse);
    });

    test('⚠️ 기다리던 새 기능 안내는 첫 값이 와도 다시 넘기지 않는다', () {
      // 넘기면 같은 문장이 한 번 더 밀려 올라온다(에뮬레이터에서 봄).
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(null, featureWeek);
      final turns = reel.turns;

      reel.receive(activity(now: 3, today: 20), featureWeek);

      expect(reel.current, isA<HomeNoticeFeature>());
      expect(reel.turns, turns);
      expect(reel.stopped, isFalse);
    });

    test('값이 끊기면 새 기능 안내로 돌아간다', () {
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(activity(now: 3, today: 20), afterFeature);

      reel.receive(null, afterFeature);

      expect(reel.current, isA<HomeNoticeFeature>());
    });

    test('홈에 다시 들어오면 본 완주도 한 바퀴에 다시 나온다', () {
      final value = activity(runs: [run(1)], today: 1);
      final reel = HomeNoticeReel(featureSince: since)
        ..restart(value, afterFeature);
      playOut(reel);

      reel.restart(value, afterFeature);

      expect(reel.current, isA<HomeNoticeFinished>());
    });
  });
}
