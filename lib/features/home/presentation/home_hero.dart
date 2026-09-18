import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/color/aura_orb.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 홈 히어로 (S05).
///
/// ## 히어로가 매칭 상태를 전담한다
///
/// 정본이 정한 구조다. 모집 중에는 **갈 화면이 따로 없고** 여기가 그 상태를
/// 보여주는 유일한 자리다. 확정되면 `로비로 이동`이 생기고, 그 버튼이 방으로
/// 가는 유일한 문이 된다.
///
/// 상태는 [room]이 정한다 — `null`이면 기본, 모집 중이면 대기, 확정이면 확정.
///
/// ## 아우라를 텍스트 뒤에 깔지 않는다
///
/// 정본 와이어프레임은 히어로 가운데에 아우라 글로우를 두지만,
/// `docs/implementation-notes.md` §3-4가 **글로우를 텍스트 뒤에 깔지 말라**고 못 박았다.
/// 러닝 색은 채도가 높아 그 위 글자가 대비 기준을 통과하지 못한다.
/// 그래서 우측 상단 밖으로 흘려보내고, 글자는 깨끗한 배경 위에 둔다.
///
/// ## 정본에서 뺀 것
///
/// - **참가자별 시그니처 컬러 아바타** — 색을 모으는 기능이 아직 없다.
///   첫 글자만 남기고 한 가지 톤으로 그린다
/// - **날씨 오버레이** — 받을 API가 없다
/// - **`FAILED` 상태** — 명세에 그 상태가 없다. "마감은 인원과 무관하게 항상
///   확정으로 끝난다"고 정해져 있어 정본의 이 갈래는 낡았다
class HomeHero extends StatelessWidget {
  const HomeHero({
    required this.greeting,
    required this.onMatch,
    required this.onSolo,
    required this.onCancel,
    required this.onLobby,
    required this.now,
    this.room,
    this.pending = false,
    super.key,
  });

  /// 시간대 인사. 어느 문구인지는 부르는 쪽이 정한다.
  final String greeting;

  /// 매칭 등록 화면으로. 기본 상태에서만 쓴다.
  final VoidCallback onMatch;

  /// 1인 러닝 시작.
  final VoidCallback onSolo;

  /// 방 정보를 못 받았을 때만 쓴다. 평소의 취소는 로비가 맡는다.
  final VoidCallback onCancel;

  /// 방으로 들어간다. 모집 중이면 로비, 확정 뒤면 대기실 — 같은 화면이다.
  final VoidCallback onLobby;

  /// 지금. **부르는 쪽이 1초마다 갈아끼운다** — 카운트다운이 이 값에서 나온다.
  final DateTime now;

  /// 속한 방. `null`이면 매칭 중이 아니거나 아직 방 정보를 못 받았다.
  final RoomInfo? room;

  /// ⚠️ 서버는 매칭 중이라는데 [room]이 아직 없는 구간인가.
  ///
  /// 인원·마감 시각은 스트림이 나르므로 상태 조회만으로는 그릴 것이 없다.
  /// 그 사이에 기본 히어로를 보여주면 신청한 적 없는 줄 알고 다시 누른다.
  final bool pending;

  /// 기록이 없을 때의 아우라 밝기.
  static const _restingVitality = 0.5;

  @override
  Widget build(BuildContext context) {
    final current = room;

    return ClipRRect(
      // 아우라가 히어로 밖으로 새어 아래 카드를 덮지 않게 자른다.
      borderRadius: AppRadius.xl,
      child: ConstrainedBox(
        // 정본이 정한 히어로 최소 높이.
        constraints: const BoxConstraints(minHeight: 236),
        child: Stack(
          children: [
            Positioned(
              top: -AppSpacing.space10,
              right: -AppSpacing.space10,
              child: AuraOrb(
                colors: [RunPalette.shadesOf(RunHue.company)[1]],
                size: 240,
                vitality: _restingVitality,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: switch (current?.status) {
                // 모집 중과 확정만 히어로가 맡는다. 러닝이 시작된 뒤에는
                // 라우터가 이미 러닝 화면으로 보냈다.
                RoomStatus.matching => _Waiting(
                  room: current!,
                  now: now,
                  onLobby: onLobby,
                ),
                RoomStatus.matched => _Confirmed(
                  room: current!,
                  now: now,
                  onLobby: onLobby,
                ),
                _ when pending => _Pending(onCancel: onCancel),
                _ => _Idle(
                  greeting: greeting,
                  onMatch: onMatch,
                  onSolo: onSolo,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 기본 — 아직 매칭 중이 아니다.
class _Idle extends StatelessWidget {
  const _Idle({
    required this.greeting,
    required this.onMatch,
    required this.onSolo,
  });

  final String greeting;
  final VoidCallback onMatch;
  final VoidCallback onSolo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greeting,
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space1),

        Text(
          AppStrings.homeHeroPrompt,
          style: AppTypography.h1.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space6),

        AppButton(label: AppStrings.homeMatchCta, onPressed: onMatch),
        const SizedBox(height: AppSpacing.space2),

        AppButton(
          label: AppStrings.homeSoloCta,
          onPressed: onSolo,
          variant: AppButtonVariant.secondary,
        ),
      ],
    );
  }
}

/// 매칭 중인데 방 정보가 아직 없다.
///
/// 짧게 지나가는 구간이지만 **비워 둘 수 없다.** 여기가 비면 매칭을 신청한
/// 사람이 기본 히어로를 보고 다시 신청하려 든다.
class _Pending extends StatelessWidget {
  const _Pending({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppSpacing.space2,
              height: AppSpacing.space2,
              decoration: BoxDecoration(
                color: colors.matchWaiting,
                borderRadius: AppRadius.full,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              AppStrings.homeMatchWaiting,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space3),

        Text(
          AppStrings.homeMatchPending,
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space4),

        // 방 정보가 없어도 나갈 수는 있다 — 취소는 방 번호를 쓰지 않는다.
        AppButton(
          label: AppStrings.homeMatchCancel,
          onPressed: onCancel,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.md,
          expand: false,
        ),
      ],
    );
  }
}

/// 모집 중 — 몇 명이 모였고 언제 마감되는가.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.room,
    required this.now,
    required this.onLobby,
  });

  final RoomInfo room;
  final DateTime now;
  final VoidCallback onLobby;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final closeAt = room.closeAt;
    final untilClose = closeAt == null
        ? null
        : closeAt.difference(now).isNegative
        ? Duration.zero
        : closeAt.difference(now);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppSpacing.space2,
              height: AppSpacing.space2,
              decoration: BoxDecoration(
                color: colors.matchWaiting,
                borderRadius: AppRadius.full,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              AppStrings.homeMatchWaiting,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),

        // 숫자만 강조색이다. 문장 전체를 칠하면 몇 명인지가 묻힌다.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${AppStrings.homeMatchJoinedPrefix} '),
              TextSpan(
                text: AppStrings.homeMatchJoinedCount(room.players.length),
                style: TextStyle(color: colors.matchWaiting),
              ),
              TextSpan(text: ' ${AppStrings.homeMatchJoinedSuffix}'),
            ],
          ),
          style: AppTypography.h1.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space4),

        _Avatars(players: room.players, size: AppSizes.touchDefault),
        const SizedBox(height: AppSpacing.space4),

        if (untilClose != null)
          Text(
            AppStrings.homeMatchSlotLine(room.scheduledStartAt, untilClose),
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        const SizedBox(height: AppSpacing.space4),

        // ⚠️ 취소는 여기 두지 않는다. 로비가 제재 여부를 문구로 알려주고
        // 거기서 결정하게 한다 — 두 곳에 두면 한쪽 문구만 고쳐진다.
        AppButton(label: AppStrings.homeMatchToLobby, onPressed: onLobby),
      ],
    );
  }
}

/// 확정 — 언제 출발하고 누구와 뛰는가.
class _Confirmed extends StatelessWidget {
  const _Confirmed({
    required this.room,
    required this.now,
    required this.onLobby,
  });

  final RoomInfo room;
  final DateTime now;
  final VoidCallback onLobby;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final left = room.scheduledStartAt.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.matchConfirmed.withValues(alpha: 0.16),
            borderRadius: AppRadius.sm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space2,
              vertical: AppSpacing.space1,
            ),
            child: Text(
              AppStrings.homeMatchConfirmed(room.scheduledStartAt),
              style: AppTypography.caption.copyWith(
                color: colors.matchConfirmed,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),

        Text(
          AppStrings.homeMatchStartLabel,
          style: AppTypography.caption.copyWith(color: colors.textTertiary),
        ),
        Text(
          AppStrings.matchRoomCountdown(remaining),
          style: AppTypography.display.copyWith(
            color: colors.textPrimary,
            // 1초마다 갈리는 숫자다. 자릿수가 흔들리면 글자가 춤춘다.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),

        // ⚠️ 명단을 모르면 **아예 그리지 않는다.** 스냅샷이 없을 때 0명이라
        // 적으면 혼자 달리는 줄 안다 — 모르는 것과 없는 것은 다르다.
        if (room.players.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StackedAvatars(players: room.players, size: AppSpacing.space8),
              const SizedBox(width: AppSpacing.space2),
              Text(
                AppStrings.homeMatchParty(room.players.length),
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.space4),

        AppButton(label: AppStrings.homeMatchToWaitingRoom, onPressed: onLobby),
      ],
    );
  }
}

/// 참가자 동그라미들.
///
/// ⚠️ **시그니처 컬러를 쓰지 못한다.** 색을 모으는 기능이 아직 없어 한 가지
/// 톤으로 그린다. 정본은 각자의 색으로 칠하고 글로우를 두른다.
class _Avatars extends StatelessWidget {
  const _Avatars({required this.players, required this.size});

  final List<RoomPlayer> players;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final player in players)
          Padding(
            padding: EdgeInsets.only(
              right: player == players.last ? 0 : AppSpacing.space2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Circle(player: player, size: size),
                const SizedBox(height: AppSpacing.space1),
                SizedBox(
                  width: size + AppSpacing.space2,
                  child: Text(
                    player.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: context.appColors.textSecondary,
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

/// 겹쳐 놓은 동그라미들. 확정 상태에서 쓴다 — 이름은 아래 카드가 맡는다.
///
/// ⚠️ **음수 패딩으로 겹치지 않는다.** `Padding`은 음수를 받지 못해 레이아웃이
/// 통째로 깨진다(테스트에서 99,336px 오버플로로 드러났다). 겹침은 [Stack]이
/// 만들고 폭은 직접 센다.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.players, required this.size});

  final List<RoomPlayer> players;
  final double size;

  /// 옆 동그라미를 얼마나 덮는가.
  static const _bite = AppSpacing.space2;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();

    final step = size - _bite;
    return SizedBox(
      width: size + step * (players.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < players.length; i++)
            Positioned(
              left: step * i,
              child: _Circle(player: players[i], size: size, bordered: true),
            ),
        ],
      ),
    );
  }
}

/// 동그라미 하나.
class _Circle extends StatelessWidget {
  const _Circle({
    required this.player,
    required this.size,
    this.bordered = false,
  });

  final RoomPlayer player;
  final double size;

  /// 겹칠 때는 테두리로 서로를 갈라 준다.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryMuted,
        borderRadius: AppRadius.full,
        border: bordered ? Border.all(color: colors.bgSurface, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        _initial(player),
        style: AppTypography.body.copyWith(color: colors.primary),
      ),
    );
  }

  /// 첫 글자. 탈퇴한 사람은 이름이 익명 처리돼 오므로 그대로 쓴다.
  static String _initial(RoomPlayer player) =>
      player.nickname.isEmpty ? '?' : player.nickname.characters.first;
}
