import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/home/domain/greeting.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/domain/run_resume.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 홈 (S05).
///
/// 상단 히어로 + 하단 카드 스택 구조다. **히어로가 매칭 상태를 전담한다** —
/// 모집 중에는 갈 화면이 따로 없고 여기가 그 상태를 보여주는 유일한 자리다.
/// 확정되면 히어로의 `로비로 이동`이 방으로 가는 유일한 문이 된다.
///
/// 그래서 홈에서는 글로벌 스티키 배너를 띄우지 않는다 — 중복이다.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _ticker;

  /// 지금. 카운트다운이 이 값에서 나온다.
  var _now = DateTime.now();

  var _leaving = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 방이 있을 때만 시계를 돌린다. **기본 상태에서는 셀 것이 없다** —
  /// 매칭하지 않는 사람의 홈에서 1초마다 화면을 다시 그릴 이유가 없다.
  void _syncTicker({required bool needed}) {
    if (needed == (_ticker != null)) return;
    if (!needed) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 매칭 상태는 `AppShell`이 살려 둔 provider가 나른다 — 홈이 소유하지 않는다.
    final room = ref.watch(matchRoomProvider.select((state) => state.room));
    // 서버가 아는 상태. 방 정보가 오기 전 구간을 메우는 데 쓴다.
    final status = ref.watch(userStatusProvider);

    final counting =
        room != null &&
        (room.status == RoomStatus.matching ||
            room.status == RoomStatus.matched);
    // ⚠️ 빌드 중에 타이머를 만들면 그 프레임에서 `setState`가 겹친다. 미룬다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncTicker(needed: counting),
    );

    // 프로필 유도는 여기 없다. **`AppShell`이 관문으로 막아선다** —
    // 프로필 없이는 어느 탭도 쓸 수 없으므로 홈만 막는 것은 뜻이 없다.
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space8,
          ),
          children: [
            HomeHero(
              greeting: _greetingText(GreetingRule.of(DateTime.now())),
              room: counting ? room : null,
              // ⚠️ 상태는 매칭 중인데 스냅샷이 아직 안 온 구간. 여기를 비우면
              // 신청한 사람이 기본 히어로를 보고 다시 누른다.
              pending:
                  room == null &&
                  status != null &&
                  RunResume.showsMatchBanner(status),
              now: _now,
              // 조건을 고르는 화면(S08)을 거친다. 홈에서 바로 신청하면
              // 시간대도 거리도 정할 수 없다.
              onMatch: () => context.push(AppRoutes.matchRegister),
              // 준비 화면을 거친다. GPS 첫 신호를 기다릴 자리가 필요하다 —
              // 신호 전에 출발하면 초반 거리가 통째로 빠진다.
              onSolo: () => context.push(AppRoutes.runPrepare),
              onCancel: _confirmCancel,
              onLobby: () => context.push(AppRoutes.matchRoom),
            ),

            const SizedBox(height: AppSpacing.space7),

            _SectionLabel(AppStrings.homeSectionCompetition),
            const SizedBox(height: AppSpacing.space3),
            const EmptyStateCard(
              icon: LucideIcons.trophy,
              message: AppStrings.homeEmptyCompetition,
            ),
            const SizedBox(height: AppSpacing.space6),

            _SectionLabel(AppStrings.homeSectionRecentRun),
            const SizedBox(height: AppSpacing.space3),
            const EmptyStateCard(
              icon: LucideIcons.footprints,
              message: AppStrings.homeEmptyRecentRun,
              hint: AppStrings.homeEmptyRecentRunHint,
            ),
          ],
        ),
      ),
      backgroundColor: colors.bgBase,
    );
  }

  /// 모집 중에 빠진다.
  ///
  /// **마감 전이라 제재가 없다.** 확정 뒤의 나가기(로비)와 달리 겁줄 것이
  /// 없으므로 묻기만 하고 짧게 끝낸다.
  Future<void> _confirmCancel() async {
    if (_leaving) return;

    final colors = context.appColors;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(
          AppStrings.matchRoomLeaveTitle,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
        content: Text(
          AppStrings.matchRoomLeaveFree,
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.matchRoomStay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.matchRoomLeaveConfirm),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    _leaving = true;
    // 나가는 순서는 provider가 안다. 로비에서 나갈 때와 같은 순서여야 한다.
    final left = await ref.read(matchRoomProvider.notifier).leave();
    _leaving = false;
    if (!mounted || left) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(AppStrings.matchRoomLeaveFailed)),
      );
  }

  /// 시간대 → 문구. 판정은 [GreetingRule]이 하고 여기서는 문구만 고른다.
  static String _greetingText(Greeting greeting) => switch (greeting) {
    Greeting.morning => AppStrings.homeGreetingMorning,
    Greeting.afternoon => AppStrings.homeGreetingAfternoon,
    Greeting.evening => AppStrings.homeGreetingEvening,
    Greeting.night => AppStrings.homeGreetingNight,
  };
}

/// 카드 묶음 위에 붙는 라벨. 무엇이 아니라 **무엇의 목록**인지 알려준다.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: context.appColors.textTertiary,
      ),
    );
  }
}
