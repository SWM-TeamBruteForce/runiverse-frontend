import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/presentation/nickname_sheet.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 편집 (S22.1).
///
/// ## 저장이 셋으로 갈린다
///
/// | 무엇 | 언제 저장되나 |
/// |---|---|
/// | 사진 | 고르는 **즉시** (47~50번) |
/// | 닉네임 | 시트에서 **즉시** (52번 — 중복확인·409) |
/// | 소개글·생년월일·키·몸무게 | **저장 버튼 하나로** (51번) |
///
/// 서버가 그렇게 갈라 놨다. 사진은 3단계 업로드라 저장 버튼에 묶을 수 없고,
/// 닉네임은 중복 검사가 붙어 누르는 자리에서 답이 나야 한다.
///
/// 화면에서는 **누르면 시트가 열리는 것은 거기서 끝나고, 화면에 남는 것만
/// 저장을 기다린다.** 이 구분이 보이지 않으면 사진을 바꾸고 저장을 안 눌러
/// 사라졌다고 여기게 된다.
///
/// ## 성별과 평균 페이스는 없다
///
/// 성별은 기능정의서(`SETTING-PERSONAL-001`)가 **설정 UI 미노출**로 정했고,
/// 평균 페이스는 서버가 러닝 기록으로 갱신한다. 둘 다 요청에 싣지 않는다.
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  late final TextEditingController _introduction;

  /// 화면에 들어올 때의 소개글. **바뀐 게 있는지**를 이것과 비교해 판단한다.
  late final String _initialIntroduction;

  DateTime? _birthday;
  int? _heightCm;
  int? _weightKg;

  bool _saving = false;
  ProfileEditFailure? _failure;

  @override
  void initState() {
    super.initState();
    _initialIntroduction =
        ref.read(profileSummaryControllerProvider).summary?.introduction ?? '';
    _introduction = TextEditingController(text: _initialIntroduction);

    // 앱을 켜 둔 동안 기억해 둔 값이 있으면 그것으로 시작한다.
    final body = ref.read(profileBodyProvider);
    _birthday = body.birthday;
    _heightCm = body.heightCm;
    _weightKg = body.weightKg;
  }

  @override
  void dispose() {
    _introduction.dispose();
    super.dispose();
  }

  // ── 판정 ──────────────────────────────────────────────────

  /// 저장 버튼이 다루는 값 중 **하나라도 바뀌었나.**
  ///
  /// 사진과 닉네임은 세지 않는다 — 이미 저장된 것이라 저장 버튼이 할 일이 없다.
  bool get _dirty {
    final body = ref.read(profileBodyProvider);
    return _introduction.text.trim() != _initialIntroduction ||
        _birthday != body.birthday ||
        _heightCm != body.heightCm ||
        _weightKg != body.weightKg;
  }

  bool get _introductionTooLong => _introduction.text.trim().length > 100;

  bool get _canSave => _dirty && !_saving && !_introductionTooLong;

  // ── 고르기 ────────────────────────────────────────────────

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final current = _birthday ?? DateTime(now.year - 27, 4, 12);

    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profileBirthLabel,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitYear,
          values: [for (var y = now.year - 80; y <= now.year - 10; y++) y],
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

    setState(() => _birthday = DateTime(picked[0], picked[1], picked[2]));
  }

  Future<void> _pickBody() async {
    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profileBodyLabel,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitHeight,
          values: [for (var h = 130; h <= 210; h++) h],
          initial: _heightCm ?? 172,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitWeight,
          values: [for (var w = 30; w <= 140; w++) w],
          initial: _weightKg ?? 63,
        ),
      ],
    );
    if (picked == null) return;

    setState(() {
      _heightCm = picked[0];
      _weightKg = picked[1];
    });
  }

  // ── 저장·이탈 ─────────────────────────────────────────────

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _saving = true;
      _failure = null;
    });

    final body = ref.read(profileBodyProvider);
    final introduction = _introduction.text.trim();

    final failure = await ref
        .read(profileSummaryControllerProvider.notifier)
        .saveProfile(
          // ⚠️ **바뀐 것만 보낸다.** 안 바뀐 값을 실어 보내면 서버가 같은 값을
          // 다시 쓰는데, 다른 기기에서 방금 바꾼 값이 있으면 그것을 덮는다.
          introduction: introduction == _initialIntroduction
              ? null
              : introduction,
          birthday: _birthday == body.birthday ? null : _birthday,
          heightCm: _heightCm == body.heightCm ? null : _heightCm,
          weightKg: _weightKg == body.weightKg ? null : _weightKg,
        );

    if (!mounted) return;
    if (failure == null) {
      context.pop();
      return;
    }

    setState(() {
      _saving = false;
      _failure = failure;
    });
  }

  /// 저장하지 않고 나가려 한다. **바꾼 게 없으면 묻지 않는다.**
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.bgElevated,
        title: Text(
          AppStrings.profileEditDiscardTitle,
          style: AppTypography.h3.copyWith(
            color: context.appColors.textPrimary,
          ),
        ),
        content: Text(
          AppStrings.profileEditDiscardBody,
          style: AppTypography.body.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.profileEditDiscardStay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              AppStrings.profileEditDiscardLeave,
              style: TextStyle(color: context.appColors.error),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ── 화면 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final summary = ref.watch(profileSummaryControllerProvider).summary;

    return PopScope(
      // 바꾼 게 있으면 먼저 묻는다. 뒤로 밀기(제스처)도 여기로 들어온다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                onBack: () async {
                  if (await _confirmLeave() && context.mounted) context.pop();
                },
                onSave: _canSave ? _save : null,
                saving: _saving,
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space5,
                    AppSpacing.space4,
                    AppSpacing.space5,
                    AppSpacing.space8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 사진은 **저장 버튼과 무관하다.** 고르는 순간 올라간다.
                      Center(
                        child: Column(
                          children: [
                            ProfileAvatar(
                              url: summary?.profileImageUrl,
                              editable: true,
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text(
                              AppStrings.profileEditPhoto,
                              style: AppTypography.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space7),

                      // 닉네임도 시트에서 즉시 저장된다.
                      _Label(AppStrings.profileNicknameLabel),
                      _ValueRow(
                        value: summary?.nickname,
                        onTap: () => showNicknameSheet(
                          context,
                          current: summary?.nickname,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space6),

                      _Label(AppStrings.profileIntroductionLabel),
                      const SizedBox(height: AppSpacing.space2),
                      AppInput(
                        controller: _introduction,
                        hint: AppStrings.profileIntroductionHint,
                        helper: _introductionTooLong
                            ? AppStrings.profileIntroductionTooLong
                            : null,
                        tone: _introductionTooLong
                            ? AppInputTone.error
                            : AppInputTone.neutral,
                        counter: '${_introduction.text.trim().length}/100',
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(100),
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.space7),

                      _Label(AppStrings.profileBodySection),
                      _ValueRow(
                        label: AppStrings.profileBirthLabel,
                        value: _birthday == null ? null : _dateText(_birthday!),
                        onTap: _pickBirthday,
                      ),
                      _ValueRow(
                        label: AppStrings.profileBodyLabel,
                        value: _heightCm == null || _weightKg == null
                            ? null
                            : '$_heightCm${AppStrings.profileUnitHeight}'
                                  ' · $_weightKg${AppStrings.profileUnitWeight}',
                        onTap: _pickBody,
                      ),

                      if (_failure != null) ...[
                        const SizedBox(height: AppSpacing.space4),
                        Text(
                          _messageOf(_failure!),
                          style: AppTypography.caption.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateText(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}'
      '.${date.day.toString().padLeft(2, '0')}';

  static String _messageOf(ProfileEditFailure failure) => switch (failure) {
    ProfileEditFailure.notOnboarded => AppStrings.profileNicknameNotOnboarded,
    ProfileEditFailure.sessionExpired => AppStrings.profileSubmitExpired,
    _ => AppStrings.profileSubmitFailed,
  };
}

/// `‹  프로필 편집          저장`
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onSave,
    required this.saving,
  });

  final VoidCallback onBack;

  /// `null`이면 잠긴다 — **바꾼 게 없을 때**가 그렇다.
  final VoidCallback? onSave;

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      height: AppSizes.touchDefault + AppSpacing.space2,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: AppStrings.authBack,
            constraints: const BoxConstraints(
              minWidth: AppSizes.touchDefault,
              minHeight: AppSizes.touchDefault,
            ),
            icon: Icon(
              LucideIcons.arrowLeft,
              size: AppSpacing.space6,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              AppStrings.profileEditTitle,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
          // 뒤로 아이콘과 **같은 폭**을 잡아 제목이 가운데에 선다.
          SizedBox(
            width: AppSizes.touchDefault + AppSpacing.space4,
            child: saving
                ? const Center(
                    child: SizedBox(
                      width: AppSpacing.space4,
                      height: AppSpacing.space4,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: onSave,
                    child: Text(
                      AppStrings.profileEditSave,
                      style: AppTypography.body.copyWith(
                        color: onSave == null
                            ? colors.textDisabled
                            : colors.primary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space1),
    child: Text(
      text,
      style: AppTypography.caption.copyWith(
        color: context.appColors.textSecondary,
      ),
    ),
  );
}

/// 눌러서 시트를 여는 한 줄. **값이 없으면 `—`를 그린다.**
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.value, required this.onTap, this.label});

  /// 줄 왼쪽에 붙는 이름. 없으면 값만 그린다(닉네임처럼 위에 라벨이 있을 때).
  final String? label;

  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = value;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.md,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
        child: Row(
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.space4),
            ],
            Expanded(
              child: Text(
                text ?? AppStrings.profileEditUnknown,
                textAlign: label == null ? TextAlign.start : TextAlign.end,
                style: AppTypography.body.copyWith(
                  // 값이 없다는 것과 있는 것을 **무게로** 가른다.
                  color: text == null
                      ? colors.textTertiary
                      : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            Icon(
              LucideIcons.chevronRight,
              size: AppSpacing.space5,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
