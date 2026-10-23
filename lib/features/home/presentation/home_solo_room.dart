import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/fact_row.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

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

  /// 시안 `158:3030`의 높이.
  static const _height = 452.0;

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
                    AppStrings.homeMatchSoloTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    AppStrings.homeMatchSoloBody,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body07.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),

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
  static String _distance(int? meters) {
    final km = TargetDistance.fromMeters(meters)?.km;
    return km == null
        ? AppStrings.homeMatchUnknownValue
        : AppStrings.matchDistanceText(km);
  }
}
