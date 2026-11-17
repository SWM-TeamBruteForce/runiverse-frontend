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

/// 새 기능 안내. 다른 소식이 하나도 없을 때도 이 줄이 선다.
class HomeNoticeFeature extends HomeNoticeLine {
  const HomeNoticeFeature();
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
/// 홈에 들어오면 `새 기능 → 지금 달리는 수 → 오늘 완주 → 오늘(어제) 수`를 한
/// 번 돌고 마지막 줄에서 멈춘다. 계속 돌면 산만하고, 30초마다 오는 값마다
/// 처음부터 돌리면 첫 줄만 보게 된다.
///
/// 그 뒤에 **처음 보는 완주**가 오면 그 줄만 보여 주고 다시 마지막 줄로
/// 간다.
///
/// ## 시간은 모른다
///
/// 줄을 넘기는 시계는 화면이 쥔다([advance]를 부른다). 여기는 순서만 안다.
class HomeNoticeReel {
  HomeNoticeReel({required this.featureSince});

  /// 새 기능이 나온 날. 그날부터 [featureDays]일 동안 띠 맨 앞에 선다.
  final DateTime featureSince;

  static const featureDays = 7;

  List<HomeNoticeLine> _lines = const [HomeNoticeFeature()];
  var _index = 0;

  /// 지금 줄이 [HomeNoticeFeature] 하나뿐인 까닭이 **소식이 없어서**인가.
  ///
  /// 그 상태에서 소식이 생기면 한 바퀴를 새로 돈다. 안 그러면 누가 달리기
  /// 시작해도 다음에 홈에 들어올 때까지 새 기능 안내만 서 있다.
  var _empty = true;

  /// 이미 보여 준 완주. 같은 완주가 30초마다 다시 와도 또 띄우지 않는다.
  final _seen = <int>{};

  /// 줄이 바뀐 횟수. 화면이 넘김 애니메이션의 키로 쓴다 — 같은 줄의 숫자만
  /// 바뀌면 넘기지 않고 그 자리에서 글자만 바꾼다.
  var _turns = 0;

  HomeNoticeLine get current => _lines[_index];

  int get turns => _turns;

  /// 마지막 줄에 섰는가. 더 넘길 것이 없다.
  bool get stopped => _index == _lines.length - 1;

  /// 처음부터 한 바퀴 돈다. 홈을 열 때와 홈 탭으로 돌아올 때 부른다.
  void restart(HomeActivity? activity, DateTime now) {
    if (activity != null) {
      _seen.addAll(activity.todayFinishedRuns.map((r) => r.runningRecordId));
    }
    _play(_lap(activity, now));
  }

  /// 새 값이 왔다. **처음부터 다시 돌리지 않는다.**
  ///
  /// `null`이면 값이 끊겼다(90초 동안 안 왔다) — 소식을 내리고 새 기능 안내로
  /// 돌아간다.
  void receive(HomeActivity? activity, DateTime now) {
    if (activity == null) {
      if (!_empty) _play(const []);
      return;
    }

    // 소식이 없던 띠에 소식이 생겼다. 홈에 들어올 때 못 돈 한 바퀴를 지금 돈다.
    if (_empty) {
      restart(activity, now);
      return;
    }

    final fresh = [
      for (final run in activity.todayFinishedRuns)
        if (_seen.add(run.runningRecordId)) HomeNoticeFinished(run),
    ];
    final rest = _rest(activity);

    if (fresh.isNotEmpty) {
      if (stopped) {
        _play([...fresh, ?rest]);
        return;
      }
      // ⚠️ **도는 중이면 처음부터 다시 깔지 않는다.** 깔면 이번 바퀴에 남은
      // 완주 줄이 안 뜨고, 이미 본 것으로 쳐져 다음에도 안 나온다. 머물 줄
      // 앞에 끼워 넣어 이어서 돈다.
      _lines = [..._head(activity, rest), ...fresh, ?rest];
      return;
    }

    // ⚠️ **멈춘 줄도 새 값에 맞춘다.** 안 맞추면 `지금 3명이 달리고 있어요`에서
    // 멈춘 띠가, 다 끝나 0명이 된 뒤에도 홈에 다시 들어올 때까지 그대로 선다.
    if (rest == null) {
      // 도는 중이면 끝까지 돌게 두고, 다음 값에서 멈춘 줄을 내린다.
      if (stopped) _play(const []);
      return;
    }
    if (stopped && current.runtimeType != rest.runtimeType) {
      _play([rest]);
      return;
    }
    // 같은 종류의 줄이면 숫자만 바꾼다. 줄은 그대로라 넘기지 않는다.
    _lines = [..._head(activity, rest), rest];
  }

  /// 머물 줄을 새로 붙이기 전의 앞부분.
  ///
  /// 마지막 줄이 오늘·어제 수면 뺀다 — 새 머물 줄이 그 자리에 선다.
  ///
  /// ⚠️ **`지금 N명`이면 빼지 않는다.** 오늘·어제 수가 없던 바퀴에서는 이 줄이
  /// ①과 머물 줄을 겸한다. 새 머물 줄이 오늘·어제 수면 이 줄은 ①로 남아야
  /// 한다 — 빼면 이번 바퀴에서 `지금 N명`이 사라진다. 숫자는 새 값으로 바꾸고,
  /// 0명이 됐거나 새 머물 줄도 `지금 N명`이면 뺀다.
  List<HomeNoticeLine> _head(HomeActivity activity, HomeNoticeLine? rest) {
    final head = _lines.sublist(0, _lines.length - 1);
    return switch (_lines.last) {
      HomeNoticeToday() || HomeNoticeYesterday() => head,
      HomeNoticeRunningNow()
          when activity.runningNowCount > 0 && rest is! HomeNoticeRunningNow =>
        [...head, HomeNoticeRunningNow(activity.runningNowCount)],
      HomeNoticeRunningNow() => head,
      final last => [...head, last],
    };
  }

  /// 다음 줄로. 마지막 줄이면 그대로 둔다.
  void advance() {
    if (stopped) return;
    _index++;
    _turns++;
  }

  void _play(List<HomeNoticeLine> lines) {
    // ⚠️ **지금 줄과 새 첫 줄이 같은 문장이면 넘기지 않는다.** 넘기면 같은
    // 문장이 한 번 더 밀려 올라온다 — 값을 기다리던 새 기능 안내에 첫 값이
    // 올 때, 한 줄짜리 바퀴(`어제 12명`)에서 탭을 옮겼다 올 때가 그렇다.
    final next = lines.isEmpty ? const HomeNoticeFeature() : lines.first;
    final same = _sameText(current, next);
    _lines = lines.isEmpty ? const [HomeNoticeFeature()] : lines;
    _empty = lines.isEmpty;
    _index = 0;
    if (!same) _turns++;
  }

  /// 홈에 들어왔을 때 도는 한 바퀴. 소식이 하나도 없으면 비어 있다.
  List<HomeNoticeLine> _lap(HomeActivity? activity, DateTime now) {
    if (activity == null) return const [];
    final news = [
      if (activity.runningNowCount > 0)
        HomeNoticeRunningNow(activity.runningNowCount),
      for (final run in activity.todayFinishedRuns) HomeNoticeFinished(run),
      ?_stop(activity),
    ];
    if (news.isEmpty) return const [];
    return [if (_featureShown(now)) const HomeNoticeFeature(), ...news];
  }

  /// 띠가 멈출 줄. 오늘이 어제 이상이면 오늘, 아니면 어제다.
  static HomeNoticeLine? _stop(HomeActivity activity) {
    final today = activity.todayFinishedCount;
    final yesterday = activity.yesterdayFinishedCount;
    if (today > 0 && today >= yesterday) return HomeNoticeToday(today);
    if (yesterday > 0) return HomeNoticeYesterday(yesterday);
    return null;
  }

  /// 띠가 머물 줄. 오늘(어제) 수가 없으면 지금 달리는 수다.
  static HomeNoticeLine? _rest(HomeActivity activity) =>
      _stop(activity) ??
      (activity.runningNowCount > 0
          ? HomeNoticeRunningNow(activity.runningNowCount)
          : null);

  /// 화면에 같은 문장으로 그려지는가.
  static bool _sameText(HomeNoticeLine a, HomeNoticeLine b) => switch ((a, b)) {
    (HomeNoticeFeature(), HomeNoticeFeature()) => true,
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

  bool _featureShown(DateTime now) =>
      !now.isBefore(featureSince) &&
      now.isBefore(featureSince.add(const Duration(days: featureDays)));
}
