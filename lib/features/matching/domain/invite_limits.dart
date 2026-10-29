/// 초대 방의 운영값.
///
/// ## ⚠️ 서버가 내려주지 않아 앱이 적어 둔다
///
/// 매칭에는 `GET /match-rooms/slots`가 고를 수 있는 시각과 거리를 내려줘서
/// 앱이 범위를 알 필요가 없었다. **초대에는 그런 API가 없다.** 그래서 여기
/// 적어 두고, 서버가 바꾸면 `INVITE_START_AT_OUT_OF_RANGE`·`INVALID_REQUEST`로
/// 알게 된다.
///
/// 값을 바꿀 자리를 한 곳으로 모은 이유가 그것이다 — 화면 세 곳에 흩어지면
/// 서버 정책이 바뀌는 날 한 곳만 고치는 사고가 난다.
abstract final class InviteLimits {
  const InviteLimits._();

  /// 서버가 요구하는 최소 리드타임. **"지금 +10분" 이후만 받는다.**
  static const minLeadMinutes = 10;

  /// 피커가 실제로 세우는 바닥. [minLeadMinutes]보다 **1분 늦다.**
  ///
  /// ## ⚠️ 기기 시계를 믿지 않는다
  ///
  /// 이 화면은 앱이 **처음으로 `scheduledStartAt`을 직접 만드는 자리**다
  /// (`match_slot.dart`는 서버 문자열을 되돌려 보낼 뿐이다). 기기 시계가 몇 분
  /// 느리면 화면에서 합법이던 값이 서버에서 거절된다 — 사용자는 방금 고른
  /// 시각이 왜 안 되는지 알 수 없다.
  ///
  /// 1분으로 충분한지는 **서버가 무엇을 기준으로 재는지에 달렸다**(설계 §8-8,
  /// BE 확인 중). 이 저장소는 다른 곳에서도 기기 시계를 의심한다
  /// (`RunningReady.startsInMs`, `MatchRoomState.launchAt`).
  static const pickerLeadMinutes = 11;

  static const minMeters = 1000;

  /// 풀코스. **상한이자 [fullMeters]다.**
  static const maxMeters = 42195;

  /// 하프코스. 21,097.5m를 **올린 값이다.**
  ///
  /// ⚠️ 서버가 정수 미터만 받는다. 내리면 공인 거리보다 짧아진다.
  static const halfMeters = 21098;

  static const fullMeters = maxMeters;

  /// 거리 입력란을 채우는 바로가기 세 칸.
  ///
  /// ## ⚠️ 매칭의 3/5/10을 쓰지 않는다
  ///
  /// 그 셋은 **버킷** 때문에 있다 — `target_distance.dart`가 적어 둔 그대로
  /// "값이 흩어지면 매칭될 상대가 없어진다". 초대 방에는 버킷이 없다(상대를
  /// 직접 고른다). 그래서 **타자로 치기 고약하고 이름이 있는 거리**만 남긴다.
  ///
  /// 칩은 자유 입력을 대신하지 않는다 — 눌러서 입력란을 채운다.
  static const shortcuts = <({String label, int meters})>[
    (label: '5km', meters: 5000),
    (label: '하프', meters: halfMeters),
    (label: '풀', meters: fullMeters),
  ];

  /// 방 정원.
  static const capacity = 4;

  /// **내가** 한 친구에게 보낼 수 있는 초대 횟수(최초 포함).
  ///
  /// ⚠️ 보낸 사람별로 따로 센다 — A와 C가 같은 친구를 초대하면 각자 5회다.
  /// 남은 횟수를 서버가 내려주지 않아 앱이 셀 수도 없다(설계 §8-3).
  static const maxInvitesPerFriend = 5;

  /// 시작 몇 분 전에 모집이 닫히는가. **매칭 방은 10분이다.**
  static const closeBeforeMinutes = 1;

  /// 고를 수 있는 시작 시각의 범위.
  ///
  /// 바닥은 `지금 +[pickerLeadMinutes]분`, 천장은 **오늘 23:59**다. 익일
  /// 예약은 받지 않는다.
  ///
  /// ## ⚠️ `null`이면 오늘은 만들 수 없다
  ///
  /// 23:49 이후에는 바닥이 천장을 넘는다. **실제로 생기는 상태다** — 화면은
  /// 빈 피커를 두지 않고 "오늘은 초대 러닝을 만들 수 없어요"로 갈린다. 비어
  /// 있는 피커만 두면 고장으로 읽힌다.
  ///
  /// [nowKst]는 KST 기준의 벽시계 시각이다. **초와 밀리초는 버린다** — 서버가
  /// 분 단위를 받고, 버린 분으로 경계를 재야 23:48:59에 멀쩡한 1분을 잃지
  /// 않는다.
  static ({DateTime from, DateTime to})? window({required DateTime nowKst}) {
    final minute = DateTime(
      nowKst.year,
      nowKst.month,
      nowKst.day,
      nowKst.hour,
      nowKst.minute,
    );
    final from = minute.add(const Duration(minutes: pickerLeadMinutes));
    final to = DateTime(minute.year, minute.month, minute.day, 23, 59);

    if (from.isAfter(to)) return null;
    return (from: from, to: to);
  }

  /// 보낼 수 있는 거리인가.
  static bool allowsMeters(int meters) =>
      meters >= minMeters && meters <= maxMeters;
}
