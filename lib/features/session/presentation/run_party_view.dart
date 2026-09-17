import 'dart:math' as math;
import 'dart:ui';

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

/// 파티원 상태 (S13 3페이지, 2026-09-17 개편안 B).
///
/// 사람마다 카드 하나 — 아바타·이름, **큰 숫자 둘**(현재 거리 · 페이스), 자기
/// 색 진행 막대, 아래 줄에 격차와 작은 콤보 배지. 콤보가 하나 오를 때마다
/// **카드를 덮개로 가리고 가운데에 `12 COMBO`를 아케이드처럼 띄웠다가** 배지
/// 자리로 보낸다. 나와 콤보가 이어진 카드는 그 사이에도 두 사람 색을 섞은
/// 테두리로 빛난다.
///
/// ## ⚠️ 위치를 그리지 않는다
///
/// 진행률과 격차만 보여준다. GPS 좌표·경로는 어떤 화면으로도 파티원에게
/// 드러내지 않는 것이 정책이다(`CLAUDE.md`).
///
/// ## 등수를 적지 않는다
///
/// 순서는 [PartyBoard]가 정한 진행률 순이지만 `1등`·`2등`을 쓰지 않는다.
///
/// ## 정본과 다른 것
///
/// - "평균 페이스" 자리에는 서버가 주는 **순간 페이스**가 들어간다(2026-09-17
///   결정). 라벨은 그래서 "페이스"다
/// - 케이던스는 뺐다 — 파티원 것은 서버가 보내지 않는다
/// - 임팩트는 **나와 상대 카드에 동시에** 뜬다. 콤보는 둘의 것이다
class RunPartyView extends StatelessWidget {
  const RunPartyView({
    required this.board,
    this.myPace,
    this.targetDistanceMeters,
    this.now,
    super.key,
  });

  final PartyBoard board;

  /// 앱이 잰 내 순간 페이스. 서버는 본인 것을 보내지 않는다.
  final Duration? myPace;

  /// 목표 거리. 모르면 막대를 채우지 않는다 — 임의의 기준으로 칠하면 거짓말이다.
  final int? targetDistanceMeters;

  /// 지금. 통지가 오래된 카드를 흐리게 하는 기준이다. 테스트만 넣는다.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lanes = board.lanes;
    final clock = now ?? DateTime.now();
    // 내 카드의 콤보는 상대 중 가장 높은 것. 콤보는 쌍마다 따로 센다.
    final myCombo = board.combos.values.isEmpty
        ? null
        : board.combos.values.reduce(
            (a, b) => a.comboCount >= b.comboCount ? a : b,
          );
    final byId = {for (final member in board.roster) member.userId: member};
    String nameOf(String userId) =>
        byId[userId]?.nickname ?? AppStrings.runPartyUnknown;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space8,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.space4),
          child: Text(
            AppStrings.runPartyTitle,
            style: AppTypography.h3.copyWith(color: colors.textPrimary),
          ),
        ),
        // ⚠️ 파티원이 없어도 **내 카드는 그린다.** 상대가 취소하거나 재시작 뒤
        // 첫 통지가 오기 전이어도 내 기록은 계속 보여야 한다.
        for (final lane in lanes)
          Padding(
            key: ValueKey(lane.userId),
            padding: const EdgeInsets.only(bottom: AppSpacing.space3),
            child: _PartyCard(
              lane: lane,
              color: RunPalette.lane(board.colorSlotOf(lane.userId)),
              // 콤보 글로우·테두리는 **상대의 색과 내 색**이 섞인다.
              partnerColor: lane.isMe
                  ? (myCombo == null
                        ? null
                        : RunPalette.lane(board.colorSlotOf(myCombo.userId)))
                  : (lane.combo == null
                        ? null
                        : RunPalette.lane(board.colorSlotOf(board.myUserId))),
              comboCount: lane.isMe
                  ? myCombo?.comboCount
                  : lane.combo?.comboCount,
              bestCombo: lane.isMe
                  ? board.myBestCombo
                  : board.bestComboOf(lane.userId),
              meters: lane.isMe
                  ? board.myDistanceMeters
                  : lane.progress?.distanceMeters ?? 0,
              targetMeters: targetDistanceMeters,
              pace: lane.isMe
                  ? myPace
                  : switch (lane.progress?.currentPaceSecondsPerKm) {
                      final int s => Duration(seconds: s),
                      null => null,
                    },
              // 아래 줄. 상대는 격차, 나는 누구 곁인지(콤보 중) 또는 안내.
              footnote: lane.isMe
                  ? (myCombo == null
                        ? AppStrings.runPartyComboHint
                        : AppStrings.runPartyBeside(nameOf(myCombo.userId)))
                  : (lane.gapMeters == null
                        ? null
                        : AppStrings.runPartyGapLine(lane.gapMeters!)),
              // 덮개 한 줄. 상대 카드에는 내 이름, 내 카드에는 상대 이름.
              impactLine: lane.isMe
                  ? (myCombo == null ? '' : nameOf(myCombo.userId))
                  : nameOf(board.myUserId),
              stale: _stale(lane, clock),
            ),
          ),
        if (board.rows.isEmpty)
          Text(
            AppStrings.runPartyEmpty,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }

  /// 통지가 끊긴 것으로 보이는가. 서버는 끊김을 알리지 않으므로 시간으로 본다.
  static bool _stale(PartyRow lane, DateTime now) {
    final at = lane.progress?.receivedAt;
    return at != null && now.difference(at) > PartyBoard.staleAfter;
  }
}

/// 카드 하나. 콤보가 오르면 임팩트를 스스로 재생한다.
class _PartyCard extends StatefulWidget {
  const _PartyCard({
    required this.lane,
    required this.color,
    required this.partnerColor,
    required this.comboCount,
    required this.bestCombo,
    required this.meters,
    required this.targetMeters,
    required this.pace,
    required this.footnote,
    required this.impactLine,
    required this.stale,
  });

  final PartyRow lane;
  final Color color;

  /// 나와 콤보가 이어졌을 때 상대(또는 나)의 색. `null`이면 콤보가 없다.
  final Color? partnerColor;

  /// 지금 이어지는 콤보. `null`이면 없다.
  final int? comboCount;

  /// 이 러닝의 최고 콤보. 콤보가 없을 때 배지에 남는다.
  final int bestCombo;
  final int meters;
  final int? targetMeters;
  final Duration? pace;
  final String? footnote;

  /// 임팩트 덮개 아래 한 줄에 넣을 상대 이름.
  final String impactLine;
  final bool stale;

  @override
  State<_PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends State<_PartyCard> with TickerProviderStateMixin {
  static const _staleOpacity = 0.4;
  static const _borderWidth = 1.5;

  /// 임팩트 전체. 덮개가 덮이고(10%) → 숫자가 튀고(28%) → 앉고(42%) → 머물다
  /// (78%) → 배지 자리로 날아가며 덮개가 걷힌다(100%).
  late final AnimationController _impact = AnimationController(
    vsync: this,
    duration: AppMotion.revealLong,
  );

  /// 임팩트가 끝난 직후 배지가 한 번 튕긴다.
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  late final Animation<double> _coverOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1), weight: 68),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 22),
  ]).animate(_impact);

  late final Animation<double> _textScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.3,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 28,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 14),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.02), weight: 36),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.02,
        end: 0.3,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 22,
    ),
  ]).animate(_impact);

  late final Animation<double> _textOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 20),
    TweenSequenceItem(tween: ConstantTween(1), weight: 58),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 22),
  ]).animate(_impact);

  late final Animation<double> _textAngle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -10, end: 3), weight: 28),
    TweenSequenceItem(tween: Tween(begin: 3, end: 0), weight: 14),
    TweenSequenceItem(tween: ConstantTween(0), weight: 58),
  ]).animate(_impact);

  /// 마지막 22%에 배지 자리(오른쪽 아래)로 날아간다. 카드 크기 비율이다.
  late final Animation<Offset> _textSlide = TweenSequence<Offset>([
    TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 78),
    TweenSequenceItem(
      tween: Tween(
        begin: Offset.zero,
        end: const Offset(0.35, 0.65),
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 22,
    ),
  ]).animate(_impact);

  late final Animation<double> _ringScale = Tween<double>(begin: 0.35, end: 2.4)
      .chain(CurveTween(curve: Curves.easeOut))
      .animate(
        CurvedAnimation(parent: _impact, curve: const Interval(0, 0.56)),
      );

  late final Animation<double> _ringOpacity = Tween<double>(
    begin: 0.95,
    end: 0,
  ).animate(CurvedAnimation(parent: _impact, curve: const Interval(0, 0.56)));

  late final Animation<double> _bumpScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.55), weight: 45),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.55,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 55,
    ),
  ]).animate(_bump);

  @override
  void initState() {
    super.initState();
    _impact.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _impact.reset();
        _bump.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(_PartyCard old) {
    super.didUpdateWidget(old);
    // 콤보가 **오를 때만** 튄다. 처음 이어질 때(null→1)도 오르는 것이다.
    final before = old.comboCount ?? 0;
    final after = widget.comboCount ?? 0;
    if (after > before && !_impact.isAnimating) {
      _impact.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _impact.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final partner = widget.partnerColor;
    final color = widget.color;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space5,
        AppSpacing.space4,
        AppSpacing.space5,
        AppSpacing.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(lane: widget.lane, color: color),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Expanded(
                child: _BigStat(
                  label: AppStrings.runPartyDistanceLabel,
                  value: AppStrings.runPartyKm1(widget.meters),
                  unit: widget.targetMeters == null
                      ? AppStrings.runPartyUnitKm
                      : '/ ${AppStrings.runPartyTargetKm(widget.targetMeters!)}',
                ),
              ),
              Expanded(
                child: _BigStat(
                  label: AppStrings.runPartyPaceLabel,
                  value: PaceCalculator.format(widget.pace),
                  unit: AppStrings.runPartyUnitPerKm,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          _Bar(
            color: color,
            meters: widget.meters,
            targetMeters: widget.targetMeters,
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.footnote ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: partner ?? colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              ScaleTransition(
                scale: _bumpScale,
                child: _Badge(
                  color: color,
                  comboCount: widget.comboCount,
                  bestCombo: widget.bestCombo,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // 콤보 중이면 두 사람 색을 섞은 테두리. 아니면 표면색 그대로.
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.xl,
        gradient: partner == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, partner],
              ),
        boxShadow: partner == null ? null : RunPalette.glow(partner),
      ),
      padding: const EdgeInsets.all(_borderWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          AppRadius.xl.topLeft.x - _borderWidth,
        ),
        child: Stack(
          children: [
            ColoredBox(color: colors.bgSurface, child: body),
            Positioned.fill(
              child: _Impact(
                controller: _impact,
                coverOpacity: _coverOpacity,
                textScale: _textScale,
                textOpacity: _textOpacity,
                textAngle: _textAngle,
                textSlide: _textSlide,
                ringScale: _ringScale,
                ringOpacity: _ringOpacity,
                color: color,
                partner: partner ?? color,
                count: widget.comboCount ?? 0,
                line: widget.impactLine,
              ),
            ),
          ],
        ),
      ),
    );

    return Opacity(opacity: widget.stale ? _staleOpacity : 1, child: card);
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.lane, required this.color});

  final PartyRow lane;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name =
        lane.member?.nickname ??
        (lane.isMe ? AppStrings.runPartyMe : AppStrings.runPartyUnknown);
    final photo = lane.member?.profileImageUrl;
    final initial = Text(
      name.isEmpty ? '' : name.characters.first,
      style: AppTypography.caption.copyWith(
        color: colors.textOnPrimary,
        fontWeight: FontWeight.w700,
      ),
    );

    return Row(
      children: [
        Container(
          width: AppSpacing.space7,
          height: AppSpacing.space7,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: photo == null
              ? initial
              : Image.network(
                  photo,
                  fit: BoxFit.cover,
                  // 만료된 presigned URL이면 이니셜로 돌아간다.
                  errorBuilder: (_, error, stack) => initial,
                ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // 이름이 있을 때만 `나` 꼬리표를 단다. 이름을 모르면 제목이 이미 `나`다.
        if (lane.isMe && lane.member?.nickname != null)
          Text(
            AppStrings.runPartyMe,
            style: AppTypography.micro.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }
}

/// `현재 거리` 위, `2.31 / 3 km` 아래. 큰 숫자.
class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.micro.copyWith(color: colors.textTertiary),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                style: AppTypography.metricLg.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space1),
            Text(
              unit,
              style: AppTypography.caption.copyWith(
                color: colors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 진행 막대. 자기 색으로 채우고 끝이 흐려지며 뒤로 빛이 번진다.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.color,
    required this.meters,
    required this.targetMeters,
  });

  final Color color;
  final int meters;
  final int? targetMeters;

  static const _height = AppSpacing.space4;
  static const _trackAlpha = 0.18;
  static const _glowSigma = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final target = targetMeters;
    final ratio = target == null || target <= 0
        ? 0.0
        : (meters / target).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: AppRadius.full,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth * ratio;
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: colors.textPrimary.withValues(alpha: _trackAlpha),
                  ),
                ),
                // 10초마다 값이 튄다. 애니메이션이 없으면 뚝뚝 뛴다.
                AnimatedPositioned(
                  duration: AppMotion.slow,
                  curve: AppMotion.easeStandard,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: _glowSigma,
                      sigmaY: _glowSigma,
                    ),
                    child: ColoredBox(color: color),
                  ),
                ),
                AnimatedPositioned(
                  duration: AppMotion.slow,
                  curve: AppMotion.easeStandard,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.full,
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0)],
                        stops: const [0.6, 1],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 오른쪽 아래 작은 배지. 콤보 중이면 `12콤보`(자기 색), 아니면 `최고 7`(회색).
/// 최고가 0이면 자리만 비운다.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.comboCount,
    required this.bestCombo,
  });

  final Color color;
  final int? comboCount;
  final int bestCombo;

  static const _tintAlpha = 0.16;
  static const _mutedAlpha = 0.08;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final count = comboCount;
    if (count == null && bestCombo == 0) return const SizedBox.shrink();

    final active = count != null;
    final ink = active ? color : colors.textTertiary;
    return Container(
      height: AppSpacing.space6,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
      decoration: BoxDecoration(
        borderRadius: AppRadius.full,
        color: active
            ? color.withValues(alpha: _tintAlpha)
            : colors.textPrimary.withValues(alpha: _mutedAlpha),
      ),
      alignment: Alignment.center,
      child: Text(
        active
            ? AppStrings.runPartyCombo(count)
            : AppStrings.runPartyBestCombo(bestCombo),
        style: AppTypography.micro.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 임팩트 덮개. 컨트롤러가 멈춰 있으면 아무것도 그리지 않는다.
class _Impact extends StatelessWidget {
  const _Impact({
    required this.controller,
    required this.coverOpacity,
    required this.textScale,
    required this.textOpacity,
    required this.textAngle,
    required this.textSlide,
    required this.ringScale,
    required this.ringOpacity,
    required this.color,
    required this.partner,
    required this.count,
    required this.line,
  });

  final AnimationController controller;
  final Animation<double> coverOpacity;
  final Animation<double> textScale;
  final Animation<double> textOpacity;
  final Animation<double> textAngle;
  final Animation<Offset> textSlide;
  final Animation<double> ringScale;
  final Animation<double> ringOpacity;
  final Color color;
  final Color partner;
  final int count;
  final String line;

  static const _ringSize = 120.0;
  static const _ringWidth = 3.0;
  static const _coverAlpha = 0.45;
  static const _lineAlpha = 0.7;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isDismissed) return const SizedBox.shrink();
        return IgnorePointer(
          child: Opacity(
            opacity: coverOpacity.value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.2),
                  radius: 1.2,
                  colors: [
                    Color.alphaBlend(
                      color.withValues(alpha: _coverAlpha),
                      colors.bgSurface,
                    ),
                    Color.alphaBlend(
                      partner.withValues(alpha: _coverAlpha),
                      colors.bgSurface,
                    ),
                    colors.bgSurface,
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: ringOpacity.value,
                    child: Transform.scale(
                      scale: ringScale.value,
                      child: Container(
                        width: _ringSize,
                        height: _ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.textPrimary,
                            width: _ringWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                  FractionalTranslation(
                    translation: textSlide.value,
                    child: Opacity(
                      opacity: textOpacity.value,
                      child: Transform.rotate(
                        angle: textAngle.value * math.pi / 180,
                        child: Transform.scale(
                          scale: textScale.value,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [color, colors.textPrimary, partner],
                                ).createShader(bounds),
                                blendMode: BlendMode.srcIn,
                                child: Text(
                                  '$count',
                                  style: AppTypography.metricHero.copyWith(
                                    color: colors.textPrimary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space2),
                              Text(
                                AppStrings.runPartyImpactCombo,
                                style: AppTypography.h2.copyWith(
                                  color: colors.textPrimary,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (line.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: AppSpacing.space3,
                      child: Text(
                        AppStrings.runPartyBeside(line),
                        textAlign: TextAlign.center,
                        style: AppTypography.micro.copyWith(
                          color: colors.textPrimary.withValues(
                            alpha: _lineAlpha,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
