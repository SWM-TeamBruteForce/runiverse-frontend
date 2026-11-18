import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';
import 'package:runiverse/features/home/presentation/home_notice_provider.dart';

/// 홈 공지 띠 — 날씨 줄 아래 한 줄짜리 상자. **누를 수 없다.**
///
/// 줄 순서와 멈춤은 [HomeNoticeReel]이 정하고, 여기는 시계만 쥔다 — 한 줄을
/// [hold]만큼 보여 주고 다음으로 넘긴다.
///
/// ## 한 바퀴는 홈에 들어올 때 돈다
///
/// 홈이 처음 서거나 **다른 탭에서 홈 탭으로 돌아올 때**다. 탭들은 한 번 열리면
/// 살아 있어서(`StatefulShellRoute.indexedStack`) 이 위젯이 다시 서지 않는다.
/// 대신 안 보이는 탭을 go_router가 `TickerMode(enabled: false)`로 감싸므로,
/// 그 값이 켜지는 때를 돌아온 때로 본다.
///
/// 매칭 상태(대기·확정 카드)와 무관하게 같은 띠다.
class HomeNoticeStrip extends ConsumerStatefulWidget {
  const HomeNoticeStrip({super.key});

  /// 한 줄을 보여 주는 시간. 짧은 슬라이드는 5~7초가 읽기 좋다(Baymard).
  static const hold = Duration(seconds: 5);

  /// [AppStrings.homeNoticeUpdate]가 나온 날. 그날부터 1주일 동안 띠 맨 앞에
  /// 선다.
  ///
  /// ⚠️ **알릴 기능이 있는 운영 릴리스 때 공개일로 채운다**(`docs/release.md`).
  static final updateSince = DateTime(2026, 11, 19);

  @override
  ConsumerState<HomeNoticeStrip> createState() => _HomeNoticeStripState();
}

class _HomeNoticeStripState extends ConsumerState<HomeNoticeStrip> {
  final _reel = HomeNoticeReel(updateSince: HomeNoticeStrip.updateSince);
  Timer? _timer;

  /// 홈 탭이 보이는가. 꺼진 동안은 넘기지 않는다.
  bool? _active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _active) return;
    _active = active;

    if (active) {
      _reel.restart(ref.read(homeNoticeProvider).activity, DateTime.now());
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 지금 줄을 [HomeNoticeStrip.hold]만큼 보여 준 뒤 넘긴다. 마지막 줄이면
  /// 멈춘다.
  void _schedule() {
    _timer?.cancel();
    if (_reel.stopped || _active != true) return;
    _timer = Timer(HomeNoticeStrip.hold, () {
      if (!mounted) return;
      setState(_reel.advance);
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ **활동 값만 듣는다.** 대기 수는 10초마다 오는데, 그것까지 들으면
    // 그때마다 이 위젯이 다시 그려진다 — 줄은 안 바뀌어도 쓸데없다.
    ref.listen(homeNoticeProvider.select((s) => s.activity), (_, next) {
      final before = _reel.turns;
      final wasStopped = _reel.stopped;
      setState(() => _reel.receive(next, DateTime.now()));
      // 줄이 바뀌었으면 새 줄도 제 시간을 다 보여 준다. 줄은 그대로여도 멈춰
      // 있던 띠가 돌 거리가 생겼으면(값을 기다리던 워치 줄) 시계를 건다.
      if (_reel.turns != before || (wasStopped && !_reel.stopped)) {
        _schedule();
      }
    });

    final colors = context.appColorsV2;
    final text = _textOf(_reel.current);

    return Container(
      // 위아래 16 — 12면 바로 아래 340짜리 히어로 옆에서 가는 줄처럼 보였다.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space4,
      ),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        // 아래 혼자 연습하기·초대 러닝 타일과 같은 색·여백이라 둥글기도 맞춘다.
        // 12면 같은 색 상자인데 띠만 각져 다른 부품처럼 보였다.
        borderRadius: AppRadius.lg,
      ),
      child: Row(
        children: [
          // 확성기 — 이 줄이 소식이라는 걸 말한다. 회색이라 날씨 줄 핀과 같은
          // 보조 정보 위계이고, 아래 파란 매칭 버튼보다 앞서지 않는다.
          Icon(
            LucideIcons.megaphone,
            size: AppSpacing.space4,
            color: colors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            // 넘어가는 줄이 상자 밖으로 삐져나와 보이지 않게 자른다.
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.easeStandard,
                switchOutCurve: AppMotion.easeStandard,
                transitionBuilder: _slideUp,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  text,
                  // 같은 줄의 숫자만 바뀌면 넘기지 않는다 — 키가 같다.
                  key: ValueKey(_reel.turns),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypographyV2.body11.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 새 줄은 아래에서 올라오고, 지난 줄은 위로 빠진다.
  ///
  /// ⚠️ **들어오는지 나가는지를 키로 가리지 않는다.** `AnimatedSwitcher`는 줄이
  /// 들어올 때 감싼 것을 나갈 때 그대로 쓴다 — 키로 갈라 시작점을 아래로 잡으면
  /// 나갈 때도 아래로 빠진다. 나가는 줄은 애니메이션이 거꾸로(1→0) 도니
  /// 그것으로 가린다.
  static Widget _slideUp(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final rest = 1 - animation.value;
            final leaving = animation.status == AnimationStatus.reverse;
            return FractionalTranslation(
              translation: Offset(0, leaving ? -rest : rest),
              child: child,
            );
          },
        ),
      );

  static String _textOf(HomeNoticeLine line) => switch (line) {
    HomeNoticeUpdate() => AppStrings.homeNoticeUpdate,
    HomeNoticeWatch() => AppStrings.homeNoticeWatch,
    HomeNoticeRunningNow(:final count) => AppStrings.homeNoticeRunningNow(
      count,
    ),
    HomeNoticeFinished(:final run) => AppStrings.homeNoticeFinished(
      run.nickname,
      run.distanceMeters,
    ),
    HomeNoticeToday(:final count) => AppStrings.homeNoticeToday(count),
    HomeNoticeYesterday(:final count) => AppStrings.homeNoticeYesterday(count),
  };
}
