import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/preset_chip.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/settings/domain/login_type.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';
import 'package:runiverse/features/settings/presentation/withdraw_sheet.dart';

/// 설정 (S22.2).
///
/// ## 탭 셸 밖이다
///
/// 프로필 편집(S22.1)과 같은 이유다 — 하단 탭이 함께 보이면 설정을 하다 말고
/// 다른 탭으로 샌다.
///
/// ## 한 화면이다
///
/// 기능정의서는 `SETTING-NOTIFICATION-001`·`SETTING-VISIBILITY-001`처럼 코드를
/// 나눠 두었지만 **그것은 기능 목록의 분류이지 화면 분할이 아니다.**
/// `PATCH /settings`는 필드 두 개짜리 API 하나라, 화면을 셋으로 쪼개면 같은
/// API를 세 군데서 부르게 된다.
///
/// ## ⚠️ 조회에 실패해도 로그아웃은 눌린다
///
/// 세션이 이상해서 조회가 실패하는 경우가 있는데, 그때 로그아웃까지 막히면
/// 사용자가 앱에서 나갈 방법이 없다.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  void initState() {
    super.initState();
    // 빌드 중에 provider를 고치면 죽는다 (`docs/implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(settingsControllerProvider.notifier).load();
    });
  }

  // ── 바꾸기 ────────────────────────────────────────────────

  Future<void> _setAlertConsent(bool value) async {
    final failure = await ref
        .read(settingsControllerProvider.notifier)
        .setAlertConsent(value);
    _reportIfFailed(failure);
  }

  Future<void> _setVisibility(ProfileVisibility value) async {
    final failure = await ref
        .read(settingsControllerProvider.notifier)
        .setVisibility(value);
    _reportIfFailed(failure);
  }

  /// 낙관적 반영이 되돌아갔음을 알린다.
  ///
  /// **되돌린 것을 말해주지 않으면** 사용자는 껐다고 생각하고 나간다.
  void _reportIfFailed(SettingsFailure? failure) {
    // `await` 뒤라 화면이 이미 사라졌을 수 있다.
    if (!mounted || failure == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == SettingsFailure.sessionExpired
              ? AppStrings.settingsSessionExpired
              : AppStrings.settingsUpdateFailed,
        ),
      ),
    );
  }

  // ── 로그아웃 ──────────────────────────────────────────────

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.bgElevated,
        title: const Text(AppStrings.settingsSignOutTitle),
        content: const Text(AppStrings.settingsSignOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.settingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.settingsSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(authControllerProvider.notifier).signOut();
    _leave();
  }

  /// 로그인 화면으로 내보낸다.
  ///
  /// ## ⚠️ 상태를 바꾸는 것만으로는 화면이 옮겨지지 않는다
  ///
  /// 라우터에 인증 `redirect`가 **아직 없다**(`app_router.dart`의 "아직 안 한 것").
  /// `AppShell`의 관문도 `AuthSignedIn`일 때만 서는데, 이 화면은 **셸 밖**이라
  /// 그 앞도 지나지 않는다. 여기서 옮기지 않으면 로그아웃한 사람이 설정 화면에
  /// 그대로 남고, 뒤로 가면 로그인하지 않은 채로 홈이 보인다.
  ///
  /// `push`가 아니라 `go`인 것은 **스택을 비우기 위해서**다. 로그아웃한 뒤
  /// 뒤로가기로 설정 화면에 돌아올 수 있으면 안 된다.
  ///
  /// 라우터에 `redirect`가 붙으면 이 호출은 지운다.
  void _leave() {
    if (mounted) context.go(AppRoutes.signIn);
  }

  // ── 약관 ──────────────────────────────────────────────────

  /// 문서 주소가 아직 없다.
  ///
  /// 행을 감추지 않는 이유는, **약관을 볼 수 있어야 한다는 사실 자체가 약속**이라
  /// 자리를 비워두면 나중에 붙이는 것을 잊기 때문이다.
  void _openTerms() {
    // 주소가 채워지면 여기서 `url_launcher`로 연다.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.settingsTermsPending)),
    );
  }

  // ── 탈퇴 ──────────────────────────────────────────────────

  Future<void> _withdraw() async {
    if (!await showWithdrawSheet(context) || !mounted) return;

    final failure = await ref
        .read(settingsControllerProvider.notifier)
        .withdraw();
    if (!mounted) return;

    if (failure == null) {
      // 계정이 사라졌다. 로그아웃과 같은 곳으로 내보낸다.
      _leave();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.withdrawFailed)));
  }

  // ── 그리기 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(settingsControllerProvider);
    final settings = state.settings;
    final account = state.account;
    final failed = state.isEmpty && state.failure != null;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(AppStrings.settingsTitle, style: AppTypography.h3),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space2,
            AppSpacing.space4,
            AppSpacing.space8,
          ),
          children: [
            if (failed)
              _ErrorCard(
                onRetry: () =>
                    ref.read(settingsControllerProvider.notifier).load(),
              )
            else ...[
              const _SectionLabel(AppStrings.settingsNotificationSection),
              _Card(
                children: [
                  _SwitchRow(
                    label: AppStrings.settingsAlertConsent,
                    description: AppStrings.settingsAlertConsentWhy,
                    // 아직 못 읽었으면 끈 것처럼 두고 누르지 못하게 한다.
                    // 켜 보이게 두면 실제 값과 반대일 수 있다.
                    value: settings?.alertConsent ?? false,
                    onChanged: settings == null ? null : _setAlertConsent,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space6),
              const _SectionLabel(AppStrings.settingsVisibilitySection),
              _VisibilityChips(
                value: settings?.visibility,
                onChanged: settings == null ? null : _setVisibility,
              ),
            ],
            const SizedBox(height: AppSpacing.space6),
            const _SectionLabel(AppStrings.settingsAccountSection),
            _Card(
              children: [
                _ValueRow(
                  label: AppStrings.settingsEmail,
                  value: account?.email,
                ),
                _ValueRow(
                  label: AppStrings.settingsLoginMethod,
                  value: account == null
                      ? null
                      : _loginLabel(account.loginType),
                ),
                // 소셜 계정에는 비밀번호가 없다. 보여줬다가 409를 맞는 것보다
                // 안 보이는 편이 낫다. `loginType`을 못 읽었을 때도 숨는다.
                if (account?.canChangePassword ?? false)
                  _ActionRow(
                    label: AppStrings.settingsPassword,
                    onTap: () => context.push(AppRoutes.passwordChange),
                  ),
                _ActionRow(label: AppStrings.settingsTerms, onTap: _openTerms),
                // ⚠️ 조회가 실패해도 이 행은 살아 있다.
                _ActionRow(label: AppStrings.settingsSignOut, onTap: _signOut),
                _ActionRow(
                  label: AppStrings.settingsWithdraw,
                  onTap: _withdraw,
                  danger: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 서버가 모르는 제공자를 보내면 "확인 불가"다. 비밀번호 메뉴는 이때 숨는다.
  static String _loginLabel(LoginType? type) => switch (type) {
    LoginType.local => AppStrings.settingsLoginLocal,
    LoginType.kakao => AppStrings.settingsLoginKakao,
    LoginType.google => AppStrings.settingsLoginGoogle,
    null => AppStrings.settingsLoginUnknown,
  };
}

// ── 조각 ────────────────────────────────────────────────────

/// 섹션 이름. 카드 바깥에 작게 얹는다.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: AppSpacing.space1,
      bottom: AppSpacing.space2,
    ),
    child: Text(
      text,
      style: AppTypography.caption.copyWith(
        color: context.appColors.textSecondary,
      ),
    ),
  );
}

/// 행을 묶는 카드. 행 사이에 구분선을 넣는다.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.borderDefault),
      ),
      // 카드가 둥근데 안쪽 잉크가 각지면 모서리로 색이 삐져나온다.
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: colors.borderDefault),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 스위치가 붙은 행.
///
/// [onChanged]가 `null`이면 아직 값을 못 읽은 것이다 — 눌러도 반응하지 않는다.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onChanged != null;
    final text = description;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body.copyWith(
                    color: enabled ? colors.textPrimary : colors.textDisabled,
                  ),
                ),
                if (text != null) ...[
                  const SizedBox(height: AppSpacing.space0),
                  Text(
                    text,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 읽기만 하는 행. 바꾸는 API가 없다.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;

  /// `null`이면 아직 못 읽었다. 자리를 비워 두고 높이는 유지한다 —
  /// 값이 들어올 때 행이 튀어 오르면 누르려던 것을 놓친다.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = value;

    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          Text(label, style: AppTypography.body),
          const Spacer(),
          if (text != null)
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
            )
          else
            _Skeleton(color: colors.borderDefault),
        ],
      ),
    );
  }
}

/// 누르면 무언가 일어나는 행.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;

  /// 되돌릴 수 없는 동작. `error` 색으로 적는다.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = danger ? colors.error : colors.textPrimary;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Row(
            children: [
              Text(label, style: AppTypography.body.copyWith(color: color)),
              const Spacer(),
              Icon(LucideIcons.chevronRight, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공개 범위 칩 둘.
///
/// ⚠️ **정본은 3단이지만 서버 enum이 둘뿐이다.** "나만보기"를 만들면 저장할 데가 없다.
class _VisibilityChips extends StatelessWidget {
  const _VisibilityChips({required this.value, required this.onChanged});

  final ProfileVisibility? value;
  final ValueChanged<ProfileVisibility>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = value;
    final change = onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final option in ProfileVisibility.values) ...[
              if (option != ProfileVisibility.values.first)
                const SizedBox(width: AppSpacing.space2),
              PresetChip(
                label: _label(option),
                selected: option == selected,
                // 아직 못 읽었으면 눌러도 아무 일도 없다. 누른 것이 지금 값과
                // 같은지 알 수 없어, 되돌릴 자리도 없다.
                onTap: change == null ? () {} : () => change(option),
              ),
            ],
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.space1),
            child: Text(
              _description(selected),
              style: AppTypography.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ],
    );
  }

  static String _label(ProfileVisibility value) => switch (value) {
    ProfileVisibility.public => AppStrings.settingsVisibilityPublic,
    ProfileVisibility.followers => AppStrings.settingsVisibilityFollowers,
  };

  static String _description(ProfileVisibility value) => switch (value) {
    ProfileVisibility.public => AppStrings.settingsVisibilityPublicWhy,
    ProfileVisibility.followers => AppStrings.settingsVisibilityFollowersWhy,
  };
}

/// 값이 들어올 자리. 빈 칸보다 낫다 — 무엇을 기다리는지 보인다.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 96,
    height: 12,
    decoration: BoxDecoration(color: color, borderRadius: AppRadius.sm),
  );
}

/// 아무것도 읽지 못했을 때.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        children: [
          Text(
            AppStrings.settingsLoadFailed,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          TextButton(
            onPressed: onRetry,
            child: const Text(AppStrings.settingsRetry),
          ),
        ],
      ),
    );
  }
}
