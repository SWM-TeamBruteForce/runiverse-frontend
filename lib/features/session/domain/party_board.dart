import 'package:runiverse/features/session/domain/run_progress.dart';

/// 함께 뛰는 사람 하나의 **표시 정보.**
///
/// ## ⚠️ 러닝 중에는 이것을 받을 길이 없다
///
/// 진행·콤보 통지는 `userId`만 싣고, 명세가 정한 출처인 `RUNNING_STARTED`
/// 스냅샷은 서버가 비워 보낸다. 그래서 **대기방에서 받아 둔 것을 들고 들어온다.**
///
/// 러닝 중에 앱을 재시작하면 이 명단이 사라진다. 그때는 이름 없이 그린다 —
/// 수치는 `userId`만으로 그려지므로 진행률·격차·콤보는 그대로 보인다.
/// (`devlog/2026-09-16-버그수정-러닝-파티원-표시정보.md`)
class PartyMember {
  const PartyMember({
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
  });

  final String userId;
  final String nickname;

  /// ⚠️ **TTL이 있는 presigned URL이다.** 오래 들고 있으면 만료된다 —
  /// 저장해 두고 다음 실행에서 쓰면 사진이 뜨지 않는다.
  final String? profileImageUrl;
}

/// 화면에 그릴 한 줄.
class PartyRow {
  const PartyRow({
    required this.userId,
    this.member,
    this.progress,
    this.combo,
    this.isMe = false,
    this.gapMeters,
  });

  final String userId;

  /// 누구인지. **모를 수 있다** — 그때는 화면이 익명으로 그린다.
  final PartyMember? member;

  /// 어디까지 갔는가. 아직 한 번도 안 왔으면 `null`이다.
  final RunProgress? progress;

  /// 나와의 콤보. 겹치지 않으면 `null`이다.
  final ComboPeer? combo;

  /// 내 줄인가. 내 수치는 서버가 아니라 앱이 잰 것이라 [progress]가 없다 —
  /// [PartyBoard.myDistanceMeters]를 쓴다.
  final bool isMe;

  /// 나와의 격차(m). **양수면 상대가 앞이다.**
  ///
  /// 서버 콤보 통지의 `gapMeters`를 우선한다 — 시간 보정까지 한 값이라 더 정확하다.
  /// 콤보가 없으면 서버 거리와 내 거리의 차로 만든다. 내 줄이거나 통지가 아직
  /// 없으면 `null`이다.
  final int? gapMeters;
}

/// 파티원 명단과 통지를 맞춰 화면 줄을 만든다.
///
/// ## 순서는 고정이다 (2026-09-18 결정)
///
/// **나는 맨 위, 나머지는 대기실 명단 순.** 명단에 없는데 통지만 오는 사람은
/// 그 뒤에 `userId` 순으로 붙는다. 거리로 자리를 바꾸지 않는다.
///
/// 정본 S13은 "진행률 높은 순"이었고 10m 히스테리시스까지 두었지만, 진행과
/// 콤보 통지가 10초마다 같이 오는 화면에서 카드까지 자리를 옮기면 너무 혼잡했다.
/// 앞뒤는 막대 길이와 격차 문장으로 충분히 보인다. 등수 숫자는 여전히 금지다
/// (`CLAUDE.md`의 "순위(1등/2등) 표시" 금지).
class PartyBoard {
  const PartyBoard({
    this.roster = const [],
    this.progress = const {},
    this.combos = const {},
    this.bestCombos = const {},
    this.myDistanceMeters = 0,
    this.myUserId = meId,
  });

  /// 내 `userId`를 모를 때의 자리. 솔로처럼 명단이 없으면 실제 ID가 필요 없다.
  static const meId = '@me';

  /// 이만큼 통지가 없으면 끊긴 것으로 **보인다.** 서버가 콤보 판정에서 오래된
  /// 거리를 빼는 기준(`running-combo.freshness`)과 같다.
  static const staleAfter = Duration(seconds: 19);

  /// 대기방에서 들고 온 명단. **화면 순서 그 자체다.**
  final List<PartyMember> roster;

  /// `userId` → 마지막 진행. 통지가 갱신분만 실어 오므로 여기에 덮는다.
  final Map<String, RunProgress> progress;

  /// `userId` → 나와의 콤보. **통이 올 때마다 통째로 갈린다.**
  final Map<String, ComboPeer> combos;

  /// `userId` → 이 러닝에서 그 사람과 이어 본 최고 콤보.
  ///
  /// ⚠️ [combos]는 끊기면 목록에서 빠져 최고값도 같이 사라진다. 콤보가 없을 때
  /// 카드에 "최고 N"을 남기려면 따로 기억해야 한다. 서버 `maxComboCount`와
  /// 지금 세는 값 중 큰 쪽을 둔다.
  final Map<String, int> bestCombos;

  /// **앱이 잰 내 거리.** 서버는 본인 진행을 보내지 않는다.
  final int myDistanceMeters;

  /// 명단에서 나를 가려내는 열쇠.
  ///
  /// ⚠️ 대기방 명단은 **방 전원**이라 나도 들어 있다. 서버는 내 진행을 보내지
  /// 않으므로 이 줄을 파티원으로 두면 0m에 영영 멈춘 내 이름이 "나" 레인 옆에
  /// 또 뜬다. 그래서 이 ID의 줄이 곧 내 레인이다.
  final String myUserId;

  /// 나를 포함한 모든 줄. **나, 명단 순, 낯선 사람 순.**
  ///
  /// 명단에 없는데 통지만 오는 사람도 **버리지 않는다.** 러닝 중 재시작하면
  /// 명단이 비어 있는데, 그때 통지까지 버리면 화면이 통째로 빈다.
  List<PartyRow> get lanes {
    final byId = {for (final member in roster) member.userId: member};
    return [
      for (final userId in _order())
        if (userId == myUserId)
          PartyRow(userId: userId, member: byId[userId], isMe: true)
        else
          PartyRow(
            userId: userId,
            member: byId[userId],
            progress: progress[userId],
            combo: combos[userId],
            gapMeters:
                combos[userId]?.gapMeters ??
                switch (progress[userId]) {
                  final RunProgress p => p.distanceMeters - myDistanceMeters,
                  null => null,
                },
          ),
    ];
  }

  /// 레인 색의 자리. 화면이 이 번호로 팔레트에서 색을 꺼낸다.
  ///
  /// 정본은 "각자의 색"인데 시그니처 컬러는 아직 없다. **명단 순서로** 돌린다 —
  /// 명단은 서버가 준 순서라 어느 기기에서 봐도 같은 사람이 같은 자리다.
  /// 명단에 없는 사람은 그 뒤에 `userId` 순으로 붙는다. 통지가 온 순서로 주면
  /// 재시작할 때마다 색이 바뀐다.
  int colorSlotOf(String userId) {
    final index = roster.indexWhere((member) => member.userId == userId);
    if (index >= 0) return index;

    // 명단에 내가 없으면(솔로·재시작) 명단 바로 뒤가 내 자리, 낯선 사람은 그 뒤다.
    // ⚠️ 나를 0으로 두면 명단이 비었을 때 첫 낯선 사람과 같은 색이 된다.
    final meInRoster = roster.any((member) => member.userId == myUserId);
    if (userId == myUserId) return roster.length;
    final base = meInRoster ? roster.length : roster.length + 1;

    final strangers =
        progress.keys
            .where(
              (id) =>
                  id != myUserId &&
                  !roster.any((member) => member.userId == id),
            )
            .toList()
          ..sort();
    final offset = strangers.indexOf(userId);
    return base + (offset < 0 ? 0 : offset);
  }

  /// 그 사람과의 최고 콤보. 이어 본 적이 없으면 0.
  int bestComboOf(String userId) => bestCombos[userId] ?? 0;

  /// 내 최고 콤보 — 모든 상대 중 가장 높은 것.
  int get myBestCombo =>
      bestCombos.values.fold(0, (best, count) => count > best ? count : best);

  /// 파티원 줄만. 솔로면 비어 있다.
  List<PartyRow> get rows => [
    for (final lane in lanes)
      if (!lane.isMe) lane,
  ];

  /// 진행 통지 하나를 덮는다.
  PartyBoard withProgress(RunProgress update) =>
      _with(progress: {...progress, update.userId: update});

  /// 콤보를 통째로 갈아끼운다.
  ///
  /// ⚠️ **합치지 않는다.** 끊긴 상대는 목록에서 빠지는 것으로 끊김을 알리므로,
  /// 기존 값에 덧붙이면 끊긴 콤보가 화면에 영영 남는다.
  PartyBoard withCombos(RunCombo update) {
    final best = {...bestCombos};
    for (final peer in update.peers) {
      final seen = peer.maxComboCount > peer.comboCount
          ? peer.maxComboCount
          : peer.comboCount;
      if (seen > (best[peer.userId] ?? 0)) best[peer.userId] = seen;
    }
    return _with(
      combos: {for (final peer in update.peers) peer.userId: peer},
      bestCombos: best,
    );
  }

  /// 명단을 들여온다. 러닝을 시작할 때 한 번.
  ///
  /// [myUserId]를 함께 주면 그 줄을 내 레인으로 삼는다.
  PartyBoard withRoster(List<PartyMember> members, {String? myUserId}) =>
      _with(roster: members, myUserId: myUserId);

  /// 내 거리를 갱신한다. 내 줄도 같은 규칙으로 섞인다.
  PartyBoard withMyDistance(int meters) => _with(myDistanceMeters: meters);

  PartyBoard _with({
    List<PartyMember>? roster,
    Map<String, RunProgress>? progress,
    Map<String, ComboPeer>? combos,
    Map<String, int>? bestCombos,
    int? myDistanceMeters,
    String? myUserId,
  }) => PartyBoard(
    roster: roster ?? this.roster,
    progress: progress ?? this.progress,
    combos: combos ?? this.combos,
    bestCombos: bestCombos ?? this.bestCombos,
    myDistanceMeters: myDistanceMeters ?? this.myDistanceMeters,
    myUserId: myUserId ?? this.myUserId,
  );

  /// 나 → 명단 순(나 제외) → 명단에 없는 사람 `userId` 순.
  ///
  /// 낯선 사람을 `userId`로 고정하는 이유: 통지가 온 순서로 두면 재시작할 때마다
  /// 줄이 달라지고, 무엇으로든 고정해야 줄이 깜빡이지 않는다.
  List<String> _order() {
    final named = [
      for (final member in roster)
        if (member.userId != myUserId) member.userId,
    ];
    final strangers =
        progress.keys
            .where((id) => id != myUserId && !named.contains(id))
            .toList()
          ..sort();
    return [myUserId, ...named, ...strangers];
  }
}
