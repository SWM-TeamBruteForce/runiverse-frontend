import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/utils/age_rule.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/core/widgets/v2/field_action.dart';
import 'package:runiverse/core/widgets/v2/step_progress.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/domain/body_rule.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/pace_level.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_provider.dart';

/// 프로필 등록 (S04). 시안 `158:2758`.
///
/// ## ⚠️ 한 번에 하나씩 묻던 화면이었다 (2026-09-30에 뒤집었다)
///
/// 오래 **답하면 다음 질문이 아래에 붙고 답한 것은 위에 쌓이는** 화면이었다.
/// 그렇게 만든 이유가 있었고, 그대로 옮겨 적는다.
///
/// > 와이어프레임은 여섯 항목을 한 화면에 늘어놓는다. 답을 시작하기 전에
/// > 분량부터 가늠하게 되는 배치라, 온보딩 3분 안에서는 이탈 신호다.
/// >
/// > 생년월일·키·몸무게는 휠 시트로 고른다. 숫자를 치게 하면 2월 31일이나
/// > 키 700cm처럼 만들 수 없어야 할 값이 만들어지고, 키보드가 화면 절반을 가린다.
///
/// 시안을 따르기로 하면서 그 판단을 뒤집었다. **되돌린 것이 아니라 새로 정한
/// 것이다** — 다음 사람이 "왜 예전 방식으로 돌아갔나"를 다시 묻지 않도록 남긴다.
///
/// 걱정하던 두 가지는 이렇게 막는다.
///
/// - **못 만들 값** — [BodyRule]이 막는다. 휠이 하던 일을 규칙이 대신한다.
///   ⚠️ 휠도 2월 31일은 못 막았다(일 칸이 달과 무관하게 1~31이었다). 이제 막힌다
/// - **키보드가 가리는 것** — 폼이 스크롤되고 `Scaffold`가 키보드만큼 밀어 올린다
///
/// ## 타이핑은 넷, 고르는 것은 둘
///
/// 닉네임·생년월일·키·몸무게는 친다. 성별은 토글, 페이스는 시트다 —
/// 페이스는 `분`과 `초` 두 칸이라 치게 하면 오히려 번거롭다.
///
/// ## 페이스는 비워도 된다
///
/// `null`은 **미측정**이다. 기본값을 몰래 채우면 그 숫자가 그대로 시그니처
/// 컬러가 되고, 사용자는 자기가 고르지 않은 색을 갖게 된다.
///
/// ## 상태를 provider로 올리지 않는다
///
/// 여기서 모아 한 번 보내고 화면을 떠나면 버리는 값이다. provider에서 가져오는
/// 것은 값이 아니라 **보낼 곳**(`onboardingRepositoryProvider`)뿐이다.
class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage>
    with SingleTickerProviderStateMixin {
  final _nickname = TextEditingController();
  final _birth = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();

  /// 닉네임 칸. 서버가 "이미 있다"고 하면 여기로 데려온다.
  final _nicknameFocus = FocusNode();

  Gender? _gender;

  /// 1km당 초. **`null`은 '미측정'이다** — 비워 두고 넘어갈 수 있다.
  int? _paceSeconds;

  /// 전송 중. 버튼이 두 번 눌리는 것을 막는다.
  bool _submitting = false;

  /// 전송이 실패한 이유. 성공하면 화면을 떠나므로 `null`로 되돌릴 일이 없다.
  OnboardingFailure? _submitFailure;

  /// 닉네임을 서버에 묻는 중. 확인 버튼이 두 번 눌리는 것을 막는다.
  bool _checkingNickname = false;

  /// 물어보지 못했다.
  ///
  /// ⚠️ **"이미 있다"와 다르다.** 하나로 묶으면 네트워크가 잠깐 끊긴 것 때문에
  /// 멀쩡한 이름이 거절되고, 사용자는 쓸 수 있는 이름을 버리게 된다.
  bool _nicknameCheckFailed = false;

  /// 마지막으로 답을 받은 이름과 그 답.
  ///
  /// **어떤 이름의 답인지 함께 들고 있어야 한다.** `bool` 하나만 두면 이름을
  /// 고친 뒤에도 지난 답이 남아, 겹치는 이름인데 통과하거나 그 반대가 된다.
  String? _checkedNickname;
  bool? _checkedAvailable;

  /// 입력이 멎기를 기다리는 타이머.
  ///
  /// 글자마다 물으면 이름 길이만큼 요청이 나간다. 손을 멈춘 뒤에만 묻는다.
  Timer? _checkTimer;
  static const _checkDebounce = Duration(milliseconds: 500);

  /// 상한에서 막힌 직후 잠깐 켜진다. 켜져 있는 동안 helper가 경고로 덮인다.
  bool _limitHit = false;
  Timer? _limitTimer;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 좌우로 한 번 튕긴다. 막혔다는 사실을 글자 말고 몸짓으로도 알린다.
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -3), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -3, end: 3), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 3, end: 0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shake, curve: AppMotion.easeStandard));

  @override
  void dispose() {
    _limitTimer?.cancel();
    _checkTimer?.cancel();
    _shake.dispose();
    _nickname.dispose();
    _birth.dispose();
    _height.dispose();
    _weight.dispose();
    _nicknameFocus.dispose();
    super.dispose();
  }

  // ── 닉네임 ────────────────────────────────────────────────

  /// 사람이 보는 글자 수. 자소 단위로 센다 —
  /// 입력을 자르는 [LengthLimitingTextInputFormatter]와 같은 기준이다.
  int get _nicknameLength => _nickname.text.trim().characters.length;

  NicknameStatus get _nicknameStatus =>
      NicknameRule.of(_nicknameLength, _nickname.text.trim());

  /// 16자를 넘겨 치려 한 순간. 잘라내기만 하면 고장난 것으로 읽힌다.
  void _onNicknameRejected() {
    _limitTimer?.cancel();
    _shake.forward(from: 0);
    setState(() => _limitHit = true);
    _limitTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _limitHit = false);
    });
  }

  /// 이름이 바뀌었다. **서버가 한 말은 전부 낡은 말이 된다.**
  void _onNicknameChanged() {
    _checkTimer?.cancel();
    setState(() {
      _checkedNickname = null;
      _checkedAvailable = null;
      _nicknameCheckFailed = false;
      if (_submitFailure == OnboardingFailure.nicknameTaken) {
        _submitFailure = null;
      }
    });

    // ⚠️ 형식이 틀리면 묻지 않는다. 서버도 400으로 거절하는데, 그 400은
    // **앱 규칙이 서버와 어긋났다는 신호**로만 써야 한다.
    if (!_nicknameStatus.isValid) return;

    _checkTimer = Timer(_checkDebounce, () {
      if (mounted) _checkNickname();
    });
  }

  /// 서버에 겹치는지 묻고 **결과만 남긴다.**
  Future<void> _checkNickname() async {
    if (!_nicknameStatus.isValid) return;

    // ⚠️ 앞 요청이 아직 안 끝났다. 여기서 그냥 돌아가면 **이 이름은 영영
    // 안 물어본다** — 타이머는 이미 소진됐고 다시 걸어주는 사람이 없다.
    if (_checkingNickname) {
      _checkTimer?.cancel();
      _checkTimer = Timer(_checkDebounce, () {
        if (mounted) _checkNickname();
      });
      return;
    }

    final nickname = _nickname.text.trim();
    setState(() {
      _checkingNickname = true;
      _nicknameCheckFailed = false;
      _submitFailure = null;
    });

    bool? available;
    try {
      available = await ref
          .read(onboardingRepositoryProvider)
          .isNicknameAvailable(nickname);
    } on OnboardingException {
      // 사유를 가르지 않는다. 사용자가 할 일은 다시 눌러보는 것 하나다.
    }

    if (!mounted) return;
    // 기다리는 동안 이름을 고쳤다면 이 답은 **다른 이름의 답**이다. 버린다.
    if (_nickname.text.trim() != nickname) {
      setState(() => _checkingNickname = false);
      return;
    }

    setState(() {
      _checkingNickname = false;
      _checkedNickname = nickname;
      _checkedAvailable = available;
      _nicknameCheckFailed = available == null;
      if (available == false) _submitFailure = OnboardingFailure.nicknameTaken;
    });
  }

  /// 이 이름에 대한 **답**을 이미 들고 있는가.
  ///
  /// ⚠️ 물어봤다는 것만으로는 모자란다. 실패한 확인도 `_checkedNickname`을
  /// 남기는데 그것을 답으로 치면 '확인'이 재시도 분기를 건너뛰어,
  /// **눌리는데 아무 일도 일어나지 않는 버튼**이 된다.
  bool get _hasFreshAnswer =>
      _checkedAvailable != null && _checkedNickname == _nickname.text.trim();

  /// '중복확인'을 눌렀다. 디바운스를 기다리는 중이었다면 지금 묻는다.
  Future<void> _confirmNickname() async {
    if (!_nicknameStatus.isValid || _checkingNickname) return;
    _checkTimer?.cancel();
    await _checkNickname();
  }

  // ── 값 읽기 ───────────────────────────────────────────────

  DateTime? get _birthDate => BodyRule.parseBirth(_birth.text);
  int? get _heightCm => BodyRule.parseNumber(_height.text);
  int? get _weightKg => BodyRule.parseNumber(_weight.text);

  /// 생년월일 칸의 오류 문구. **비어 있으면 아무 말도 하지 않는다** —
  /// 아직 안 친 것뿐이다.
  String? get _birthError {
    if (_birth.text.isEmpty) return null;

    final date = _birthDate;
    if (date == null) return AppStrings.profileBirthMalformed;

    final now = DateTime.now();
    // ⚠️ 미래를 먼저 본다. 나이 판정에도 걸리지만 그때 나오는 말은
    // "너무 어려요"라, 무엇이 잘못됐는지 알 수 없다.
    if (BodyRule.isFutureBirth(date, now: now)) {
      return AppStrings.profileBirthFuture;
    }
    if (BodyRule.isTooOldBirth(date, now: now)) {
      return AppStrings.profileBirthTooOld;
    }
    if (!AgeRule.isAllowed(date, now: now)) {
      return AppStrings.profileBirthTooYoung;
    }
    return null;
  }

  String? get _heightError {
    if (_height.text.isEmpty) return null;
    final cm = _heightCm;
    if (cm == null || !BodyRule.isAllowedHeight(cm)) {
      return AppStrings.profileHeightOutOfRange(
        BodyRule.minHeight,
        BodyRule.maxHeight,
      );
    }
    return null;
  }

  String? get _weightError {
    if (_weight.text.isEmpty) return null;
    final kg = _weightKg;
    if (kg == null || !BodyRule.isAllowedWeight(kg)) {
      return AppStrings.profileWeightOutOfRange(
        BodyRule.minWeight,
        BodyRule.maxWeight,
      );
    }
    return null;
  }

  /// 다 채웠는가. **페이스는 보지 않는다** — 미측정으로 넘어갈 수 있다.
  bool get _done =>
      _nicknameStatus.isValid &&
      _hasFreshAnswer &&
      _checkedAvailable == true &&
      _birth.text.isNotEmpty &&
      _birthError == null &&
      _gender != null &&
      _height.text.isNotEmpty &&
      _heightError == null &&
      _weight.text.isNotEmpty &&
      _weightError == null;

  // ── 페이스 ────────────────────────────────────────────────

  Future<void> _pickPace() async {
    final current = _paceSeconds ?? PaceRule.toSeconds(6, 0);

    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profilePaceSheetTitle,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitMinute,
          values: [
            for (var m = PaceRule.minMinutes; m <= PaceRule.maxMinutes; m++) m,
          ],
          initial: current ~/ 60,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitSecond,
          values: [for (var s = 0; s < 60; s += PaceRule.secondStep) s],
          initial: (current % 60) ~/ PaceRule.secondStep * PaceRule.secondStep,
        ),
      ],
    );
    if (picked == null) return;

    setState(() => _paceSeconds = PaceRule.toSeconds(picked[0], picked[1]));
  }

  /// `5'42" /km` 형태. 미측정이면 `null`.
  String? get _paceLabel {
    final total = _paceSeconds;
    if (total == null) return null;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return "${total ~/ 60}'$seconds\" ${AppStrings.profilePacePerKm}";
  }

  // ── 보내기 ────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_submitting || !_done) return;
    setState(() {
      _submitting = true;
      _submitFailure = null;
    });

    final profile = OnboardingProfile(
      nickname: _nickname.text.trim(),
      gender: _gender!,
      birthday: _birthDate!,
      paceSecondsPerKm: _paceSeconds,
      heightCm: _heightCm!,
      weightKg: _weightKg!,
    );

    OnboardingFailure? failure;
    try {
      await ref.read(onboardingRepositoryProvider).submit(profile);
      // 저장소와 상태를 함께 켠다. 이게 없으면 앱을 껐다 켤 때 다시 여기로 온다.
      await ref.read(authControllerProvider.notifier).markOnboarded();

      // ⚠️ **여기가 신체 정보를 기기에 남기는 유일한 시작점이다.** 서버에
      // 이것을 돌려주는 조회 API가 없어(`BodyProfileStore` 참조), 지금 남기지
      // 않으면 앱을 껐다 켰을 때 칼로리를 낼 수 없다.
      await ref
          .read(bodyProfileProvider.notifier)
          .remember(
            birthday: profile.birthday,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
          );
    } on OnboardingException catch (error) {
      failure = error.failure;
    }

    // await 사이에 화면이 사라졌을 수 있다.
    if (!mounted) return;

    if (failure != null) {
      // 입력은 그대로 둔다. 여섯 개를 다시 채우게 하지 않는다.
      setState(() {
        _submitting = false;
        _submitFailure = failure;
      });
      // 닉네임 중복만 **고칠 자리가 정해져 있다.** 한 화면 폼이라 스크롤로
      // 가려져 있을 수 있어, 그 칸으로 데려온다.
      if (failure == OnboardingFailure.nicknameTaken) {
        _nicknameFocus.requestFocus();
      }
      return;
    }

    // ⚠️ 원래는 시그니처 컬러 리빌(S04.5)로 간다. 그 화면이 아직 없어 여기서 끝난다.
    //
    // **왔던 자리로 돌려보낸다.** 프로필 탭의 유도 시트에서 시작했으면 그 탭으로
    // 돌아가 방금 채운 이름이 그 자리에 뜬다.
    //
    // 인증 직후에는 `go`로 열려 스택에 이 화면뿐이다 — 그때만 홈이다.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  // ── 그리기 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Scaffold(
      // 앱 테마는 아직 옛 세대라 scaffold 배경이 푸른 회색이다.
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ⚠️ 시안에는 뒤로가기와 건너뛰기가 있다. 둘 다 넣지 않는다 —
            // 프로필은 채워야 앱을 쓸 수 있고(라우터가 여기로 돌려보낸다),
            // 인증 직후에는 `go`로 열려 뒤로 갈 곳도 없다.
            //
            // 대신 그 줄만큼 비운다. 약관·회원가입은 뒤로가기 줄 아래에
            // 진행 바가 오는데, 여기만 위로 붙으면 넘길 때 바가 튄다.
            const SizedBox(height: AppSizes.touchDefault + AppSpacing.space6),

            // 가입 흐름의 마지막 걸음. 약관 → 회원가입 → **프로필 등록**.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space6,
              ),
              child: const StepProgressV2(step: 3, total: 3),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space6,
                  AppSpacing.space7,
                  AppSpacing.space6,
                  AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.profileSetupTitle,
                      style: AppTypographyV2.heading04.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space7),

                    _nicknameField(),
                    const SizedBox(height: AppSpacing.space2),

                    AppInputV2(
                      controller: _birth,
                      label: AppStrings.profileBirthLabel,
                      hint: AppStrings.profileBirthHint,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(BodyRule.birthDigits),
                      ],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      tone: _birthError == null
                          ? AppInputToneV2.neutral
                          : AppInputToneV2.error,
                      helper: _birthError,
                    ),
                    const SizedBox(height: AppSpacing.space2),

                    _GenderToggle(
                      value: _gender,
                      onChanged: (gender) => setState(() => _gender = gender),
                    ),
                    const SizedBox(height: AppSpacing.space2),

                    // 키와 몸무게는 나란히. 시안 `158:2792` · `158:2797`.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppInputV2(
                            controller: _height,
                            label: AppStrings.profileHeightLabel,
                            hint: AppStrings.profileHeightHint,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            tone: _heightError == null
                                ? AppInputToneV2.neutral
                                : AppInputToneV2.error,
                            helper: _heightError,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space2),
                        Expanded(
                          child: AppInputV2(
                            controller: _weight,
                            label: AppStrings.profileWeightLabel,
                            hint: AppStrings.profileWeightHint,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            tone: _weightError == null
                                ? AppInputToneV2.neutral
                                : AppInputToneV2.error,
                            helper: _weightError,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space2),

                    _PaceField(value: _paceLabel, onTap: _pickPace),

                    if (_submitFailure != null &&
                        _submitFailure != OnboardingFailure.nicknameTaken) ...[
                      const SizedBox(height: AppSpacing.space4),
                      _FailureNotice(failure: _submitFailure!),
                    ],
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                0,
                AppSpacing.space6,
                AppSpacing.space6,
              ),
              child: SizedBox(
                height: AppSizes.touchRunning,
                child: _submitting
                    ? Center(
                        child: SizedBox.square(
                          dimension: AppSpacing.space6,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                      )
                    : AppButtonV2(
                        label: AppStrings.profileNext,
                        onPressed: _done ? _finish : null,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nicknameField() {
    final status = _nicknameStatus;

    // 경고가 떠 있는 동안은 일반 안내가 덮어쓰지 않는다.
    // 아래 셋은 전부 형식을 통과한 뒤의 이야기라, switch가 '쓸 수 있는
    // 이름이에요'라고 답하는 것을 덮어야 한다.
    final (String helper, AppInputToneV2 tone) = _limitHit
        ? (AppStrings.profileNicknameTooLong, AppInputToneV2.error)
        : _checkingNickname
        ? (AppStrings.profileNicknameChecking, AppInputToneV2.neutral)
        // ⚠️ 물어보지 못한 것과 이미 있는 것을 가른다.
        : _nicknameCheckFailed
        ? (AppStrings.profileNicknameCheckFailed, AppInputToneV2.error)
        : _submitFailure == OnboardingFailure.nicknameTaken
        ? (AppStrings.profileNicknameTaken, AppInputToneV2.error)
        // ⚠️ 형식을 통과했어도 **서버가 답하기 전까지는** 쓸 수 있다고 말하지
        // 않는다. 곧 "이미 있다"로 뒤집힐 수 있는 말이다.
        : (status.isValid && !_hasFreshAnswer)
        ? (AppStrings.profileNicknameCheckPending, AppInputToneV2.neutral)
        : switch (status) {
            NicknameStatus.empty => (
              AppStrings.profileNicknameGuide,
              AppInputToneV2.neutral,
            ),
            NicknameStatus.tooShort => (
              AppStrings.profileNicknameTooShort,
              AppInputToneV2.error,
            ),
            NicknameStatus.tooLong => (
              AppStrings.profileNicknameTooLong,
              AppInputToneV2.error,
            ),
            NicknameStatus.invalidChars => (
              AppStrings.profileNicknameInvalidChars,
              AppInputToneV2.error,
            ),
            NicknameStatus.valid => (
              AppStrings.profileNicknameOk,
              AppInputToneV2.success,
            ),
          };

    return AnimatedBuilder(
      animation: _shakeOffset,
      builder: (context, child) => Transform.translate(
        offset: Offset(_shakeOffset.value, 0),
        child: child,
      ),
      child: AppInputV2(
        controller: _nickname,
        focusNode: _nicknameFocus,
        label: AppStrings.profileNicknameLabel,
        hint: AppStrings.profileNicknameHint,
        helper: helper,
        counter: '$_nicknameLength/${NicknameRule.max}',
        tone: tone,
        textInputAction: TextInputAction.next,
        inputFormatters: [_NicknameLimiter(_onNicknameRejected)],
        onChanged: (_) => _onNicknameChanged(),
        onSubmitted: (_) => _confirmNickname(),
        // 시안(`158:2778`)은 중복확인을 칸 안에 둔다.
        suffix: FieldActionV2(
          label: AppStrings.profileNicknameConfirm,
          // 묻는 중에도 잠근다. 두 번 누르면 요청이 두 번 나가고,
          // 늦게 온 답이 이긴다.
          //
          // 겹친다는 답을 이미 들었으면 잠근다 — 눌러봐야 같은 답을 받으러
          // 한 번 더 나갈 뿐이다.
          onPressed:
              (status.isValid &&
                  !_checkingNickname &&
                  !(_hasFreshAnswer && _checkedAvailable == false))
              ? _confirmNickname
              : null,
        ),
      ),
    );
  }
}

/// `[ 남자 ][ 여자 ]` 두 갈래 토글. 시안 `158:2760`.
///
/// ⚠️ **여기서만 쓴다.** "두 번째로 쓰이는 순간 `core/widgets/v2/`로 올린다"는
/// 규칙대로, 프로필 수정 화면이 같은 것을 필요로 할 때 올린다.
class _GenderToggle extends StatelessWidget {
  const _GenderToggle({required this.value, required this.onChanged});

  final Gender? value;
  final ValueChanged<Gender> onChanged;

  /// 시안 실측. 바깥 상자 72 · 안쪽 버튼 56.
  static const _outerHeight = 72.0;
  static const _innerHeight = 56.0;
  static const _pad = (_outerHeight - _innerHeight) / 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      height: _outerHeight,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
      ),
      child: Row(
        children: [
          for (final gender in Gender.values) ...[
            if (gender != Gender.values.first)
              const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: _GenderOption(
                gender: gender,
                selected: value == gender,
                onTap: () => onChanged(gender),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.gender,
    required this.selected,
    required this.onTap,
  });

  final Gender gender;
  final bool selected;
  final VoidCallback onTap;

  /// [Gender]를 화면 문구로. **변환을 여기 한 곳에만 둔다.**
  String get _label => switch (gender) {
    Gender.male => AppStrings.profileGenderMale,
    Gender.female => AppStrings.profileGenderFemale,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.primary : Colors.transparent,
        borderRadius: AppRadius.md,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: Center(
            child: Text(
              _label,
              // 고른 쪽은 굵기까지 바뀐다. 색만으로 알리지 않는다.
              style:
                  (selected ? AppTypographyV2.body05 : AppTypographyV2.body06)
                      .copyWith(
                        color: selected
                            ? colors.textOnPrimary
                            : colors.textTertiary,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 누르면 시트가 열리는 칸. 페이스는 `분`과 `초` 두 칸이라 치게 하면 번거롭다.
///
/// 비워 두고 넘어갈 수 있다 — `null`은 **미측정**이다.
class _PaceField extends StatelessWidget {
  const _PaceField({required this.value, required this.onTap});

  /// 고른 값. `null`이면 아직 안 골랐다.
  final String? value;
  final VoidCallback onTap;

  /// 시안의 큰 칸과 같은 71. `AppInputV2`의 라벨 있는 칸에 맞춘다.
  static const _height = 71.0;
  static const _padX = 18.0;
  static const _padY = 14.0;
  static const _labelGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final filled = value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: AppStrings.profilePaceLabel,
          value: value ?? AppStrings.profilePaceHint,
          child: Material(
            color: colors.bgSurface,
            borderRadius: AppRadius.lg,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.lg,
              child: Container(
                height: _height,
                padding: const EdgeInsets.symmetric(
                  horizontal: _padX,
                  vertical: _padY,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppStrings.profilePaceLabel,
                            style: AppTypographyV2.body22.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: _labelGap),
                          Text(
                            value ?? AppStrings.profilePaceHint,
                            style: AppTypographyV2.body04.copyWith(
                              color: filled
                                  ? colors.textPrimary
                                  : colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIcon(AppIcons.down, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        // 비워도 넘어갈 수 있다는 것을 알린다. 이 줄이 없으면 필수로 읽힌다.
        Text(
          AppStrings.profilePaceSkipWhy,
          style: AppTypographyV2.body20.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// 16자를 넘기면 잘라내되, **잘렸다는 사실을 알린다.**
///
/// [LengthLimitingTextInputFormatter]에 자르기를 맡긴다. 자소 클러스터 계산을
/// 직접 하면 이모지에서 틀리고, 화면 카운터와 기준이 어긋난다.
class _NicknameLimiter extends TextInputFormatter {
  _NicknameLimiter(this.onRejected);

  final VoidCallback onRejected;

  late final _limiter = LengthLimitingTextInputFormatter(NicknameRule.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final result = _limiter.formatEditUpdate(oldValue, newValue);
    // 자르기가 실제로 일어났을 때만 알린다.
    if (result.text != newValue.text) onRejected();
    return result;
  }
}

/// 전송 실패 안내 — 아이콘 + 문구.
///
/// **색만으로 알리지 않는다.**
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final OnboardingFailure failure;

  String get _message => switch (failure) {
    OnboardingFailure.sessionExpired => AppStrings.profileSubmitExpired,
    // 닉네임 중복은 그 칸의 helper가 말한다. 여기까지 오지 않는다.
    _ => AppStrings.profileSubmitFailed,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(AppIcons.alert, size: AppSpacing.space5, color: colors.error),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            _message,
            style: AppTypographyV2.body20.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}
