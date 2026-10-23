import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/config/legal_links.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/legal_document.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/preset_chip.dart';
import 'package:runiverse/features/auth/domain/login_type.dart';
import 'package:runiverse/features/auth/domain/private_relay_email.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/utils/age_rule.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
// ⚠️ **설정이 프로필의 provider를 읽는다.** feature를 가로지르지만 provider는
// 예외이고, 방향은 `settings → profile` 한쪽뿐이다(`CLAUDE.md`).
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';
import 'package:runiverse/features/settings/presentation/withdraw_sheet.dart';

// TODO(되살리기): 알림 동의·공개 범위를 서버에 저장하게 되면 true로.
// 빌드 때 고정하는 숨김이다(원격 설정 아님).
const _showPreferences = false;

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
  /// 51번(`GET /users/me/profile`)을 아직 기다리는가. 그동안 신체 정보 두 줄은
  /// 잠긴다.
  bool _bodyLoading = true;

  /// 51번이 실패했는가. **빈 응답과 다르다** — 빈 응답은 온보딩 전이라
  /// 덮어쓸 값이 없고, 실패는 서버 값을 모르는 것이라 덮으면 안 된다.
  bool _bodyFailed = false;

  /// 생년월일·키·몸무게를 만질 수 있는가.
  bool get _bodyEditable => !_bodyLoading && !_bodyFailed;

  @override
  void initState() {
    super.initState();
    // 빌드 중에 provider를 고치면 죽는다 (`docs/implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showPreferences) {
        ref.read(settingsControllerProvider.notifier).load();
      }
      _loadBody();
    });
  }

  /// 서버가 가진 신체 정보를 받아 두 줄을 채운다(51번).
  ///
  /// ⚠️ **기준값을 따로 두지 않는다.** 바뀐 것을 가리는 기준은
  /// `bodyProfileProvider`이고, 이 호출이 그것을 서버 값으로 맞춘다 — 그래서
  /// 시트를 열어 키만 고치면 몸무게는 "안 바뀐 것"이 되어 요청에 실리지 않는다.
  Future<void> _loadBody() async {
    final loaded = await ref.read(bodyProfileProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _bodyLoading = false;
      _bodyFailed = !loaded;
    });
  }

  // ── 바꾸기 ────────────────────────────────────────────────

  Future<void> _setAlertConsent(bool value) async {
    final failure = await ref
        .read(settingsControllerProvider.notifier)
        .setAlertConsent(value);
    _reportIfFailed(failure);
  }

  // ── 신체 정보 ─────────────────────────────────────────────

  /// 생년월일을 고른다. **고르는 즉시 보낸다** — 설정에는 저장 버튼이 없다.
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final body = ref.read(bodyProfileProvider);
    final current = body.birthday ?? DateTime(now.year - 27, 4, 12);

    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profileBirthLabel,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitYear,
          // ⚠️ 상한은 `AgeRule`이 정한다. 온보딩 화면과 같은 값을 써야 한다.
          values: [
            for (var y = now.year - 80; y <= AgeRule.latestYear(now); y++) y,
          ],
          initial: current.year,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitMonth,
          values: [for (var m = 1; m <= 12; m++) m],
          initial: current.month,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitDay,
          values: [for (var d = 1; d <= 31; d++) d],
          initial: current.day,
          // 일 목록은 년·월에 달렸다. 다음 달 0일 = 이번 달 마지막 날.
          valuesFor: (picked) => [
            for (var d = 1; d <= DateTime(picked[0], picked[1] + 1, 0).day; d++)
              d,
          ],
        ),
      ],
    );
    if (picked == null) return;

    final birthday = DateTime(picked[0], picked[1], picked[2]);
    // 안 바뀌었다. 보내면 서버가 같은 값을 다시 쓰는데, 다른 기기에서 방금
    // 바꾼 값이 있으면 그것을 덮는다.
    if (birthday == body.birthday) return;

    // ⚠️ **휠이 막아주던 값이 아니다.** 상한은 `AgeRule`이 정하지만 윤년·일수
    // 조합으로 경계를 넘을 수 있다. 서버도 400으로 막는데 그 메시지는 화면에
    // 닿지 않아, 여기서 말해 준다.
    if (!AgeRule.isAllowed(birthday, now: DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.profileBirthTooYoung)),
      );
      return;
    }

    await _saveBody(birthday: birthday);
  }

  /// 키·몸무게를 고른다. **한 시트가 두 값을 함께 돌려준다.**
  Future<void> _pickBody() async {
    final body = ref.read(bodyProfileProvider);

    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profileBodyLabel,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitHeight,
          values: [for (var h = 130; h <= 210; h++) h],
          initial: body.heightCm ?? 172,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitWeight,
          values: [for (var w = 30; w <= 140; w++) w],
          initial: body.weightKg ?? 63,
        ),
      ],
    );
    if (picked == null) return;

    // ⚠️ **바뀐 것만 보낸다.** 시트가 두 값을 함께 돌려주므로, 키만 고쳤는데
    // 몸무게까지 실으면 **다른 기기에서 방금 바꾼 몸무게를 덮는다.**
    await _saveBody(
      heightCm: picked[0] == body.heightCm ? null : picked[0],
      weightKg: picked[1] == body.weightKg ? null : picked[1],
    );
  }

  /// 신체 정보를 보낸다. **보낼 것이 없으면 아무것도 하지 않는다.**
  ///
  /// ⚠️ 실패를 삼키지 않는다. 설정에는 저장 버튼이 없어 **다시 누를 자리도
  /// 없으므로**, 조용히 실패하면 사용자는 바뀐 줄 알고 화면을 떠난다.
  Future<void> _saveBody({
    DateTime? birthday,
    int? heightCm,
    int? weightKg,
  }) async {
    if (birthday == null && heightCm == null && weightKg == null) return;

    final failure = await ref
        .read(profileSummaryControllerProvider.notifier)
        .saveProfile(
          birthday: birthday,
          heightCm: heightCm,
          weightKg: weightKg,
        );

    if (!mounted || failure == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == ProfileEditFailure.sessionExpired
              ? AppStrings.settingsSessionExpired
              : AppStrings.settingsUpdateFailed,
        ),
      ),
    );
  }

  /// 생년월일 한 줄. **아직 못 읽었으면 `null`** — `_ValueRow`가 자리를
  /// 비워 두고 높이를 유지한다.
  String? get _birthdayText {
    if (_bodyLoading) return null;
    final birthday = ref.watch(bodyProfileProvider).birthday;
    if (birthday == null) return AppStrings.profileEditUnknown;
    return '${birthday.year}.${birthday.month.toString().padLeft(2, '0')}'
        '.${birthday.day.toString().padLeft(2, '0')}';
  }

  /// `180cm · 85kg` 한 줄. **한쪽만 있으면 비운다** — 시트가 두 값을 함께
  /// 돌려주므로 반쪽만 있는 상태는 없다.
  String? get _bodyText {
    if (_bodyLoading) return null;
    final body = ref.watch(bodyProfileProvider);
    final height = body.heightCm;
    final weight = body.weightKg;
    if (height == null || weight == null) return AppStrings.profileEditUnknown;
    return '$height${AppStrings.profileUnitHeight}'
        ' · $weight${AppStrings.profileUnitWeight}';
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
        backgroundColor: context.appColorsV2.bgElevated,
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

  /// 이용약관. 가입 화면이 필수 동의로 받은 문서라 설정에서도 언제든 다시
  /// 볼 수 있어야 한다.
  void _openTerms() => unawaited(_openDocument(LegalLinks.terms));

  Future<void> _openDocument(String url) => openLegalDocument(context, url);

  // ── 탈퇴 ──────────────────────────────────────────────────

  Future<void> _withdraw() async {
    // 애플 계정이면 시트가 "애플 쪽 연결을 직접 끊으라"는 줄을 덧붙인다.
    // 아직 `/users/me`를 못 읽었으면 `null`이라 그 줄이 빠진다 — 없는 안내보다
    // 틀린 안내가 나쁘다.
    final loginType = ref.read(
      authControllerProvider.select(
        (state) => state is AuthSignedIn ? state.user?.loginType : null,
      ),
    );
    if (!await showWithdrawSheet(context, loginType: loginType) || !mounted) {
      return;
    }

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
    final colors = context.appColorsV2;
    final state = ref.watch(settingsControllerProvider);
    final settings = state.settings;
    // 계정 정보는 `/users/me`가 실어 온다 — 설정이 따로 조회하지 않는다.
    // 아직 못 읽었으면 `null`이고, 계정 섹션만 빈 채로 나머지가 그려진다.
    final account = ref.watch(
      authControllerProvider.select(
        (state) => state is AuthSignedIn ? state.user : null,
      ),
    );
    final failed = state.isEmpty && state.failure != null;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(AppStrings.settingsTitle, style: AppTypographyV2.heading06),
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
            if (_showPreferences) ...[
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
            ],

            // ⚠️ **편집 화면에서 옮겨 왔다**(2026-10-22 요청). 자주 고치는
            // 값이 아니고, 거기 있으면 홈과 닮은 위쪽이 긴 폼에 묻힌다.
            const _SectionLabel(AppStrings.profileBodySection),
            _Card(
              children: [
                _ValueRow(
                  label: AppStrings.profileBirthLabel,
                  value: _birthdayText,
                  // 서버 값을 모르는 동안은 잠긴다. 선택기 기본값이 저장돼
                  // 버리는 것을 막는 유일한 자리다.
                  onTap: _bodyEditable ? _pickBirthday : null,
                ),
                _ValueRow(
                  label: AppStrings.profileBodyLabel,
                  value: _bodyText,
                  onTap: _bodyEditable ? _pickBody : null,
                ),
              ],
            ),
            // 잠긴 이유를 적는다. 안 적으면 눌러도 아무 일이 없는 줄로 보인다.
            if (_bodyFailed)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.space2,
                  left: AppSpacing.space4,
                ),
                child: Text(
                  AppStrings.profileBodyLoadFailed,
                  style: AppTypographyV2.body15.copyWith(color: colors.error),
                ),
              ),

            const SizedBox(height: AppSpacing.space6),
            const _SectionLabel(AppStrings.settingsAccountSection),
            _Card(
              children: [
                _ValueRow(
                  label: AppStrings.settingsEmail,
                  value: _emailLabel(account?.email),
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
                _ActionRow(
                  label: AppStrings.settingsPrivacy,
                  onTap: () => _openDocument(LegalLinks.privacy),
                ),
                _ActionRow(
                  label: AppStrings.settingsAccountDeletion,
                  onTap: () => _openDocument(LegalLinks.accountDeletion),
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

  /// 이메일 칸에 그릴 것.
  ///
  /// ⚠️ **애플이 가린 주소는 그대로 띄우지 않는다.** 릴레이 주소는 애플이
  /// 앱마다 다르게 만들어 주는 값이라, 보이는 쪽에서는 처음 보는 주소가 자기
  /// 계정에 박혀 있는 것으로 읽힌다. 가린 것은 사용자가 고른 일이므로 **가렸다는
  /// 사실**을 알린다 — 값은 서버·DB에 그대로 있다([PrivateRelayEmail]).
  static String? _emailLabel(String? email) => switch (email) {
    null => null,
    _ when PrivateRelayEmail.hides(email) =>
      AppStrings.settingsEmailHiddenByApple,
    _ => email,
  };

  /// 서버가 모르는 제공자를 보내면 "확인 불가"다. 비밀번호 메뉴는 이때 숨는다.
  static String _loginLabel(LoginType? type) => switch (type) {
    LoginType.local => AppStrings.settingsLoginLocal,
    LoginType.kakao => AppStrings.settingsLoginKakao,
    LoginType.google => AppStrings.settingsLoginGoogle,
    LoginType.apple => AppStrings.settingsLoginApple,
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
      style: AppTypographyV2.body15.copyWith(
        color: context.appColorsV2.textSecondary,
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
    final colors = context.appColorsV2;

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
    final colors = context.appColorsV2;
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
                  style: AppTypographyV2.body07.copyWith(
                    color: enabled ? colors.textPrimary : colors.textDisabled,
                  ),
                ),
                if (text != null) ...[
                  const SizedBox(height: AppSpacing.space0),
                  Text(
                    text,
                    style: AppTypographyV2.body15.copyWith(
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
  const _ValueRow({required this.label, required this.value, this.onTap});

  final String label;

  /// 누르면 고르는 자리가 열린다. `null`이면 **읽기 전용 행**이고, 화살표도
  /// 그리지 않는다 — 그려 두면 눌러도 아무 일이 없는 줄로 보인다.
  final VoidCallback? onTap;

  /// `null`이면 아직 못 읽었다. 자리를 비워 두고 높이는 유지한다 —
  /// 값이 들어올 때 행이 튀어 오르면 누르려던 것을 놓친다.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final text = value;

    final row = Container(
      constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          Text(label, style: AppTypographyV2.body07),
          const SizedBox(width: AppSpacing.space4),
          // ⚠️ **`Spacer`를 두면 값이 쓸 수 있는 폭이 절반으로 깎인다.**
          //
          // `Spacer`는 `Expanded`(flex 1)이고 값도 `Flexible`(flex 1)이라,
          // 라벨을 뺀 남은 폭을 **둘이 반씩 나눠 가졌다.** 그래서 긴 이메일이
          // 오른쪽에 자리가 뻔히 비어 있는데도 `…`로 잘렸다. 값을
          // `Expanded`로 두고 오른쪽 정렬하면 남은 폭을 전부 쓴다.
          if (text != null)
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.end,
                // 한 줄에 안 들어가는 주소가 있다. 자르기 전에 **한 줄 더
                // 쓴다** — 뒤를 잘라내면 도메인이 사라져 무슨 주소인지도 모른다.
                //
                // 주소에는 띄어쓰기가 없어 **줄이 주소 가운데서 넘어간다.**
                // 보기 좋지는 않지만 전부 보이는 쪽을 골랐다.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else ...[
            // 자리표시자는 폭이 정해져 있다. 밀어서 오른쪽에 붙인다.
            const Spacer(),
            _Skeleton(color: colors.borderDefault),
          ],
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.space2),
            AppIcon(AppIcons.right, size: 18, color: colors.textTertiary),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: row),
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
    final colors = context.appColorsV2;
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
              Text(label, style: AppTypographyV2.body07.copyWith(color: color)),
              const Spacer(),
              AppIcon(AppIcons.right, size: 18, color: color),
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
    final colors = context.appColorsV2;
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
              PresetChipV2(
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
              style: AppTypographyV2.body15.copyWith(
                color: colors.textTertiary,
              ),
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
    final colors = context.appColorsV2;

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
            style: AppTypographyV2.body07.copyWith(color: colors.textSecondary),
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
