/// 초대 방에서 **아직 답을 기다리는 초대 하나.**
///
/// `RoomInfo.invitations`의 원소다. [RoomPlayer]와 모양이 닮았지만 **페이스가
/// 없다** — 아직 방에 들어온 사람이 아니라서 팀 평균에 들지 않는다.
///
/// ## ⚠️ 서버가 `PENDING`만 보낸다
///
/// 수락하면 `players`로 옮겨 가고, 거절하거나 나가면 목록에서 빠진다. 모집이
/// 마감되면 **빈 배열**이 온다. 그래서 상태 필드를 들고 있지 않다 — 들고 있으면
/// 언젠가 `PENDING`이 아닌 값을 기대하는 분기가 생기는데 그런 값은 오지 않는다.
///
/// `isDeleted`도 서버가 항상 `false`로 보낸다(탈퇴한 사람의 초대는 서버가
/// 정리한다). 그래도 받아 두는 것은 `players`와 같은 모양으로 그리기 위해서다 —
/// 화면이 두 목록을 같은 위젯으로 깐다.
class RoomInvitation {
  const RoomInvitation({
    required this.userId,
    required this.nickname,
    required this.isDeleted,
    this.profileImageUrl,
  });

  final String userId;

  /// 탈퇴했으면 서버가 `"탈퇴한 사용자"`로 준다.
  final String nickname;

  final bool isDeleted;

  /// 사진이 없거나 탈퇴했으면 `null`.
  final String? profileImageUrl;

  @override
  bool operator ==(Object other) =>
      other is RoomInvitation &&
      other.userId == userId &&
      other.nickname == nickname &&
      other.isDeleted == isDeleted &&
      other.profileImageUrl == profileImageUrl;

  @override
  int get hashCode => Object.hash(userId, nickname, isDeleted, profileImageUrl);

  @override
  String toString() => 'RoomInvitation($userId, $nickname)';
}
