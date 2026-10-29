import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/core/widgets/v2/preset_chip.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space6,
          ),
          children: [
            _Label(AppStrings.inviteRegisterWhen),
            SurfaceCard(
              child: InkWell(
                onTap: () => unawaited(_pickTime(window)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.space1,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.startAt == null
                              ? AppStrings.inviteRegisterWhen
                              : '${AppStrings.inviteRegisterToday}  '
                                    '${AppStrings.inviteRegisterTime(state.startAt!)}',
                          style: AppTypographyV2.body03.copyWith(
                            color: state.startAt == null
                                ? colors.textTertiary
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronDown,
                        size: AppSpacing.space4,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _Hint(AppStrings.inviteRegisterWindow(window.from, window.to)),

            const SizedBox(height: AppSpacing.space5),
            _Label(AppStrings.inviteRegisterHowFar),
            SurfaceCard(
              child: TextField(
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textAlign: TextAlign.center,
                style: AppTypographyV2.body02.copyWith(
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.0 km',
                  hintStyle: AppTypographyV2.body02.copyWith(
                    color: colors.textTertiary,
                  ),
                  suffixText: 'km',
                  suffixStyle: AppTypographyV2.body06.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                onChanged: _onDistance,
              ),
            ),

            const SizedBox(height: AppSpacing.space3),
            // ⚠️ **매칭의 3/5/10을 쓰지 않는다.** 그 셋은 서버가 같은 조건끼리
            // 묶는 **버킷** 때문에 있고, 초대 방에는 버킷이 없다. 그래서
            // **타자로 치기 고약하고 이름이 있는 거리**만 남긴다.
            //
            // 세 칸을 균등하게 깐다 — 왼쪽으로 쏠리면 오른쪽 빈자리가 "칩이 더
            // 있는데 잘렸나"로 읽힌다.
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
    // 방 화면이 유저 상태를 보고 스트림에 붙는다 — 여기서 열지 않는다.
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
    child: Text(
      text,
      style: AppTypographyV2.body11.copyWith(
        color: context.appColorsV2.textPrimary,
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.space2),
    child: Text(
      text,
      style: AppTypographyV2.body18.copyWith(
        color: context.appColorsV2.textTertiary,
      ),
    ),
  );
}
