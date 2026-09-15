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
/// ## ⚠️ 거리순으로 세우지 않는다
///
/// 정렬을 거리로 하면 그것이 곧 순위표가 된다. 이 앱은 **경쟁이 아니라 동행**을
/// 그리기로 했고(`CLAUDE.md`), 순위 표시를 금지한다. 그래서 **명단 순서를
/// 그대로 유지한다** — 누가 앞서도 줄이 흔들리지 않는다.
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

  /// 그릴 줄들.
  ///
  /// 명단에 없는데 통지만 오는 사람도 **버리지 않고 뒤에 붙인다.** 러닝 중
  /// 재시작하면 명단이 비어 있는데, 그때 통지까지 버리면 화면이 통째로 빈다.
  List<PartyRow> get rows {
    final known = {for (final member in roster) member.userId};
    final extra = progress.keys.where((id) => !known.contains(id)).toList()
      ..sort();

    return [
      for (final member in roster)
        PartyRow(
          userId: member.userId,
          member: member,
          progress: progress[member.userId],
          combo: combos[member.userId],
        ),
      for (final userId in extra)
        PartyRow(
          userId: userId,
          progress: progress[userId],
          combo: combos[userId],
        ),
    ];
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
