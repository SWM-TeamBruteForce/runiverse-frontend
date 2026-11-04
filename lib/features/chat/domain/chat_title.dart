import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 채팅 화면의 제목. **두 줄이다.**
///
/// 한 줄로 두면 `19:30 - 5 km 러닝 영희님 외 2명`이 되어 긴 닉네임 하나로
/// 통째로 잘린다. 시각·거리는 윗줄, 사람은 아랫줄로 나눠 두면 아랫줄만 줄어든다.
class ChatTitle {
  const ChatTitle({required this.top, required this.bottom});

  /// `19:30 - 5 km 러닝`
  final String top;

  /// `영희님 외 2명` · 파티원이 나뿐이면 빈 문자열이다.
  final String bottom;
}

/// 방 정보로 제목 두 줄을 조립한다.
///
/// ## ⚠️ 대표는 명단 순서로 뽑고, 탈퇴한 사람은 건너뛴다
///
/// 탈퇴한 사람을 방의 얼굴로 세우는 쪽이 더 나쁘다. 다만 **인원 수에서는 빼지
/// 않는다** — 빼면 숫자가 방의 인원과 어긋난다. 건너뛸 곳이 없으면(전원 탈퇴)
/// 멈추지 않고 첫 사람을 그대로 쓴다.
///
/// 시각은 [AppStrings.matchSlotTime]이 한국 시각으로 못 박아 준다. 기기
/// 시간대로 그리면 없는 슬롯 시각이 뜬다 — 이미 밟은 함정이다.
ChatTitle chatTitleOf({
  required DateTime scheduledStartAt,
  required int? targetDistanceMeters,
  required List<RoomPlayer> players,
  required String? myUserId,
}) {
  final meters = targetDistanceMeters;
  final top = AppStrings.chatTitleRun(
    AppStrings.matchSlotTime(scheduledStartAt),
    meters == null ? null : AppStrings.distanceKm(meters),
  );

  final others = players.where((player) => player.userId != myUserId).toList();
  if (others.isEmpty) return ChatTitle(top: top, bottom: '');

  final leader = others.firstWhere(
    (player) => !player.isDeleted,
    orElse: () => others.first,
  );

  // ⚠️ 건너뛸 곳이 없어 탈퇴한 사람을 세웠을 때는 **이름을 가린다.** 버블과
  // 명단이 이미 같은 사람을 가리고 있고(`match_room_page.dart`), 서버가 닉네임을
  // 익명 처리해 준다는 계약은 아직 확인 전이다(명세 9절).
  final name = leader.isDeleted
      ? AppStrings.matchRoomDeletedPlayer
      : leader.nickname;

  return ChatTitle(
    top: top,
    bottom: AppStrings.chatTitleParty(name, others.length - 1),
  );
}
