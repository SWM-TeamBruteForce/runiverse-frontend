import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭을 기다리는 중 — 시안 `158:2951`.
///
/// 동심원 한가운데에 내가 있고, 함께 달릴 사람들이 둘레에 떠 있다.
///
/// ## ⚠️ 둘레 자리는 시안을 그대로 베끼지 않았다
///
/// 시안은 세 사람을 **손으로 배치했다** — 반지름은 165~179로 비슷한데 각도가
/// 제각각이고(-23° · 122° · 203°), 크기도 67·78·103으로 다르다.
///
/// 우리 방은 **2~4명**이라 둘레에 설 사람이 1~3명으로 변한다. 그래서
/// **각도는 시안이 쓴 셋을 자리표로 두고, 그보다 많아지면 고르게 나눈다.**
///
/// ⚠️ **크기와 불투명도는 모두 같게 뒀다.** 시안은 깊이를 내려고 달리하는데,
/// 우리 목록은 서버가 준 순서라 **앞사람이 크게 그려지면 순위처럼 읽힌다.**
/// CLAUDE.md 가 파티원에 순위를 붙이지 말라고 못 박는다 — 동행이지 경쟁이
/// 아니다. 디자인 확인이 필요하다.
class HomeWaiting extends StatelessWidget {
  const HomeWaiting({
    required this.room,
    required this.onLobby,
    this.myUserId,
    this.myNickname,
    this.myPhotoUrl,
    super.key,
  });

  final RoomInfo room;

  /// 로비로 들어간다. 시안의 CTA 는 잠겨 있지만, 들어갈 길은 남겨 둔다.
  final VoidCallback onLobby;

  /// 나를 둘레에서 빼는 데 쓴다.
  ///
  /// ⚠️ **서버가 나를 명단에 넣는지 아닌지와 무관하게 맞는다.** 넣으면
  /// 빠지고, 안 넣으면 뺄 것이 없다.
  final String? myUserId;

  final String? myNickname;
  final String? myPhotoUrl;

  /// 시안 `158:2952`의 높이.
  static const _height = 452.0;

  /// 가운데 내 사진. 시안 `158:2969`.
  static const _mySize = 135.0;

  /// 둘레 사람들의 크기와 궤도 반지름.
  static const _otherSize = 80.0;
  static const _orbit = 165.0;

  /// 시안이 쓴 세 각도(도). 넷째부터는 고르게 나눈다.
  static const _angles = [-22.9, 121.8, 202.8];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final others = room.players
        .where((player) => player.userId != myUserId)
        .toList();

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        height: _height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/home_waiting_bg.webp',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),

            // 둘레 사람들. **가운데보다 먼저 그린다** — 겹치면 내가 위다.
            for (final (index, player) in others.indexed)
              _Orbiting(
                angle: _angleOf(index, others.length),
                child: RunnerAvatarV2(
                  nickname: player.nickname,
                  imageUrl: player.profileImageUrl,
                  size: _otherSize,
                ),
              ),

            // 가운데 — 나.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 시안 `158:2969`의 파란 번짐. 내가 가운데라는 표시다.
                boxShadow: [BoxShadow(color: colors.primary, blurRadius: 24)],
              ),
              child: RunnerAvatarV2(
                nickname: myNickname ?? '',
                imageUrl: myPhotoUrl,
                size: _mySize,
              ),
            ),

            Positioned(
              top: AppSpacing.space8,
              left: AppSpacing.space6,
              right: AppSpacing.space6,
              child: Column(
                children: [
                  Text(
                    AppStrings.homeMatchWaitingTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    // ⚠️ 신청 직후에는 아직 나뿐이다. 그때 `0명의 러너가`라고
                    // 적으면 말이 안 된다 — 시안에 없는 구간이다.
                    '${others.isEmpty ? AppStrings.homeMatchWaitingAlone : AppStrings.homeMatchWaitingOthers(others.length)}'
                    '\n${AppStrings.homeMatchWaitingHint}',
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body07.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: AppSpacing.space4,
              right: AppSpacing.space4,
              bottom: AppSpacing.space4,
              // ⚠️ **취소는 여기 두지 않는다.** 로비가 제재 여부를 문구로
              // 알려주고 거기서 결정하게 한다 — 두 곳에 두면 한쪽 문구만
              // 고쳐진다.
              child: AppButtonV2(
                label: AppStrings.homeMatchWaitingCta,
                variant: AppButtonV2Variant.tonal,
                onPressed: onLobby,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 둘레 자리의 각도(라디안).
  ///
  /// 시안이 쓴 셋까지는 그대로 쓰고, 그보다 많아지면 고르게 나눈다.
  static double _angleOf(int index, int total) {
    final degrees = total <= _angles.length
        ? _angles[index]
        : _angles.first + 360.0 * index / total;
    return degrees * math.pi / 180;
  }
}

/// 가운데에서 [angle] 방향으로 궤도 반지름만큼 밀어낸다.
///
/// ⚠️ **카드 밖으로 걸쳐도 둔다.** 시안도 왼쪽 사람을 카드 밖까지 내보낸다 —
/// 둘레가 화면보다 넓다는 느낌이 거기서 나온다. 바깥은 `ClipRRect`가 자른다.
class _Orbiting extends StatelessWidget {
  const _Orbiting({required this.angle, required this.child});

  final double angle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(
        HomeWaiting._orbit * math.cos(angle),
        HomeWaiting._orbit * math.sin(angle),
      ),
      child: child,
    );
  }
}
