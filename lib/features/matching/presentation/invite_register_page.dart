import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/core/widgets/v2/preset_chip.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/features/matching/presentation/invite_register_provider.dart';

/// 초대 등록 — 시각과 거리를 **자유롭게** 정해 방을 연다.
///
/// ## ⚠️ 매칭 등록과 같은 화면을 쓰지 않는다
///
/// 입력이 겹치지 않는다. 매칭은 서버가 준 슬롯 중 하나와 3/5/10km enum이고,
/// 초대는 분 단위 자유 시각과 1,000~42,195m 자유 거리다. 두 도메인 모델이
/// 자유 입력을 **막는 쪽으로** 적혀 있어서(`target_distance.dart`,
/// `match_slot.dart`) 그대로 쓸 수 없고, 707줄 안에서 두 모드가 엉키면 이미
/// 배포된 매칭이 같이 위험해진다.
///
/// 껍데기(`SurfaceCard`·`PresetChipV2`·`AppButtonV2`)와 실패를 스낵바로 알리고
/// 곧바로 지우는 패턴만 베껴 쓴다.
class InviteRegisterPage extends ConsumerStatefulWidget {
  const InviteRegisterPage({this.now, super.key});

  /// 기기 시각을 고정한다. **테스트만 넘긴다** — `23:49 이후` 화면은 실제
  /// 시계로는 하루 중 10분만 재현되는데, 그 10분을 못 지켜 깨지면 사용자는
  /// 비어 있는 피커를 본다.
  final DateTime? now;

  @override
  ConsumerState<InviteRegisterPage> createState() => _InviteRegisterPageState();
}

class _InviteRegisterPageState extends ConsumerState<InviteRegisterPage> {
  final _distance = TextEditingController();

  @override
  void dispose() {
    _distance.dispose();
    super.dispose();
  }

  /// 지금(KST 벽시계). **화면이 열려 있는 사이에 23:49를 넘길 수 있어** 매번
  /// 새로 읽는다.
  DateTime get _nowKst => KstTime.wallOf(widget.now ?? DateTime.now());

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(inviteRegisterProvider);
    final window = InviteRegisterState.windowAt(_nowKst);

    // 실패는 스낵바로 알리고 곧바로 지운다. 상태에 남겨두면 화면이 다시
    // 그려질 때마다 같은 말을 되풀이한다.
    ref.listen(inviteRegisterProvider.select((s) => s.failure), (_, failure) {
      if (failure == null) return;
      final message = ref.read(inviteRegisterProvider).message;
      _say(_failureMessage(failure, message));
      ref.read(inviteRegisterProvider.notifier).clearFailure();
    });

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          color: colors.textPrimary,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.inviteRegisterTitle,
          style: AppTypographyV2.heading07.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: window == null
            ? _closedToday(colors)
            : _form(state, window, colors),
      ),
    );
  }

  /// ⚠️ **23:49 이후다.** 바닥(지금 +11분)이 천장(오늘 23:59)을 넘었고 익일
  /// 예약은 안 된다. 빈 피커를 두면 고장으로 읽힌다.
  Widget _closedToday(AppColorsV2 colors) => const Center(
    child: EmptyStateV2(
      icon: LucideIcons.clock,
      message: AppStrings.inviteRegisterClosedToday,
      why: AppStrings.inviteRegisterClosedTodayWhy,
    ),
  );

  Widget _form(
    InviteRegisterState state,
    ({DateTime from, DateTime to}) window,
    AppColorsV2 colors,
  ) => Column(
    children: [
      Expanded(
        child: ListView(
          // 매칭 등록과 같은 여백이다.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space2,
            AppSpacing.space4,
            AppSpacing.space6,
          ),
          children: [
            _Label(AppStrings.inviteRegisterWhen),
            const SizedBox(height: AppSpacing.space3),

            _Field(
              onTap: () => unawaited(_pickTime(window)),
              child: Text(
                state.startAt == null
                    ? AppStrings.inviteRegisterTimePlaceholder
                    : '${AppStrings.inviteRegisterToday}  '
                          '${AppStrings.inviteRegisterTime(state.startAt!)}',
                style: AppTypographyV2.body04.copyWith(
                  color: state.startAt == null
                      ? colors.textTertiary
                      : colors.textStrong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),

            _Hint(AppStrings.inviteRegisterWindow(window.from, window.to)),
            const SizedBox(height: AppSpacing.space6),

            _Label(AppStrings.inviteRegisterHowFar),
            const SizedBox(height: AppSpacing.space3),

            _Field(
              child: TextField(
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                // 숫자가 흔들리지 않게 고정폭 숫자를 쓴다 — 러닝 수치의
                // 규칙이다(CLAUDE.md).
                style: AppTypographyV2.body04.copyWith(
                  color: colors.textStrong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: AppStrings.inviteRegisterDistancePlaceholder,
                  hintStyle: AppTypographyV2.body04.copyWith(
                    color: colors.textTertiary,
                  ),
                  suffixText: 'km',
                  suffixStyle: AppTypographyV2.body04.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: _onDistance,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),

            // 세 칸 균등. 왼쪽으로 쏠리면 오른쪽 빈자리가 "칩이 더 있는데
            // 잘렸나"로 읽힌다.
            Row(
              children: [
                for (final (index, shortcut)
                    in InviteLimits.shortcuts.indexed) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.space2),
                  Expanded(
                    child: PresetChipV2(
                      label: shortcut.label,
                      selected: state.meters == shortcut.meters,
                      onTap: () => _pickShortcut(shortcut.meters),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.space3),

            _Hint(AppStrings.inviteRegisterDistanceRange),
          ],
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space4,
          0,
          AppSpacing.space4,
          AppSpacing.space4,
        ),
        child: AppButtonV2(
          label: AppStrings.inviteRegisterSubmit,
          onPressed: state.canSubmit(nowKst: _nowKst)
              ? () => unawaited(_submit())
              : null,
        ),
      ),
    ],
  );

  /// 분 단위 피커. 범위 밖을 고르면 받지 않는다.
  Future<void> _pickTime(({DateTime from, DateTime to}) window) async {
    final current = ref.read(inviteRegisterProvider).startAt ?? window.from;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;

    final at = DateTime(
      window.from.year,
      window.from.month,
      window.from.day,
      picked.hour,
      picked.minute,
    );
    // 범위 밖이면 **고르지 않고 안내만 한다.** 받아 두면 버튼이 잠긴 이유를
    // 알 수 없다.
    if (at.isBefore(window.from) || at.isAfter(window.to)) {
      _say(AppStrings.inviteRegisterWindow(window.from, window.to));
      return;
    }
    ref.read(inviteRegisterProvider.notifier).pickTime(at);
  }

  /// 칩은 **자유 입력을 대신하지 않는다** — 눌러서 입력란을 채운다.
  void _pickShortcut(int meters) {
    _distance.text = _km(meters);
    ref.read(inviteRegisterProvider.notifier).setMeters(meters);
  }

  void _onDistance(String text) {
    final km = double.tryParse(text);
    ref
        .read(inviteRegisterProvider.notifier)
        .setMeters(km == null ? null : (km * 1000).round());
  }

  /// `21098` → `21.098`. 소수점 뒤 0은 떼고, 정수면 한 자리를 남긴다.
  static String _km(int meters) {
    final km = meters / 1000;
    if (km == km.roundToDouble()) return km.toStringAsFixed(1);
    return km.toString();
  }

  Future<void> _submit() async {
    final roomId = await ref
        .read(inviteRegisterProvider.notifier)
        .submit(nowKst: _nowKst);
    if (roomId == null || !mounted) return;

    // ⚠️ **순서가 정해져 있다 — 개설 응답을 받은 뒤에 붙는다.**
    //
    // 방 화면은 첫 스냅샷(`INVITE_ROOM_ENTRANCE`)이 와야 그려진다. 여기서
    // 붙이지 않으면 **방은 서버에 멀쩡히 만들어져 있는데 화면은 로딩만 돈다** —
    // provider는 유저 상태가 `WAITING`·`READY`라고 할 때만 스스로 붙고, 그
    // 상태는 아래 재조회가 끝나야 바뀐다.
    //
    // 활성 신청이 없는데 먼저 열면 서버가 404로 거절하므로 순서를 지킨다.
    // 매칭 등록도 같은 순서다(`match_register_page._submit`).
    ref.read(matchRoomProvider.notifier).connect();

    // 방이 생겼으니 서버가 아는 상태가 달라졌다. 홈 히어로와 앱 재시작 복구가
    // 이 값을 본다.
    await ref.read(userStatusProvider.notifier).refresh();
    if (!mounted) return;

    context.go(AppRoutes.matchRoom);
  }

  /// **서버 문구를 그대로 쓴다.** 없으면 갈래별 기본 문구다.
  String _failureMessage(InviteFailure failure, String? message) =>
      message ??
      switch (failure) {
        InviteFailure.startAtOutOfRange ||
        InviteFailure.invalidRequest => AppStrings.inviteRegisterOutOfRange,
        InviteFailure.alreadyInProgress =>
          AppStrings.inviteRegisterAlreadyInProgress,
        InviteFailure.onboardingNotCompleted =>
          AppStrings.inviteRegisterOnboarding,
        _ => AppStrings.inviteRegisterFailed,
      };

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 매칭 등록의 `_Label`과 **같은 타이포·색**이다.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypographyV2.body05.copyWith(
      color: context.appColorsV2.textStrong,
    ),
  );
}

/// 입력 칸. 매칭 등록의 `_SlotTrigger`와 **같은 치수**다.
///
/// ⚠️ **`minHeight`를 반드시 둔다.** 안 두면 글자 높이만큼 쪼그라들어 손가락이
/// 빗나가고(44 미만), 매칭 등록 옆에 두면 두 화면이 다른 앱처럼 보인다.
class _Field extends StatelessWidget {
  const _Field({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lg,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.lg,
          ),
          padding: const EdgeInsets.all(AppSpacing.space5),
          child: Row(
            children: [
              Expanded(child: child),
              if (onTap != null)
                AppIcon(
                  AppIcons.right,
                  size: AppSpacing.space6,
                  color: colors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypographyV2.body12.copyWith(
      color: context.appColorsV2.textTertiary,
    ),
  );
}
