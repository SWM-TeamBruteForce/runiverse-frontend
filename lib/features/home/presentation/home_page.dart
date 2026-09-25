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
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
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
            room.status == RoomStatus.matched ||
            // ⚠️ **시작된 방도 히어로가 맡는다.** 빼 두면 달리는 중에 홈이
            // 기본 화면으로 보이고, 들어갈 문이 없다.
            room.status == RoomStatus.started);

    // ⚠️ 스냅샷이 없어도 **확정된 러닝에는 들어갈 수 있어야 한다.**
    //
    // 스트림이 옛 방을 주거나 늦게 붙는 동안 방 정보가 비는데, 그때 아무것도
    // 안 그리면 확정된 사람이 홈에서 길을 잃는다. 상태 조회가 아는 것(방 번호·
    // 시작 시각·목표)만으로 카운트다운과 입장 버튼을 세운다.
    final shown = counting ? room : RoomInfo.fromStatus(status);

    // ⚠️ **방금 끝낸 방은 내놓지 않는다.**
    //
    // 종료 확인을 받은 뒤에도 서버 상태가 잠시 `RUNNING`을 돌려준다. 그 값만
    // 믿으면 여기에 "러닝 화면으로 가기"가 뜨고, 눌러도 `NOT_ROOM_PLAYER`만
    // 받는다(2026-09-19 01:40 실주행). 그 구간에서는 **앱이 서버보다 잘 안다.**
    final finishedId = ref.watch(
      runningConnectionProvider.select((it) => it.finishedRoomId),
    );
    final hero = shown != null && shown.runningRoomId == finishedId
        ? null
        : shown;

    // 상태를 못 읽었을 때 들어갈 자리. [_enterStartedRun] 참조.
    _fallbackRoom = hero;

    // 이탈·조기 종료 제재. **매칭 신청만 막고 솔로는 열어 둔다.**
    final cooldownUntil = status?.cooldownUntil;
    final cooling =
        cooldownUntil != null && cooldownUntil.isAfter(DateTime.now());

    // ⚠️ 빌드 중에 타이머를 만들면 그 프레임에서 `setState`가 겹친다. 미룬다.
    //
    // ⚠️ **제한이 걸린 동안에도 돌린다.** 안 돌리면 `_now`가 굳어 제한이
    // 끝나도 버튼이 잠긴 채로 남고, 탭을 옮겼다 와야 풀린다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncTicker(needed: counting || cooling),
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
              room: hero,
              // ⚠️ 상태는 매칭 중인데 스냅샷이 아직 안 온 구간. 여기를 비우면
              // 신청한 사람이 기본 히어로를 보고 다시 누른다.
              pending:
                  hero == null &&
                  status != null &&
                  RunResume.showsMatchBanner(status),
              now: _now,
              cooldownUntil: cooldownUntil,
              // 조건을 고르는 화면(S08)을 거친다. 홈에서 바로 신청하면
              // 시간대도 거리도 정할 수 없다.
              onMatch: () => context.push(AppRoutes.matchRegister),
              // 준비 화면을 거친다. GPS 첫 신호를 기다릴 자리가 필요하다 —
              // 신호 전에 출발하면 초반 거리가 통째로 빠진다.
              onSolo: () => context.push(AppRoutes.runPrepare),
              onCancel: _confirmCancel,
              // ⚠️ **이미 시작한 방은 대기실이 아니라 러닝 화면이다.**
              // 대기실로 보내면 카운트다운이 0인 화면에서 한 번 더 눌러야 한다.
              onLobby: () => hero != null && hero.status == RoomStatus.started
                  ? unawaited(_enterStartedRun())
                  : context.push(AppRoutes.matchRoom),
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

  /// 이미 시작한 러닝으로 들어간다.
  ///
  /// ## ⚠️ 화면만 띄우면 안 된다
  ///
  /// 러닝 화면은 스스로 붙지 않는다. 스플래시가 복구할 때와 **같은 순서**로
  /// 방에 다시 붙이고 출발 시각부터 이어 재야 한다 — 빼먹으면 "서버에
  /// 연결하는 중이에요"에서 멈춘다.
  ///
  /// 매칭 방만 이 길로 온다. 솔로는 준비 화면이 맡는다.
  ///
  /// ## ⚠️ 들어가기 전에 상태를 다시 읽는다
  ///
  /// 히어로가 들고 있는 방은 **마지막으로 읽은 상태**에서 나온 것이다. 그
  /// 사이에 러닝이 끝났으면 이미 끝난 방으로 들어가려 하고, 서버가
  /// `NOT_ROOM_PLAYER`로 거절한다 — 앱은 러닝을 접고 홈으로 되돌아온다
  /// (2026-09-19 00:44 실주행).
  ///
  /// 그래서 **새로 읽은 값으로** 들어간다. 방 번호까지 그쪽 것을 쓴다 —
  /// 그사이 다른 방에 배정됐을 수도 있다.
  ///
  /// ⚠️ **못 읽었으면 그래도 들어간다.** 판정에 실패했다고 막으면 신호가
  /// 나쁜 곳에서 달리던 사람이 자기 러닝으로 못 돌아간다. 틀렸을 때의 값은
  /// `NOT_ROOM_PLAYER` 한 번이고, 그 길은 이미 안내와 함께 홈으로 돌아온다.
  Future<void> _enterStartedRun() async {
    if (_entering) return;
    _entering = true;

    try {
      final status = await ref.read(userStatusProvider.notifier).refresh();
      if (!mounted) return;

      // 서버가 **더는 달리는 중이 아니라고** 말했다. 히어로가 새 상태로 알아서
      // 다시 그려지므로 여기서 따로 알릴 것이 없다.
      if (status != null && (status is! UserStatusRunning || status.isSolo)) {
        return;
      }

      final room = status is UserStatusRunning
          ? RoomInfo.fromStatus(status)
          : _fallbackRoom;
      if (room == null) return;

      unawaited(
        ref
            .read(runningConnectionProvider.notifier)
            .reopen(
              room.runningRoomId,
              targetDistanceMeters: room.targetDistanceMeters,
            ),
      );
      unawaited(
        ref
            .read(runSessionControllerProvider.notifier)
            .startWhenReady(since: room.scheduledStartAt),
      );
      unawaited(context.push(AppRoutes.runSession));
    } finally {
      _entering = false;
    }
  }

  /// 들어가는 중인가. 상태를 읽는 동안 두 번 눌리는 것을 막는다.
  var _entering = false;

  /// 상태를 못 읽었을 때 쓸 방. 화면이 들고 있던 것이다.
  RoomInfo? _fallbackRoom;

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
