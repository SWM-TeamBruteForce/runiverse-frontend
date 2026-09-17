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
/// ## 진행률 순으로 세운다
///
/// 정본 S13이 "진행률 높은 순 정렬"을 명시한다. 금지된 것은 **등수 숫자**다 —
/// `1등`·`2등`을 적으면 경쟁 프레임이 되지만, 막대 길이로 앞뒤가 보이는 것은
/// 함께 달리는 감각에 필요하다(`CLAUDE.md`의 "순위(1등/2등) 표시" 금지).
///
/// ## ⚠️ 자리는 기준값만큼 앞서야 바뀐다
///
/// 나란히 달리는 두 사람은 통지마다 몇 미터씩 앞서거니 뒤서거니 한다. 거리순으로
/// 곧이곧대로 세우면 10초마다 줄이 서로 자리를 바꾸며 튄다. 그래서 **아래 줄이
/// 위 줄보다 [swapThresholdMeters] 이상 앞설 때만** 자리를 바꾸고, 바뀐 뒤에
/// 되돌리는 쪽도 같은 만큼이 필요하다(FE노트 S13). 그 기억이 [order]다.
///
/// 처음 세울 때는 기억이 없어 거리순이다. 같은 거리면 명단 순서를 지킨다.
class PartyBoard {
  const PartyBoard({
    this.roster = const [],
    this.progress = const {},
    this.combos = const {},
    this.myDistanceMeters = 0,
    this.myUserId = meId,
    this.order = const [],
  });

  /// 내 `userId`를 모를 때의 자리. 솔로처럼 명단이 없으면 실제 ID가 필요 없다.
  static const meId = '@me';

  /// 자리를 바꾸는 데 필요한 격차. 정책값이다.
  static const swapThresholdMeters = 10;

  /// 이만큼 통지가 없으면 끊긴 것으로 **보인다.** 서버가 콤보 판정에서 오래된
  /// 거리를 빼는 기준(`running-combo.freshness`)과 같다.
  static const staleAfter = Duration(seconds: 19);

  /// 대기방에서 들고 온 명단. **처음 세울 때의 동률 순서다.**
  final List<PartyMember> roster;

  /// `userId` → 마지막 진행. 통지가 갱신분만 실어 오므로 여기에 덮는다.
  final Map<String, RunProgress> progress;

  /// `userId` → 나와의 콤보. **통이 올 때마다 통째로 갈린다.**
  final Map<String, ComboPeer> combos;

  /// **앱이 잰 내 거리.** 서버는 본인 진행을 보내지 않는다.
  final int myDistanceMeters;

  /// 명단에서 나를 가려내는 열쇠.
  ///
  /// ⚠️ 대기방 명단은 **방 전원**이라 나도 들어 있다. 서버는 내 진행을 보내지
  /// 않으므로 이 줄을 파티원으로 두면 0m에 영영 멈춘 내 이름이 "나" 레인 옆에
  /// 또 뜬다. 그래서 이 ID의 줄이 곧 내 레인이다.
  final String myUserId;

  /// 지난번 화면 순서(나 포함). 히스테리시스의 기억이다.
  final List<String> order;

  /// 나를 포함한 모든 줄. **[order] 순서 그대로.**
  ///
  /// 명단에 없는데 통지만 오는 사람도 **버리지 않는다.** 러닝 중 재시작하면
  /// 명단이 비어 있는데, 그때 통지까지 버리면 화면이 통째로 빈다.
  List<PartyRow> get lanes {
    final byId = {for (final member in roster) member.userId: member};
    return [
      for (final userId in _reordered())
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
  PartyBoard withCombos(RunCombo update) =>
      _with(combos: {for (final peer in update.peers) peer.userId: peer});

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
    int? myDistanceMeters,
    String? myUserId,
  }) {
    final next = PartyBoard(
      roster: roster ?? this.roster,
      progress: progress ?? this.progress,
      combos: combos ?? this.combos,
      myDistanceMeters: myDistanceMeters ?? this.myDistanceMeters,
      myUserId: myUserId ?? this.myUserId,
      // 내 자리 이름이 바뀌면 옛 기억은 못 쓴다. 처음부터 다시 세운다.
      order: myUserId == null || myUserId == this.myUserId ? order : const [],
    );
    // 기억을 굳힌다. 다음 갱신은 이 순서에서 출발한다.
    return PartyBoard(
      roster: next.roster,
      progress: next.progress,
      combos: next.combos,
      myDistanceMeters: next.myDistanceMeters,
      myUserId: next.myUserId,
      order: next._reordered(),
    );
  }

  int _distanceOf(String userId) => userId == myUserId
      ? myDistanceMeters
      : progress[userId]?.distanceMeters ?? 0;

  /// 지난 순서에서 출발해 기준값을 넘긴 자리만 바꾼다.
  List<String> _reordered() {
    final rank = {
      for (var i = 0; i < roster.length; i++) roster[i].userId: i,
      // 명단에 내가 없으면(솔로·재시작) 맨 앞 동률로 둔다.
      if (!roster.any((member) => member.userId == myUserId)) myUserId: -1,
    };
    final ids = <String>{myUserId, ...rank.keys, ...progress.keys};

    // 처음 보는 사람은 거리순으로 뒤에 붙인다. 기억이 없을 때는 전부가 그렇다.
    final known = order.where(ids.contains).toList();
    final fresh = ids.where((id) => !known.contains(id)).toList()
      ..sort((a, b) {
        final byDistance = _distanceOf(b).compareTo(_distanceOf(a));
        if (byDistance != 0) return byDistance;
        // 명단에 없는 사람은 뒤로. 그들끼리는 `userId`로 순서를 고정한다 —
        // 무엇으로든 고정해야 줄이 깜빡이지 않는다.
        final ai = rank[a] ?? roster.length;
        final bi = rank[b] ?? roster.length;
        return ai != bi ? ai.compareTo(bi) : a.compareTo(b);
      });
    final result = [...known, ...fresh];

    // 아래가 위보다 기준값 이상 앞서면 한 칸 올린다. 더 바뀌지 않을 때까지.
    var swapped = true;
    while (swapped) {
      swapped = false;
      for (var i = 0; i < result.length - 1; i++) {
        final gap = _distanceOf(result[i + 1]) - _distanceOf(result[i]);
        if (gap >= swapThresholdMeters) {
          final upper = result[i];
          result[i] = result[i + 1];
          result[i + 1] = upper;
          swapped = true;
        }
      }
    }
    return result;
  }
}
