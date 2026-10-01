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
import 'package:runiverse/features/home/presentation/home_confirmed.dart';
import 'package:runiverse/features/home/presentation/home_idle.dart';
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
/// ## ⚠️ 상태마다 배경이 다르다
///
/// 시안이 상태별로 다른 배경을 준다 — 기본은 아래에서 올라오는 파란 빛
/// (`158:2848`), 나머지는 아직 옛 아우라다. **배경을 껍데기가 정하지 않고
/// 상태가 들고 온다.** 껍데기가 하나로 정하면 상태를 하나 옮길 때마다
/// 껍데기를 고치게 되고, 그때 다른 상태가 같이 흔들린다.
///
/// 기본 상태의 빛은 **이미지다**(`assets/images/home_hero_light.webp`).
/// 시안이 blur 레이어 일곱 겹을 `plus-lighter`로 겹쳐 만든 것이라 손으로
/// 그리면 맞출 수 없다. 부드러운 그러데이션이라 WebP 로 5KB 에 들어간다.
///
/// 글자는 빛의 **위쪽**에 둔다. `docs/implementation-notes.md` §3-4가
/// **글로우를 텍스트 뒤에 깔지 말라**고 못 박았는데, 시안의 빛은 아래가 밝고
/// 위가 어두워서 제목이 앉는 자리는 여전히 어둡다.
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
    required this.onMatch,
    required this.onCancel,
    required this.onLobby,
    required this.now,
    this.name,
    this.room,
    this.pending = false,
    this.cooldownUntil,
    super.key,
  });

  /// 부를 이름. **없을 수 있다** — `/me`가 오기 전이거나 온보딩 전이다.
  ///
  /// 시안 `158:2848`이 `김지원님`으로 시작한다. 없으면 그 줄을 통째로 뺀다.
  final String? name;

  /// 매칭 등록 화면으로. 기본 상태에서만 쓴다.
  final VoidCallback onMatch;

  /// 방 정보를 못 받았을 때만 쓴다. 평소의 취소는 로비가 맡는다.
  final VoidCallback onCancel;

  /// 방으로 들어간다. 모집 중이면 로비, 확정 뒤면 대기실 — 같은 화면이다.
  final VoidCallback onLobby;

  /// 지금. **부르는 쪽이 1초마다 갈아끼운다** — 카운트다운이 이 값에서 나온다.
  final DateTime now;

  /// 속한 방. `null`이면 매칭 중이 아니거나 아직 방 정보를 못 받았다.
  final RoomInfo? room;

  /// 매칭 신청이 풀리는 시각. 없거나 지났으면 제한이 없다.
  ///
  /// 이탈·조기 종료 제재다. **매칭 신청만 막고 솔로는 열어 둔다.**
  final DateTime? cooldownUntil;

  /// ⚠️ 서버는 매칭 중이라는데 [room]이 아직 없는 구간인가.
  ///
  /// 인원·마감 시각은 스트림이 나르므로 상태 조회만으로는 그릴 것이 없다.
  /// 그 사이에 기본 히어로를 보여주면 신청한 적 없는 줄 알고 다시 누른다.
  final bool pending;

  /// 기록이 없을 때의 아우라 밝기. 아직 안 옮긴 상태들만 쓴다.
  static const _restingVitality = 0.5;

  @override
  Widget build(BuildContext context) {
    final current = room;

    // ⚠️ **옮긴 상태는 자기 카드를 통째로 그린다.**
    //
    // 껍데기를 함께 쓰면 껍데기가 두 세대의 토큰을 같이 읽게 되고,
    // `theme_generation_test`가 그것을 막는다. 상태를 하나씩 옮기는 동안
    // **옮긴 것만 자기 파일로 나간다** — 남은 넷은 아래 껍데기를 그대로 쓴다.
    if (current == null && !pending) {
      return HomeIdle(
        name: name,
        onMatch: onMatch,
        now: now,
        cooldownUntil: cooldownUntil,
      );
    }
    if (current != null && current.status == RoomStatus.matched) {
      return HomeConfirmed(room: current, now: now, onLobby: onLobby);
    }

    final shell = Stack(
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
            RoomStatus.matching => _Waiting(
              room: current!,
              now: now,
              onLobby: onLobby,
            ),
            // ⚠️ **여기를 비워두면 달리는 중에 홈이 "지금 매칭하기"가 된다.**
            // 예약한 시각이 지나 서버가 러닝을 시작했는데 사용자가 홈 탭에
            // 있으면 아무도 데려가지 않았다 — 그사이가 통째로 거리에서 빠진다.
            RoomStatus.started => _Started(onEnter: onLobby),
            // 기본 상태는 위에서 이미 돌아갔다. 여기 오는 `_` 는 모집 중인데
            // 방 정보가 아직 없는 구간이거나 **모르는 상태값**이고, 그때도
            // 비워 두지 않는다.
            _ => _Pending(onCancel: onCancel),
          },
        ),
      ],
    );

    return ClipRRect(
      // 아우라가 히어로 밖으로 새어 아래 카드를 덮지 않게 자른다.
      borderRadius: AppRadius.xl,
      child: ConstrainedBox(
        // 정본이 정한 히어로 최소 높이.
        constraints: const BoxConstraints(minHeight: 236),
        child: shell,
      ),
    );
  }
}

/// 기본 — 아직 매칭 중이 아니다.
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
/// 서버가 이미 시작한 러닝. **들어갈 문 하나만 둔다.**
///
/// 카운트다운도 파티원 줄도 그리지 않는다 — 기다릴 것이 없고, 이 화면에서
/// 머무는 시간이 그대로 기록에서 빠진다.
class _Started extends StatelessWidget {
  const _Started({required this.onEnter});

  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppStrings.homeRunStarted,
          style: AppTypography.h2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          AppStrings.homeRunStartedHint,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space4),

        AppButton(label: AppStrings.homeRunToSession, onPressed: onEnter),
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

class _Circle extends StatelessWidget {
  const _Circle({required this.player, required this.size});

  final RoomPlayer player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryMuted,
        borderRadius: AppRadius.full,
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
