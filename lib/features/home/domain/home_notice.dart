/// 오늘 끝낸 러닝 하나. 공지 띠의 `철** 님이 5 km 달렸어요`가 된다.
class FinishedRun {
  const FinishedRun({
    required this.runningRecordId,
    required this.nickname,
    required this.distanceMeters,
  });

  /// 처음 보는 완주를 가리는 기준이다([HomeNoticeReel.receive]).
  final int runningRecordId;

  /// **서버가 가려서 보낸다**(`철**`). 앱이 다시 가리지 않는다.
  final String nickname;

  /// 목표 거리. 목표 없이 혼자 달렸으면 실제로 달린 거리다.
  final int distanceMeters;
}

/// 앱 스트림 `HOME_ACTIVITY` — 다른 러너들이 지금·오늘·어제 달린 것.
///
/// 서버가 30초마다 그 서버에 붙은 연결 전부에 보낸다. 연결 직후에는 오지
/// 않는다.
class HomeActivity {
  const HomeActivity({
    required this.runningNowCount,
    required this.todayFinishedRuns,
    required this.todayFinishedCount,
    required this.yesterdayFinishedCount,
  });

  final int runningNowCount;

  /// 최신 순, 최대 3건.
  final List<FinishedRun> todayFinishedRuns;

  /// 오늘·어제 완주한 **사람** 수. 한 사람이 두 번 달려도 하나다.
  final int todayFinishedCount;
  final int yesterdayFinishedCount;
}

/// 공지 띠의 한 줄.
sealed class HomeNoticeLine {
  const HomeNoticeLine();
}

/// 그 버전의 업데이트 소식. 나온 날부터 1주일만 한 바퀴 맨 앞에 선다.
class HomeNoticeUpdate extends HomeNoticeLine {
  const HomeNoticeUpdate();
}

/// 워치 앱 안내. **늘** 한 바퀴에 한 번 지나가고, 소식이 하나도 없으면 이
/// 줄에서 멈춘다 — 띠가 비지 않게 하는 바탕 줄이다.
class HomeNoticeWatch extends HomeNoticeLine {
  const HomeNoticeWatch();
}

/// `지금 3명이 달리고 있어요`.
class HomeNoticeRunningNow extends HomeNoticeLine {
  const HomeNoticeRunningNow(this.count);

  final int count;
}

/// `철** 님이 5 km 달렸어요`.
class HomeNoticeFinished extends HomeNoticeLine {
  const HomeNoticeFinished(this.run);

  final FinishedRun run;
}

/// `오늘 20명이 달렸어요`. 띠가 여기서 멈춘다.
class HomeNoticeToday extends HomeNoticeLine {
  const HomeNoticeToday(this.count);

  final int count;
}

/// `어제 12명이 달렸어요`. 오늘이 어제보다 적을 때 [HomeNoticeToday] 자리에
/// 선다 — 아침에 `오늘 1명`을 띄우면 앱이 죽어 보인다.
class HomeNoticeYesterday extends HomeNoticeLine {
  const HomeNoticeYesterday(this.count);

  final int count;
}

/// 공지 띠가 지금 어느 줄을 보여 주는가.
///
/// ## 한 번 돌고 멈춘다
///
/// 홈에 들어오면 `업데이트 → 지금 달리는 수 → 오늘 완주 → 워치 → 오늘(어제)
/// 수`를 한 번 돌고 마지막 줄에서 멈춘다. 계속 돌면 산만하고, 30초마다 오는
/// 값마다 처음부터 돌리면 첫 줄만 보게 된다.
///
/// - 업데이트는 가장 많이 보이는 첫 줄에 둔다. 홈은 오래 머무는 화면이 아니라
///   첫 5초에 뜨는 줄을 가장 많이 본다.
/// - 워치는 매일 같은 문장이라 멈출 줄 바로 앞에 둔다.
/// - 소식이 하나도 없으면 `업데이트 → 워치`(업데이트 기간이 아니면 워치 한 줄).
///
/// 그 뒤에 **처음 보는 완주**가 오면 그 줄만 보여 주고 다시 머물 줄로 간다.
///
/// ## 시간은 모른다
///
/// 줄을 넘기는 시계는 화면이 쥔다([advance]를 부른다). 여기는 순서만 안다.
class HomeNoticeReel {
  HomeNoticeReel({this.updateSince});

  /// 업데이트 소식이 나온 날. 그날부터 [updateDays]일 동안 맨 앞에 선다.
  /// `null`이면 업데이트 줄이 없다.
  final DateTime? updateSince;

  static const updateDays = 7;

  List<HomeNoticeLine> _lines = const [HomeNoticeWatch()];
  var _index = 0;

  /// 지금 바퀴가 **소식 없는** 바탕 바퀴인가.
  ///
  /// 그 상태에서 소식이 생기면 한 바퀴를 새로 돈다. 안 그러면 누가 달리기
  /// 시작해도 다음에 홈에 들어올 때까지 워치 줄만 서 있다.
  var _empty = true;

  /// 이미 보여 준 완주. 같은 완주가 30초마다 다시 와도 또 띄우지 않는다.
  final _seen = <int>{};

  /// 이번에 홈에 들어와서 업데이트 줄을 이미 띄웠는가. 홈에 다시 들어오기
  /// 전에는 또 띄우지 않는다 — 소식이 사라졌다 다시 생겨 바퀴를 새로 깔 때
  /// 같은 소식이 한 번 더 뜬다.
  var _updateDone = false;

  /// 줄이 바뀐 횟수. 화면이 넘김 애니메이션의 키로 쓴다 — 같은 줄의 숫자만
  /// 바뀌면 넘기지 않고 그 자리에서 글자만 바꾼다.
  var _turns = 0;

  HomeNoticeLine get current => _lines[_index];

  int get turns => _turns;

  /// 마지막 줄에 섰는가. 더 넘길 것이 없다.
  bool get stopped => _index == _lines.length - 1;

  /// 처음부터 한 바퀴 돈다. 홈을 열 때와 홈이 다시 보일 때 부른다.
  void restart(HomeActivity? activity, DateTime now) {
    _updateDone = false;
    _start(activity, now);
  }

  void _start(HomeActivity? activity, DateTime now) {
    if (activity != null) {
      _seen.addAll(activity.todayFinishedRuns.map((r) => r.runningRecordId));
    }
    if (activity != null && _hasNews(activity)) {
      _play(_lap(activity, now), empty: false);
    } else {
      _play(_base(now), empty: true);
    }
  }

  /// 새 값이 왔다. **처음부터 다시 돌리지 않는다.**
  ///
  /// `null`이면 값이 끊겼다(90초 동안 안 왔다) — 소식이 없는 값과 똑같이
  /// 소식을 내린다.
  void receive(HomeActivity? activity, DateTime now) {
    // ⚠️ **소식이 사라지면 도는 중이어도 바로 워치 줄로 간다.** 남은 줄을 두면
    // 다음 차례에 지난 숫자(`어제 5명` 등)가 뜨고 거기서 멈춘다 — 자정을 넘길
    // 때 그렇다. 업데이트 줄을 보여 주는 중이면 그 뒤를 워치 줄로 잇는다 —
    // 바탕 바퀴를 처음부터 다시 깔면 이미 본 업데이트 줄이 또 뜬다.
    if (activity == null || !_hasNews(activity)) {
      if (_empty) return;
      if (current is HomeNoticeUpdate && !stopped) {
        _lines = [current, const HomeNoticeWatch()];
        _empty = true;
      } else {
        _play(const [HomeNoticeWatch()], empty: true);
      }
      return;
    }

    // 소식이 없던 띠에 소식이 생겼다. 홈에 들어올 때 못 돈 한 바퀴를 지금 돈다.
    if (_empty) {
      _start(activity, now);
      return;
    }

    final fresh = [
      for (final run in activity.todayFinishedRuns)
        if (_seen.add(run.runningRecordId)) HomeNoticeFinished(run),
    ];
    final stop = _stop(activity);

    if (stopped) {
      // 머물 줄. 오늘(어제) 수가 없으면 워치 줄에 머문다.
      final rest = stop ?? const HomeNoticeWatch();
      if (fresh.isNotEmpty) {
        _play([...fresh, rest], empty: false);
      } else if (current.runtimeType == rest.runtimeType) {
        // 같은 종류의 줄이면 숫자만 바꾼다. 줄은 그대로라 넘기지 않는다.
        _lines = [..._lines.sublist(0, _index), rest];
      } else {
        _play([rest], empty: false);
      }
      return;
    }

    // ⚠️ **도는 중이면 처음부터 다시 깔지 않는다.** 깔면 이번 바퀴에 남은
    // 완주 줄이 안 뜨고, 이미 본 것으로 쳐져 다음에도 안 나온다. 아직 안 본
    // 줄은 새 값으로 고치고, 새 완주는 워치·머물 줄 앞에 끼워 넣어 이어서
    // 돈다.
    final ahead = _lines.sublist(_index + 1);
    final watchAhead = ahead.any((l) => l is HomeNoticeWatch);
    _lines = [
      ..._lines.sublist(0, _index + 1),
      for (final line in ahead)
        ...switch (line) {
          HomeNoticeRunningNow() when activity.runningNowCount > 0 => [
            HomeNoticeRunningNow(activity.runningNowCount),
          ],
          HomeNoticeRunningNow() ||
          HomeNoticeWatch() ||
          HomeNoticeToday() ||
          HomeNoticeYesterday() => const <HomeNoticeLine>[],
          _ => [line],
        },
      ...fresh,
      if (watchAhead) const HomeNoticeWatch(),
      ?stop,
    ];
  }

  /// 다음 줄로. 마지막 줄이면 그대로 둔다.
  void advance() {
    if (stopped) return;
    _index++;
    _turns++;
  }

  void _play(List<HomeNoticeLine> lines, {required bool empty}) {
    // ⚠️ **지금 줄과 새 첫 줄이 같은 문장이면 넘기지 않는다.** 넘기면 같은
    // 문장이 한 번 더 밀려 올라온다 — 값을 기다리던 워치 줄에 첫 값이 올 때,
    // 한 줄짜리 바퀴(`어제 12명`)에서 홈에 다시 들어올 때가 그렇다.
    final same = _sameText(current, lines.first);
    _lines = lines;
    _empty = empty;
    _index = 0;
    if (!same) _turns++;
    if (lines.first is HomeNoticeUpdate) _updateDone = true;
  }

  /// 업데이트 줄을 바퀴 맨 앞에 둘까. 기간 안이고 이번 방문에서 아직 안
  /// 띄웠거나, **지금 띄우고 있는 중**이면 둔다 — 띄우던 줄을 갑자기 다른 줄로
  /// 바꾸지 않는다.
  bool _updateFirst(DateTime now) =>
      _updateShown(now) && (!_updateDone || current is HomeNoticeUpdate);

  /// 소식이 있을 때 도는 한 바퀴.
  List<HomeNoticeLine> _lap(HomeActivity activity, DateTime now) => [
    if (_updateFirst(now)) const HomeNoticeUpdate(),
    if (activity.runningNowCount > 0)
      HomeNoticeRunningNow(activity.runningNowCount),
    for (final run in activity.todayFinishedRuns) HomeNoticeFinished(run),
    const HomeNoticeWatch(),
    ?_stop(activity),
  ];

  /// 소식이 하나도 없을 때의 바퀴. 워치 줄에서 멈춘다.
  List<HomeNoticeLine> _base(DateTime now) => [
    if (_updateFirst(now)) const HomeNoticeUpdate(),
    const HomeNoticeWatch(),
  ];

  static bool _hasNews(HomeActivity activity) =>
      activity.runningNowCount > 0 ||
      activity.todayFinishedRuns.isNotEmpty ||
      _stop(activity) != null;

  /// 띠가 멈출 줄. 오늘이 어제 이상이면 오늘, 아니면 어제다.
  static HomeNoticeLine? _stop(HomeActivity activity) {
    final today = activity.todayFinishedCount;
    final yesterday = activity.yesterdayFinishedCount;
    if (today > 0 && today >= yesterday) return HomeNoticeToday(today);
    if (yesterday > 0) return HomeNoticeYesterday(yesterday);
    return null;
  }

  /// 화면에 같은 문장으로 그려지는가.
  static bool _sameText(HomeNoticeLine a, HomeNoticeLine b) => switch ((a, b)) {
    (HomeNoticeUpdate(), HomeNoticeUpdate()) => true,
    (HomeNoticeWatch(), HomeNoticeWatch()) => true,
    (
      HomeNoticeRunningNow(count: final x),
      HomeNoticeRunningNow(count: final y),
    ) =>
      x == y,
    (HomeNoticeFinished(run: final x), HomeNoticeFinished(run: final y)) =>
      x.runningRecordId == y.runningRecordId,
    (HomeNoticeToday(count: final x), HomeNoticeToday(count: final y)) =>
      x == y,
    (
      HomeNoticeYesterday(count: final x),
      HomeNoticeYesterday(count: final y),
    ) =>
      x == y,
    _ => false,
  };

  bool _updateShown(DateTime now) {
    final since = updateSince;
    return since != null &&
        !now.isBefore(since) &&
        now.isBefore(since.add(const Duration(days: updateDays)));
  }
}
