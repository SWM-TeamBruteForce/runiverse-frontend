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
  });

  final String userId;

  /// 누구인지. **모를 수 있다** — 그때는 화면이 익명으로 그린다.
  final PartyMember? member;

  /// 어디까지 갔는가. 아직 한 번도 안 왔으면 `null`이다.
  final RunProgress? progress;

  /// 나와의 콤보. 겹치지 않으면 `null`이다.
  final ComboPeer? combo;
}

/// 파티원 명단과 통지를 맞춰 화면 줄을 만든다.
///
/// ## 진행률 순으로 세운다
///
/// 정본 S13이 "진행률 높은 순 정렬"을 명시한다. 금지된 것은 **등수 숫자**다 —
/// `1등`·`2등`을 적으면 경쟁 프레임이 되지만, 막대 길이로 앞뒤가 보이는 것은
/// 함께 달리는 감각에 필요하다(`CLAUDE.md`의 "순위(1등/2등) 표시" 금지).
///
/// ⚠️ **같은 거리면 명단 순서를 지킨다.** 안 그러면 두 사람이 나란히 달릴 때
/// 통지가 올 때마다 줄이 서로 자리를 바꾸며 깜빡인다.
class PartyBoard {
  const PartyBoard({
    this.roster = const [],
    this.progress = const {},
    this.combos = const {},
  });

  /// 대기방에서 들고 온 명단. **순서가 곧 화면 순서다.**
  final List<PartyMember> roster;

  /// `userId` → 마지막 진행. 통지가 갱신분만 실어 오므로 여기에 덮는다.
  final Map<String, RunProgress> progress;

  /// `userId` → 나와의 콤보. **통이 올 때마다 통째로 갈린다.**
  final Map<String, ComboPeer> combos;

  /// 그릴 줄들. **진행률 내림차순, 같으면 명단 순서.**
  ///
  /// 명단에 없는데 통지만 오는 사람도 **버리지 않는다.** 러닝 중 재시작하면
  /// 명단이 비어 있는데, 그때 통지까지 버리면 화면이 통째로 빈다.
  List<PartyRow> get rows {
    final order = {for (var i = 0; i < roster.length; i++) roster[i].userId: i};
    final ids = <String>{...order.keys, ...progress.keys};

    final rows = [
      for (final userId in ids)
        PartyRow(
          userId: userId,
          member: order.containsKey(userId) ? roster[order[userId]!] : null,
          progress: progress[userId],
          combo: combos[userId],
        ),
    ];

    rows.sort((a, b) {
      final byDistance = (b.progress?.distanceMeters ?? 0).compareTo(
        a.progress?.distanceMeters ?? 0,
      );
      if (byDistance != 0) return byDistance;
      // 명단에 없는 사람은 뒤로. 그들끼리는 `userId`로 순서를 고정한다 —
      // 무엇으로든 고정해야 줄이 깜빡이지 않는다.
      final ai = order[a.userId] ?? roster.length;
      final bi = order[b.userId] ?? roster.length;
      return ai != bi ? ai.compareTo(bi) : a.userId.compareTo(b.userId);
    });
    return rows;
  }

  /// 진행 통지 하나를 덮는다.
  PartyBoard withProgress(RunProgress update) => PartyBoard(
    roster: roster,
    progress: {...progress, update.userId: update},
    combos: combos,
  );

  /// 콤보를 통째로 갈아끼운다.
  ///
  /// ⚠️ **합치지 않는다.** 끊긴 상대는 목록에서 빠지는 것으로 끊김을 알리므로,
  /// 기존 값에 덧붙이면 끊긴 콤보가 화면에 영영 남는다.
  PartyBoard withCombos(RunCombo update) => PartyBoard(
    roster: roster,
    progress: progress,
    combos: {for (final peer in update.peers) peer.userId: peer},
  );

  /// 명단을 들여온다. 러닝을 시작할 때 한 번.
  PartyBoard withRoster(List<PartyMember> members) =>
      PartyBoard(roster: members, progress: progress, combos: combos);
}
