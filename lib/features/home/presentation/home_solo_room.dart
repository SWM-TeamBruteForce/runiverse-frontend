import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/fact_row.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/home/presentation/home_hero_shade.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 상대를 못 만나 **혼자 달리게 된 방** — 시안 `158:3029`의 자리.
///
/// ## ⚠️ 시안은 이 자리를 `매칭실패`로 그렸는데, 그런 상태는 없다
///
/// 서버는 모집 마감 10분 전까지 상대를 못 찾으면 **그 방을 그대로 1인 러닝으로
/// 돌린다.** 신청이 깨지는 것이 아니라 예약한 시각에 혼자 달린다. 그래서
/// 실패 화면이 아니라 **안내**이고, 시안의 `대안 매칭하기`·`매칭 재등록` 대신
/// 방으로 들어가는 문 하나만 둔다.
///
/// 취소는 여기 두지 않는다 — 로비가 제재 여부를 문구로 알려주고 거기서
/// 결정하게 한다. 혼자 남은 방은 나가도 제재가 없다(`RoomInfo.isAlone`).
///
/// ## ⚠️ "혼자"와 "명단을 모른다"는 다르다
///
/// 이 화면을 띄울지는 [HomeSoloRoom.shows]가 가른다. `players`가 **비어 있는
/// 것은 모른다는 뜻**이다 — 스냅샷이 늦는 동안 `RoomInfo.fromStatus()`가
/// 세우는 대타 방이 그렇다. 그걸 혼자로 읽으면 멀쩡한 4인 방에 이 화면이 뜬다.
class HomeSoloRoom extends StatelessWidget {
  const HomeSoloRoom({
    required this.room,
    required this.now,
    required this.onLobby,
    super.key,
  });

  final RoomInfo room;

  /// 지금. **부르는 쪽이 1초마다 갈아끼운다.**
  final DateTime now;

  final VoidCallback onLobby;

  /// 시안 `158:3030`은 452다. 340으로 줄였다 — 상태 카드 모두 같은 높이다.
  static const _height = 340.0;

  /// 내 사진. 확정 카드의 참여자 동그라미와 같은 크기다.
  static const _avatarSize = 56.0;

  /// 이 방이 **혼자 달리게 된 방**인가.
  ///
  /// ⚠️ 확정됐고, 명단을 알고, 그 명단에 나밖에 없을 때만 참이다.
  /// `RoomInfo.isAlone`은 `players.length <= 1`이라 **빈 명단도 참**이므로
  /// 여기서는 쓰지 않는다.
  static bool shows(RoomInfo room, {String? myUserId}) {
    if (room.status != RoomStatus.matched) return false;
    if (room.players.isEmpty) return false;
    return room.players.every((player) => player.userId == myUserId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final left = room.scheduledStartAt.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/home_solo_bg.webp',
                fit: BoxFit.cover,
                // 어두운 곳을 카드 바탕색으로 받친다(`HomeHeroShade` 참고).
                color: colors.bgSurface,
                colorBlendMode: BlendMode.screen,
                excludeFromSemantics: true,
              ),
            ),
            const Positioned.fill(
              child: HomeHeroShade(light: HomeHeroLight.top),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 다른 상태 카드와 같이 제목을 위 24(안쪽 여백 16 + 8)에 둔다.
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    AppStrings.homeMatchSoloTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  // 설명 줄 없이 시간표를 확정 카드와 같은 높이에 둔다 —
                  // 예약한 시각에 달린다는 것은 시간표가 말한다.
                  const SizedBox(height: AppSpacing.space3),

                  FactRowV2(
                    facts: [
                      Fact(
                        label: AppStrings.homeMatchStartAtLabel,
                        value: AppStrings.matchSlotTime(room.scheduledStartAt),
                      ),
                      Fact(
                        label: AppStrings.homeMatchDistanceLabel,
                        value: _distance(room.targetDistanceMeters),
                      ),
                      Fact(
                        label: AppStrings.homeMatchStartLabel,
                        value: AppStrings.matchRoomCountdown(remaining),
                      ),
                    ],
                  ),

                  // 확정 카드의 참여자 줄 자리에 내 사진 하나. [shows]가 참이면
                  // 명단은 나뿐이다. 명단을 모르면 확정 카드처럼 그리지 않는다.
                  if (room.players.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.space5),
                    Center(
                      child: RunnerAvatarV2(
                        nickname: room.players.first.nickname,
                        imageUrl: room.players.first.profileImageUrl,
                        size: _avatarSize,
                      ),
                    ),
                  ],

                  const Spacer(),

                  AppButtonV2(
                    label: AppStrings.homeMatchToWaitingRoom,
                    onPressed: onLobby,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `5 km`. ⚠️ **모르면 지어내지 않는다.**
  ///
  /// ⚠️ `TargetDistance`를 거치지 않는다. 3/5/10km만 아는 enum이라 초대
  /// 러닝의 자유 거리(7km·하프·풀)가 모르는 값이 된다.
  static String _distance(int? meters) {
    return meters == null
        ? AppStrings.homeMatchUnknownValue
        : AppStrings.distanceKm(meters);
  }
}
