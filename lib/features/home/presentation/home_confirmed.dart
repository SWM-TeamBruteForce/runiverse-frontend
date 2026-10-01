import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/fact_row.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 매칭이 확정됐다 — 시안 `158:3102`.
///
/// 시작 시각·목표 거리·남은 시간 셋과 참여자, 그리고 방으로 들어가는 문 하나.
///
/// ## ⚠️ 다른 상태와 배경이 다르다
///
/// 이 상태만 파란 면이다. 시안이 blur 먹인 색 판 셋과 테두리 글로우를
/// 겹쳐 만든 것이라 **이미지로 굽는다**(`home_confirmed_bg.webp`).
/// 손으로 그리면 겹치는 규칙이 달라 다른 색이 나온다 — 기본 상태에서 한 번
/// 겪었다.
///
/// ## 아바타는 겹치지 않는다
///
/// 옛 화면은 자리를 아끼려고 동그라미를 겹쳤는데, 시안은 나란히 놓고 **이름을
/// 아래 붙인다.** 누가 함께 달리는지가 이 카드의 요점이라 이름이 보여야 한다.
class HomeConfirmed extends StatelessWidget {
  const HomeConfirmed({
    required this.room,
    required this.now,
    required this.onLobby,
    super.key,
  });

  final RoomInfo room;

  /// 지금. **부르는 쪽이 1초마다 갈아끼운다** — 카운트다운이 여기서 나온다.
  final DateTime now;

  /// 방으로 들어간다.
  final VoidCallback onLobby;

  /// 시안 `158:3103`의 높이.
  static const _height = 452.0;

  /// 참여자 동그라미. 시안 `158:3110`.
  static const _avatarSize = 60.0;

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
                'assets/images/home_confirmed_bg.webp',
                fit: BoxFit.cover,
                // 사람이 읽을 것이 아니라 분위기다.
                excludeFromSemantics: true,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.space5),
                  Text(
                    AppStrings.homeMatchConfirmedTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
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

                  // ⚠️ 명단을 모르면 **아예 그리지 않는다.** 스냅샷이 없을 때
                  // 0명이라 적으면 혼자 달리는 줄 안다 — 모르는 것과 없는
                  // 것은 다르다.
                  if (room.players.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.space6),
                    Text(
                      AppStrings.homeMatchPartyLabel,
                      textAlign: TextAlign.center,
                      // ⚠️ 시안의 `#575757`은 여기서도 2.6:1 이다(AA 미달).
                      // `FactRowV2`와 같은 이유로 읽히는 쪽을 골랐다.
                      style: AppTypographyV2.body11.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    _Party(players: room.players),
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

  /// `5km`. ⚠️ **모르면 지어내지 않는다.**
  ///
  /// ⚠️ 시안은 `5 km`로 띄어 쓰는데 우리는 붙여 쓴다. 거리 칩·요약 줄이
  /// 전부 같은 표기라 여기만 바꾸면 앱 안에서 두 표기가 생긴다
  /// (스펙 13절의 미결 항목).
  static String _distance(int? meters) {
    final km = TargetDistance.fromMeters(meters)?.km;
    return km == null
        ? AppStrings.homeMatchUnknownValue
        : AppStrings.matchDistanceText(km);
  }
}

/// 참여자 줄. 동그라미와 이름을 세로로 묶어 가운데 모은다.
class _Party extends StatelessWidget {
  const _Party({required this.players});

  final List<RoomPlayer> players;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final player in players)
          Padding(
            padding: EdgeInsets.only(
              right: player == players.last ? 0 : AppSpacing.space5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RunnerAvatarV2(
                  nickname: player.nickname,
                  imageUrl: player.profileImageUrl,
                  size: HomeConfirmed._avatarSize,
                ),
                const SizedBox(height: AppSpacing.space2),

                // ⚠️ **이름이 길면 줄인다.** 네 명이 들어오면 화면을 넘긴다.
                SizedBox(
                  width: HomeConfirmed._avatarSize + AppSpacing.space3,
                  child: Text(
                    player.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body11.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
