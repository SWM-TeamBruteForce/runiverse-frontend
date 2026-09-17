import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/party_board.dart';

/// 파티원 비교 (S13 3페이지, Figma `45:110`).
///
/// 위는 **레인 카드** — 사람마다 자기 색 막대가 목표 거리 눈금 위를 달린다.
/// 아래는 **표** — 거리와 페이스, 나와의 격차.
///
/// ## ⚠️ 위치를 그리지 않는다
///
/// 진행률과 격차만 보여준다. GPS 좌표·경로는 어떤 화면으로도 파티원에게
/// 드러내지 않는 것이 정책이다(`CLAUDE.md`). 꼬리말이 그것을 화면에서 말한다.
///
/// ## 등수를 적지 않는다
///
/// 막대 길이로 앞뒤가 보이지만 `1등`·`2등`을 쓰지 않는다. 경쟁이 아니라
/// 동행이다.
///
/// ## 화면은 계산하지 않는다
///
/// 순서(기준값 히스테리시스)·격차·색 자리는 전부 [PartyBoard]가 정한다.
/// 여기서 다시 세우면 두 곳이 어긋난다.
class RunPartyView extends StatelessWidget {
  const RunPartyView({
    required this.board,
    this.myPace,
    this.targetDistanceMeters,
    this.now,
    super.key,
  });

  /// 지금. 통지가 오래된 레인을 가려내는 기준이다. 테스트만 넣는다.
  final DateTime? now;

  final PartyBoard board;

  /// 앱이 잰 내 순간 페이스. 서버는 본인 것을 보내지 않는다.
  final Duration? myPace;

  /// 목표 거리. 모르면 막대와 눈금을 그리지 않는다 — 임의의 기준으로 칠하면
  /// 거짓말이다.
  final int? targetDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lanes = board.lanes;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space4),
      children: [
        Row(
          children: [
            Text(
              AppStrings.runPartyTitle,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.space1),
            Text(
              '· ${AppStrings.runPartyHint}',
              style: AppTypography.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),

        if (board.rows.isEmpty)
          Text(
            AppStrings.runPartyEmpty,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          )
        else ...[
          _LaneCard(
            board: board,
            lanes: lanes,
            targetMeters: targetDistanceMeters,
            now: now ?? DateTime.now(),
          ),
          const SizedBox(height: AppSpacing.space4),
          _Table(board: board, lanes: lanes, myPace: myPace),
          const SizedBox(height: AppSpacing.space4),
          Text(
            AppStrings.runPartyFooter,
            textAlign: TextAlign.center,
            style: AppTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 이름 — 아바타 이니셜. 이름을 모르면 빈 원이다.
String _initialOf(PartyRow lane) {
  if (lane.isMe) return AppStrings.runPartyMe;
  final name = lane.member?.nickname;
  return name == null || name.isEmpty ? '' : name.characters.first;
}

String _nameOf(PartyRow lane) =>
    lane.member?.nickname ??
    (lane.isMe ? AppStrings.runPartyMe : AppStrings.runPartyUnknown);

int _distanceOf(PartyBoard board, PartyRow lane) =>
    lane.isMe ? board.myDistanceMeters : lane.progress?.distanceMeters ?? 0;

/// 레인 카드. 막대·머리·눈금이 **같은 좌표계**를 쓴다.
class _LaneCard extends StatelessWidget {
  const _LaneCard({
    required this.board,
    required this.lanes,
    required this.targetMeters,
    required this.now,
  });

  final PartyBoard board;
  final List<PartyRow> lanes;
  final int? targetMeters;
  final DateTime now;

  /// 통지가 끊긴 것으로 보이는가. 서버는 끊김을 알리지 않으므로 시간으로 본다.
  bool _stale(PartyRow lane) {
    final at = lane.progress?.receivedAt;
    return at != null && now.difference(at) > PartyBoard.staleAfter;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final target = targetMeters;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space3,
          AppSpacing.space4,
          AppSpacing.space3,
          AppSpacing.space3,
        ),
        child: Column(
          children: [
            for (final lane in lanes)
              _Lane(
                key: ValueKey(lane.userId),
                name: _nameOf(lane),
                initial: _initialOf(lane),
                color: RunPalette.lane(board.colorSlotOf(lane.userId)),
                meters: _distanceOf(board, lane),
                targetMeters: target,
                isMe: lane.isMe,
                stale: _stale(lane),
              ),
            if (target != null && target > 0) _Axis(targetMeters: target),
          ],
        ),
      ),
    );
  }
}

/// 레인 하나. 이름 · 칠해진 막대 · 안쪽 선 · 앞쪽 점 · 머리.
class _Lane extends StatelessWidget {
  const _Lane({
    required this.name,
    required this.initial,
    required this.color,
    required this.meters,
    required this.targetMeters,
    required this.isMe,
    this.stale = false,
    super.key,
  });

  final String name;
  final String initial;
  final Color color;
  final int meters;
  final int? targetMeters;
  final bool isMe;

  /// 통지가 끊긴 것으로 보이는 레인. 흐리게만 그린다 — 문구로 단정하지 않는다.
  final bool stale;

  static const _staleOpacity = 0.4;

  /// 머리 지름. 막대보다 크고 이름 한 글자가 들어간다.
  static const _head = AppSpacing.space7;
  static const _track = AppSpacing.space8;
  static const _bar = AppSpacing.space6;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final target = targetMeters;
    // ⚠️ 목표를 모르면 막대를 그리지 않는다. 임의의 기준으로 칠하면 거짓말이다.
    final ratio = target == null || target <= 0
        ? null
        : (meters / target).clamp(0.0, 1.0);

    return Opacity(
      opacity: stale ? _staleOpacity : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.space8,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.micro.copyWith(
                  color: isMe ? colors.textPrimary : colors.textSecondary,
                  fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space1 + AppSpacing.space0),
            Expanded(
              child: SizedBox(
                height: _track,
                child: ratio == null
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // 머리가 끝을 넘지 않게 막대 폭은 머리 반지름만큼 뺀다.
                          final usable = constraints.maxWidth - _head;
                          final painted = usable * ratio;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 10초마다 값이 튄다. 애니메이션이 없으면 뚝뚝 뛴다.
                              AnimatedPositioned(
                                duration: AppMotion.slow,
                                curve: AppMotion.easeStandard,
                                left: 0,
                                top: (_track - _bar) / 2,
                                width: painted + _head / 2,
                                height: _bar,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: AppRadius.full,
                                  ),
                                ),
                              ),
                              AnimatedPositioned(
                                duration: AppMotion.slow,
                                curve: AppMotion.easeStandard,
                                left: AppSpacing.space2,
                                top: _track / 2 - AppSpacing.space0 / 2,
                                width: (painted - AppSpacing.space2).clamp(
                                  0.0,
                                  double.infinity,
                                ),
                                height: AppSpacing.space0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.textPrimary.withValues(
                                      alpha: 0.38,
                                    ),
                                    borderRadius: AppRadius.full,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < 3; i++)
                                AnimatedPositioned(
                                  duration: AppMotion.slow,
                                  curve: AppMotion.easeStandard,
                                  left:
                                      painted +
                                      _head +
                                      i *
                                          (AppSpacing.space3 +
                                              AppSpacing.space0),
                                  top:
                                      _track / 2 -
                                      (AppSpacing.space2 - i * 2) / 2,
                                  child: _Drop(
                                    color: color,
                                    size: AppSpacing.space2 - i * 2,
                                  ),
                                ),
                              AnimatedPositioned(
                                duration: AppMotion.slow,
                                curve: AppMotion.easeStandard,
                                left: painted,
                                top: (_track - _head) / 2,
                                child: _Head(initial: initial, color: color),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 막대 앞으로 흩어지는 점. 달리는 방향을 보여준다.
class _Drop extends StatelessWidget {
  const _Drop({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// 막대 끝의 머리. 이니셜과 같은 색 테두리, 글로우.
class _Head extends StatelessWidget {
  const _Head({required this.initial, required this.color});

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: _Lane._head,
      height: _Lane._head,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: AppSpacing.space0),
        boxShadow: RunPalette.glow(color),
      ),
      child: Text(
        initial,
        style: AppTypography.caption.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 눈금. 막대와 같은 좌표계 — 이름 폭과 머리 반지름을 똑같이 뺀다.
class _Axis extends StatelessWidget {
  const _Axis({required this.targetMeters});

  final int targetMeters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final km = (targetMeters / 1000).ceil();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space1),
      child: Row(
        children: [
          const SizedBox(
            width: AppSpacing.space8 + AppSpacing.space1 + AppSpacing.space0,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final usable = constraints.maxWidth - _Lane._head;
                return SizedBox(
                  height: AppTypography.micro.fontSize! * 1.4,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i <= km; i++)
                        Positioned(
                          left:
                              usable *
                              (i * 1000 / targetMeters).clamp(0.0, 1.0),
                          child: Text(
                            '$i',
                            style: AppTypography.micro.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 표. 러너 · 거리 · 페이스, 이름 옆에 격차.
class _Table extends StatelessWidget {
  const _Table({
    required this.board,
    required this.lanes,
    required this.myPace,
  });

  final PartyBoard board;
  final List<PartyRow> lanes;
  final Duration? myPace;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final head = AppTypography.micro.copyWith(color: colors.textTertiary);

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: colors.borderDefault),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3 + AppSpacing.space0,
                vertical: AppSpacing.space2 + AppSpacing.space0,
              ),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.space6 + AppSpacing.space2),
                  Expanded(
                    child: Text(AppStrings.runPartyColRunner, style: head),
                  ),
                  SizedBox(
                    width: AppSpacing.space10,
                    child: Text(
                      AppStrings.runPartyColDistance,
                      textAlign: TextAlign.end,
                      style: head,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  SizedBox(
                    width: AppSpacing.space10 + AppSpacing.space1,
                    child: Text(
                      AppStrings.runPartyColPace,
                      textAlign: TextAlign.end,
                      style: head,
                    ),
                  ),
                ],
              ),
            ),
            for (final lane in lanes)
              _TableRow(
                key: ValueKey('row-${lane.userId}'),
                lane: lane,
                name: _nameOf(lane),
                initial: _initialOf(lane),
                color: RunPalette.lane(board.colorSlotOf(lane.userId)),
                meters: _distanceOf(board, lane),
                pace: lane.isMe
                    ? myPace
                    : switch (lane.progress?.currentPaceSecondsPerKm) {
                        final int seconds => Duration(seconds: seconds),
                        null => null,
                      },
              ),
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.lane,
    required this.name,
    required this.initial,
    required this.color,
    required this.meters,
    required this.pace,
    super.key,
  });

  final PartyRow lane;
  final String name;
  final String initial;
  final Color color;
  final int meters;
  final Duration? pace;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final gap = lane.gapMeters;
    final combo = lane.combo;
    final value = AppTypography.h3.copyWith(
      color: colors.textPrimary,
      // 10초마다 갈리는 숫자다. 자릿수가 흔들리면 줄이 어긋난다.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        // 내 줄만 살짝 띄운다. 순위가 아니라 "여기가 나"라는 표시다.
        color: lane.isMe ? colors.primaryMuted : null,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3 + AppSpacing.space0,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.space6 + AppSpacing.space0,
              height: AppSpacing.space6 + AppSpacing.space0,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                initial,
                style: AppTypography.micro.copyWith(
                  color: colors.textOnPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space2 + AppSpacing.space0),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: lane.isMe
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight: lane.isMe
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (gap != null && gap != 0) ...[
                    const SizedBox(
                      width: AppSpacing.space1 + AppSpacing.space0,
                    ),
                    Text(
                      AppStrings.runPartyGap(gap),
                      style: AppTypography.micro.copyWith(
                        // 상대가 앞서면 눈에 띄게, 뒤처지면 차분하게. 어느 쪽도
                        // 오류색으로 칠하지 않는다 — 뒤처진 것은 잘못이 아니다.
                        color: gap > 0 ? colors.success : colors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (combo != null && combo.comboCount > 0) ...[
                    const SizedBox(
                      width: AppSpacing.space1 + AppSpacing.space0,
                    ),
                    Text(
                      AppStrings.runPartyCombo(combo.comboCount),
                      style: AppTypography.micro.copyWith(
                        color: colors.matchConfirmed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: AppSpacing.space10,
              child: Text(
                AppStrings.runPartyKm(meters),
                textAlign: TextAlign.end,
                style: value,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            SizedBox(
              width: AppSpacing.space10 + AppSpacing.space1,
              child: Text(
                PaceCalculator.format(pace),
                textAlign: TextAlign.end,
                style: value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
