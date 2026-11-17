import 'package:runiverse/features/home/domain/home_notice.dart';

/// 홈 공지 이벤트 `data`를 읽는다. **여기가 그 형식을 아는 유일한 곳이다.**
///
/// 못 읽으면 `null`이다 — 그 이벤트만 버리고, 화면은 마지막으로 받은 값을
/// 들고 있다가 90초가 지나면 내린다(`HomeNoticeController`).

/// `HOME_WAITING` `{"waitingCount": 4}`.
int? homeWaitingFromJson(Object? data) {
  if (data is! Map) return null;
  final count = data['waitingCount'];
  return count is int && count >= 0 ? count : null;
}

/// `HOME_ACTIVITY`.
///
/// ⚠️ **숫자 셋 중 하나라도 못 읽으면 통째로 버린다.** 하나를 0으로 채우면
/// `어제 0명` 같은 없는 사실이 띠에 선다. 완주 목록은 깨진 건만 건너뛴다 —
/// 하나 때문에 나머지 소식까지 버릴 까닭이 없다.
HomeActivity? homeActivityFromJson(Object? data) {
  if (data is! Map) return null;

  final now = data['runningNowCount'];
  final today = data['todayFinishedCount'];
  final yesterday = data['yesterdayFinishedCount'];
  if (now is! int || today is! int || yesterday is! int) return null;
  if (now < 0 || today < 0 || yesterday < 0) return null;

  final runs = data['todayFinishedRuns'];
  return HomeActivity(
    runningNowCount: now,
    todayFinishedRuns: runs is List
        ? [for (final run in runs) ?_finishedRunOf(run)]
        : const [],
    todayFinishedCount: today,
    yesterdayFinishedCount: yesterday,
  );
}

FinishedRun? _finishedRunOf(Object? wire) {
  if (wire is! Map) return null;
  final id = wire['runningRecordId'];
  final nickname = wire['nickname'];
  final meters = wire['distanceMeters'];
  if (id is! int || nickname is! String || nickname.isEmpty) return null;
  if (meters is! int || meters <= 0) return null;
  return FinishedRun(
    runningRecordId: id,
    nickname: nickname,
    distanceMeters: meters,
  );
}
