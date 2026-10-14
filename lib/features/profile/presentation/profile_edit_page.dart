import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/utils/age_rule.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/nickname_sheet.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 편집 (S22.1).
///
/// ## 저장이 둘로 갈린다
///
/// | 무엇 | 언제 저장되나 |
/// |---|---|
/// | 닉네임 | 시트에서 **즉시** (52번 — 중복확인·409) |
/// | 사진 · 소개글 · 생년월일 · 키 · 몸무게 | **저장 버튼 하나로** |
///
/// 닉네임만 즉시인 것은 **중복 검사가 붙어 누르는 자리에서 답이 나야**
/// 하기 때문이다. 시트에서 "이미 쓰는 이름"을 듣고 다른 것을 넣는 흐름이라,
/// 저장까지 미루면 그 답을 어디서 들을지가 없어진다.
///
/// ## ⚠️ 사진도 예전에는 즉시였다
///
/// 고르는 순간 3단계 업로드가 끝나 버려서, **저장 버튼은 꺼진 채인데 이미
/// 저장된 뒤**였다. 버튼이 꺼져 있으면 저장할 것이 없다는 뜻으로 읽히는데
/// 실제로는 반대였고, 그냥 나가도 반영돼 있어 되돌릴 방법이 없었다.
///
/// 이제 고른 것을 [_photo]로 들고 있다가 저장할 때 보낸다.
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

  /// 고르거나 지우기로 했지만 **아직 안 보낸** 사진. `null`이면 안 건드렸다.
  PendingPhoto? _photo;

  bool _saving = false;
  ProfileEditFailure? _failure;

  @override
  void initState() {
    super.initState();
    _initialIntroduction =
        ref.read(profileSummaryControllerProvider).summary?.introduction ?? '';
    _introduction = TextEditingController(text: _initialIntroduction);

    // 앱을 켜 둔 동안 기억해 둔 값이 있으면 그것으로 시작한다.
    final body = ref.read(bodyProfileProvider);
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
  /// 닉네임은 세지 않는다 — 시트에서 이미 저장돼 저장 버튼이 할 일이 없다.
  bool get _dirty => _photo != null || _dirtyProfile;

  /// `PATCH /users/me/profile` 이 다루는 값 중 하나라도 바뀌었나.
  ///
  /// **사진은 세지 않는다.** 사진은 제 갈 길(3단계 업로드)이 따로 있어서,
  /// 사진만 바꿨을 때 이 `PATCH` 까지 보내면 **전부 `null` 인 요청**이 된다.
  bool get _dirtyProfile {
    final body = ref.read(bodyProfileProvider);
    return _introduction.text.trim() != _initialIntroduction ||
        _birthday != body.birthday ||
        _heightCm != body.heightCm ||
        _weightKg != body.weightKg;
  }

  bool get _introductionTooLong => _introduction.text.trim().length > 100;

  /// 만 14세 미만인가. 서버도 `PATCH /users/me/profile`에서 400으로 막지만
  /// 그 메시지는 화면에 닿지 않아, 저장 버튼을 여기서 잠근다.
  bool get _birthdayTooYoung {
    final birthday = _birthday;
    if (birthday == null) return false;
    return !AgeRule.isAllowed(birthday, now: DateTime.now());
  }

  bool get _canSave =>
      _dirty && !_saving && !_introductionTooLong && !_birthdayTooYoung;

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

    // ⚠️ **사진을 먼저 보내고, 실패하면 거기서 멈춘다.**
    //
    // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다. 멈춰서 화면에
    // 남겨 두면 다시 누르는 것으로 둘 다 간다.
    if (!await _savePhoto()) return;

    // 사진만 바꿨다. 보낼 프로필 값이 없다.
    if (!_dirtyProfile) {
      if (mounted) context.pop();
      return;
    }

    final body = ref.read(bodyProfileProvider);
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

  /// 들고 있던 사진 변경을 보낸다. **보낼 것이 없으면 그냥 참이다.**
  ///
  /// 실패하면 거짓을 돌려주고, 그 전에 스낵바로 이유를 알린다. 사진 실패는
  /// 화면 아래 문구([_failure])와 섞지 않는다 — 그쪽은 `PATCH` 의 이유라
  /// 같은 자리에 쓰면 어느 쪽이 실패한 것인지 알 수 없다.
  Future<bool> _savePhoto() async {
    final photo = _photo;
    if (photo == null) return true;

    final failure = await ref
        .read(profileImageControllerProvider.notifier)
        .apply(photo);

    if (!mounted) return false;
    if (failure == null) {
      // 보냈다. 다시 누를 때 또 올리지 않는다.
      //
      // 새 주소를 다시 받는 것은 여기서 하지 않는다 — **편집 화면을 연
      // `ProfileHeader` 가 돌아온 자리에서 이미 부른다.**
      setState(() => _photo = null);
      return true;
    }

    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_photoMessageOf(failure))));
    return false;
  }

  /// 저장하지 않고 나가려 한다. **바꾼 게 없으면 묻지 않는다.**
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColorsV2.bgElevated,
        title: Text(
          AppStrings.profileEditDiscardTitle,
          style: AppTypographyV2.heading06.copyWith(
            color: context.appColorsV2.textPrimary,
          ),
        ),
        content: Text(
          AppStrings.profileEditDiscardBody,
          style: AppTypographyV2.body07.copyWith(
            color: context.appColorsV2.textSecondary,
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
              style: TextStyle(color: context.appColorsV2.error),
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
    final colors = context.appColorsV2;
    final summary = ref.watch(profileSummaryControllerProvider).summary;

    return PopScope(
      // 바꾼 게 있으면 먼저 묻는다. 뒤로 밀기(제스처)도 여기로 들어온다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        // ⚠️ **앱 테마가 아직 옛 세대라 바탕을 직접 깐다.** 안 깔면 토큰은
        // 전부 새것인데 바탕만 `#0b0e14`로 남는다 — 채널당 차이가 10 안쪽이라
        // 눈으로는 잘 안 보인다(`v2_screen_background_test`).
        backgroundColor: colors.bgBase,
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
                      // 고른 것은 화면에만 남는다. 보내는 것은 저장 버튼이다.
                      Center(
                        child: Column(
                          children: [
                            ProfileAvatar(
                              url: summary?.profileImageUrl,
                              editable: true,
                              pending: _photo,
                              onPending: (photo) =>
                                  setState(() => _photo = photo),
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text(
                              AppStrings.profileEditPhoto,
                              style: AppTypographyV2.body15.copyWith(
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
                      AppInputV2(
                        // ⚠️ **테스트가 이 입력을 찾는 유일한 손잡이다.**
                        // 부품이 `TextField` 인지 무엇인지에 기대면 디자인을
                        // 바꿀 때 테스트가 통째로 깨진다. 디자인을 바꿔도
                        // **이 키는 이어받는다.**
                        key: const ValueKey('profile-introduction'),
                        controller: _introduction,
                        hint: AppStrings.profileIntroductionHint,
                        helper: _introductionTooLong
                            ? AppStrings.profileIntroductionTooLong
                            : null,
                        tone: _introductionTooLong
                            ? AppInputToneV2.error
                            : AppInputToneV2.neutral,
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
                      // 저장 버튼만 잠그면 왜 안 눌리는지 알 수 없다.
                      if (_birthdayTooYoung)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.space2,
                          ),
                          child: Text(
                            AppStrings.profileBirthTooYoung,
                            style: AppTypographyV2.body15.copyWith(
                              color: colors.error,
                            ),
                          ),
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
                          style: AppTypographyV2.body15.copyWith(
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

  /// 사진 실패 이유를 화면 문구로 옮긴다.
  ///
  /// **앞의 셋만 갈라 말한다.** 나머지는 사용자가 할 수 있는 일이
  /// "다시 해보기" 하나라서, 어디서 막혔는지 말해도 쓸 데가 없다.
  static String _photoMessageOf(ProfileImageFailure failure) =>
      switch (failure) {
        ProfileImageFailure.unsupportedFormat =>
          AppStrings.profilePhotoUnsupported,
        ProfileImageFailure.tooLarge => AppStrings.profilePhotoTooLarge,
        ProfileImageFailure.sessionExpired => AppStrings.profileSubmitExpired,
        _ => AppStrings.profilePhotoFailed,
      };

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
    final colors = context.appColorsV2;

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
            icon: AppIcon(
              AppIcons.left,
              size: AppSpacing.space6,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              AppStrings.profileEditTitle,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
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
                      style: AppTypographyV2.body07.copyWith(
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
      style: AppTypographyV2.body15.copyWith(
        color: context.appColorsV2.textSecondary,
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
    final colors = context.appColorsV2;
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
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.space4),
            ],
            Expanded(
              child: Text(
                text ?? AppStrings.profileEditUnknown,
                textAlign: label == null ? TextAlign.start : TextAlign.end,
                style: AppTypographyV2.body07.copyWith(
                  // 값이 없다는 것과 있는 것을 **무게로** 가른다.
                  color: text == null
                      ? colors.textTertiary
                      : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppIcon(
              AppIcons.right,
              size: AppSpacing.space5,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
