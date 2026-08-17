import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/core/widgets/preset_chip.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/pace_level.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_provider.dart';

/// 답한 줄과 시트를 여는 줄의 공통 높이.
///
/// 44px는 **눌리는 최소 크기**지 보기 좋은 크기가 아니다. 이 화면은 답이 다섯 줄까지만
/// 쌓여 아래가 크게 비는데, 줄마다 조금씩 키우면 그 여백이 줄고 줄 사이도 읽기 쉬워진다.
///
/// 두 줄이 **같은 값을 쓰는 것이 중요하다** — 답한 줄과 아직 안 채운 줄의 높이가 다르면
/// 목록이 들쭉날쭉해 보인다. 56은 토큰이 아니라 `터치 최소 + space3`으로 만든 값이다.
const _rowHeight = AppSizes.touchDefault + AppSpacing.space3; // 56

/// 프로필 등록 (S04).
///
/// ## 한 번에 하나만 묻는다
///
/// 와이어프레임은 여섯 항목을 한 화면에 늘어놓는다. 답을 시작하기 전에 분량부터
/// 가늠하게 되는 배치라, 온보딩 3분 안에서는 이탈 신호다.
/// 여기서는 **답하면 다음 질문이 아래에 붙고, 답한 것은 위에 쌓인다.**
/// 쌓인 줄이 곧 진행 상황이라 진행 인디케이터가 따로 필요 없다.
///
/// 쌓인 줄은 아무 때나 눌러 그 질문으로 돌아갈 수 있다. **이게 없으면 자동 진행은
/// 밀려가는 느낌만 준다.**
///
/// ## 타이핑은 닉네임 하나뿐이다
///
/// 생년월일·키·몸무게는 휠 시트로 고른다. 숫자를 치게 하면 2월 31일이나 키 700cm처럼
/// 만들 수 없어야 할 값이 만들어지고, 키보드가 화면 절반을 가린다.
///
/// 성별·페이스는 시트를 쓰지 않는다. 선택지가 3~4개뿐이라 시트를 열면
/// `열기 → 고르기`로 **탭이 하나 늘어난다.** 인라인 칩이 1탭이다.
///
/// ## 상태를 provider로 올리지 않는다
///
/// 서버 전송이 붙었지만 **화면 밖에서 이 값을 알 필요가 여전히 없다.**
/// 여기서 모아 한 번 보내고 화면을 떠나면 버리는 값이다.
/// provider에서 가져오는 것은 값이 아니라 **보낼 곳**(`onboardingRepositoryProvider`)뿐이다.
///
/// 전송 중·실패 상태(`_submitting` · `_submitFailure`)도 화면이 들고 있다 —
/// "버튼이 도는 중"은 화면의 상태지 앱 전체의 상태가 아니다(`auth_provider.dart`와 같은 규칙).
class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage>
    with SingleTickerProviderStateMixin {
  /// 질문 순서. 쉬운 것(이름) → 민감한 것(몸) → 흥미로운 것(페이스) 순이다.
  static const _stepCount = 5;
  static const _stepNickname = 0;
  static const _stepBirth = 1;
  static const _stepGender = 2;
  static const _stepBody = 3;
  static const _stepPace = 4;

  final _scroll = ScrollController();
  final _nickname = TextEditingController();

  /// 지금 묻고 있는 질문. [_stepCount]에 닿으면 다 채운 것이다.
  int _step = 0;

  DateTime? _birth;
  Gender? _gender;
  int? _height;
  int? _weight;

  /// 1km당 초. **`null`은 '미측정'이지 '아직 안 물어봄'이 아니다** —
  /// 물어봤는지는 [_step]이 안다.
  int? _paceSeconds;

  /// 전송 중. 버튼이 두 번 눌리는 것을 막는다.
  bool _submitting = false;

  /// 전송이 실패한 이유. 성공하면 화면을 떠나므로 `null`로 되돌릴 일이 없다.
  OnboardingFailure? _submitFailure;

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
    _shake.dispose();
    _scroll.dispose();
    _nickname.dispose();
    super.dispose();
  }

  // ── 닉네임 ────────────────────────────────────────────────

  /// 사람이 보는 글자 수. 자소 단위로 센다 —
  /// 입력을 자르는 [LengthLimitingTextInputFormatter]와 같은 기준이다.
  int get _nicknameLength => _nickname.text.trim().characters.length;

  NicknameStatus get _nicknameStatus =>
      NicknameRule.of(_nicknameLength, _nickname.text.trim());

  /// 12자를 넘겨 치려 한 순간. 잘라내기만 하면 고장난 것으로 읽힌다.
  void _onNicknameRejected() {
    _limitTimer?.cancel();
    _shake.forward(from: 0);
    setState(() => _limitHit = true);
    _limitTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _limitHit = false);
    });
  }

  void _submitNickname() {
    if (!_nicknameStatus.isValid) return;
    _advance();
  }

  // ── 진행 ──────────────────────────────────────────────────

  void _advance() {
    setState(() => _step++);
    _scrollToBottom();
  }

  void _goBackTo(int step) {
    setState(() => _step = step);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.slow,
        curve: AppMotion.easeSlow,
      );
    });
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final current = _birth ?? DateTime(now.year - 27, 4, 12);

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

    setState(() => _birth = DateTime(picked[0], picked[1], picked[2]));
    _advance();
  }

  Future<void> _pickBody() async {
    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.profileBodyLabel,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitHeight,
          values: [for (var h = 130; h <= 210; h++) h],
          initial: _height ?? 172,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitWeight,
          values: [for (var w = 30; w <= 140; w++) w],
          initial: _weight ?? 63,
        ),
      ],
    );
    if (picked == null) return;

    setState(() {
      _height = picked[0];
      _weight = picked[1];
    });
    _advance();
  }

  Future<void> _pickPace() async {
    final current = _paceSeconds ?? PaceRule.intermediateBelow;

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
          // 5초 단위. 스스로 신고하는 값에 1초 정확도는 의미가 없고,
          // 59칸을 굴리게 하면 고르기가 일이 된다.
          values: [for (var s = 0; s < 60; s += PaceRule.secondStep) s],
          initial: (current % 60) ~/ PaceRule.secondStep * PaceRule.secondStep,
        ),
      ],
    );
    if (picked == null) return;

    setState(() => _paceSeconds = PaceRule.toSeconds(picked[0], picked[1]));
    _advance();
  }

  /// 아직 재본 적 없다. **아무 값도 넣지 않고** 다음으로 간다.
  ///
  /// 기본값을 몰래 채우면 그 숫자가 그대로 시그니처 컬러가 되고, 사용자는
  /// 자기가 고르지 않은 색을 갖게 된다. 미측정은 미측정으로 남긴다.
  void _skipPace() {
    setState(() => _paceSeconds = null);
    _advance();
  }

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _submitFailure = null;
    });

    final profile = OnboardingProfile(
      nickname: _nickname.text.trim(),
      gender: _gender!,
      birthday: _birth!,
      paceSecondsPerKm: _paceSeconds,
      heightCm: _height!,
      weightKg: _weight!,
    );

    OnboardingFailure? failure;
    try {
      await ref.read(onboardingRepositoryProvider).submit(profile);
      // 저장소와 상태를 함께 켠다. 이게 없으면 앱을 껐다 켤 때 다시 여기로 온다.
      await ref.read(authControllerProvider.notifier).markOnboarded();
    } on OnboardingException catch (error) {
      failure = error.failure;
    }

    // await 사이에 화면이 사라졌을 수 있다. setState나 context를 쓰기 전에 반드시 본다.
    if (!mounted) return;

    if (failure != null) {
      // 입력은 그대로 둔다. 다섯 개를 다시 채우게 하지 않는다.
      setState(() {
        _submitting = false;
        _submitFailure = failure;
        // 닉네임 중복만 **고칠 자리가 정해져 있다.** 마지막 화면에 세워두면
        // 어디를 고쳐야 하는지 스스로 찾아야 한다.
        if (failure == OnboardingFailure.nicknameTaken) _step = _stepNickname;
      });
      return;
    }

    // ⚠️ 원래는 시그니처 컬러 리빌(S04.5)로 간다. 그 화면이 아직 없어 여기서 끝난다.
    //
    // 리빌이 생기면 PaceRule.levelOf(_paceSeconds)를 넘긴다.
    // 그 값의 needsPracticeNudge가 홈의 '혼자 연습하기' 유도를 켠다.
    //
    // **왔던 자리로 돌려보낸다.** 프로필 탭의 유도 시트에서 시작했으면 그 탭으로
    // 돌아가 방금 채운 이름이 그 자리에 뜬다. 홈으로 던지면 "내가 쓴 게 어디 갔지"
    // 하고 다시 찾아가야 한다.
    //
    // 인증 직후에는 `go`로 열려 스택에 이 화면뿐이다 — 돌아갈 곳이 없으므로
    // 그때만 홈이다. 처음 온 사람이 볼 것은 자기 프로필이 아니라 매칭이다.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  // ── 그리기 ────────────────────────────────────────────────

  String get _birthLabel {
    final b = _birth!;
    final month = b.month.toString().padLeft(2, '0');
    final day = b.day.toString().padLeft(2, '0');
    return '${b.year}. $month. $day';
  }

  String _answerOf(int step) => switch (step) {
    _stepNickname => _nickname.text.trim(),
    _stepBirth => _birthLabel,
    _stepGender => _genderLabel(_gender!),
    _stepBody =>
      '$_height ${AppStrings.profileUnitHeight} · $_weight ${AppStrings.profileUnitWeight}',
    _ => _paceLabel ?? AppStrings.profilePaceUnmeasured,
  };

  /// `5'42" /km` 형태. 미측정이면 `null`.
  String? get _paceLabel {
    final total = _paceSeconds;
    if (total == null) return null;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return "${total ~/ 60}'$seconds\" ${AppStrings.profilePacePerKm}";
  }

  /// [Gender]를 화면 문구로. **변환을 여기 한 곳에만 둔다** —
  /// 칩 목록과 답한 줄이 각자 변환하면 언젠가 둘이 갈린다.
  String _genderLabel(Gender gender) => switch (gender) {
    Gender.male => AppStrings.profileGenderMale,
    Gender.female => AppStrings.profileGenderFemale,
  };

  String _labelOf(int step) => switch (step) {
    _stepNickname => AppStrings.profileNicknameLabel,
    _stepBirth => AppStrings.profileBirthLabel,
    _stepGender => AppStrings.profileGenderLabel,
    _stepBody => AppStrings.profileBodyLabel,
    _ => AppStrings.profilePaceLabel,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final done = _step >= _stepCount;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space7,
                  AppSpacing.space5,
                  AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.profileTitle,
                      style: AppTypography.h1.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space6),

                    // 답한 것 — 누르면 그 질문으로 돌아간다.
                    for (var i = 0; i < _step; i++)
                      _AnsweredRow(
                        label: _labelOf(i),
                        value: _answerOf(i),
                        onTap: () => _goBackTo(i),
                      ),

                    if (!done) ...[
                      const SizedBox(height: AppSpacing.space6),
                      _currentQuestion(),
                    ],
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 닉네임 중복은 여기 쓰지 않는다. **고칠 입력칸 바로 아래**에
                  // 띄운다 — 화면 맨 아래에 두면 무엇을 고치라는 말인지 멀다.
                  if (_submitFailure != null &&
                      _submitFailure != OnboardingFailure.nicknameTaken) ...[
                    Text(
                      _submitFailure == OnboardingFailure.sessionExpired
                          ? AppStrings.profileSubmitExpired
                          : AppStrings.profileSubmitFailed,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: colors.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                  ],
                  AppButton(
                    label: AppStrings.profileNext,
                    // 마지막 답까지 채워야 열린다. 중간에 누를 일이 없으므로
                    // '무엇이 남았는지' 안내는 두지 않았다 — 남은 건 늘 바로 아래 하나다.
                    //
                    // 전송 중에도 잠근다. 두 번 누르면 요청이 두 번 나간다.
                    onPressed: (done && !_submitting) ? _finish : null,
                  ),

                  // 여기 있던 `나중에 하기`를 없앴다. **인증 직후에는 채우고 지나간다.**
                  //
                  // 나가는 문을 눈에 보이게 두면 대부분 그것을 누르고, 프로필 없는
                  // 사람이 늘어난다. 매칭도 기록도 이 값들 위에 서므로 그만큼 쓸 수
                  // 없는 앱이 된다.
                  //
                  // 여전히 갇히지는 않는다 — 앱을 끄고 다시 열면 자동 로그인이
                  // 홈으로 보내고, 거기서 `ProfilePromptCard`가 이어받는다.
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentQuestion() => switch (_step) {
    _stepNickname => _Question(
      key: const ValueKey(_stepNickname),
      question: AppStrings.profileNicknameQuestion,
      why: AppStrings.profileNicknameWhy,
      child: _nicknameField(),
    ),
    _stepBirth => _Question(
      key: const ValueKey(_stepBirth),
      question: AppStrings.profileBirthQuestion,
      why: AppStrings.profileBirthWhy,
      child: _PickerRow(
        value: _birth == null ? null : _birthLabel,
        onTap: _pickBirth,
      ),
    ),
    _stepGender => _Question(
      key: const ValueKey(_stepGender),
      question: AppStrings.profileGenderQuestion,
      why: AppStrings.profileGenderWhy,
      child: _ChipRow(
        options: const [
          AppStrings.profileGenderMale,
          AppStrings.profileGenderFemale,
        ],
        selected: _gender == null ? null : _genderLabel(_gender!),
        onPick: (value) {
          setState(() {
            _gender = value == AppStrings.profileGenderMale
                ? Gender.male
                : Gender.female;
          });
          _advance();
        },
      ),
    ),
    _stepBody => _Question(
      key: const ValueKey(_stepBody),
      question: AppStrings.profileBodyQuestion,
      why: AppStrings.profileBodyWhy,
      child: _PickerRow(
        value: _height == null ? null : _answerOf(_stepBody),
        onTap: _pickBody,
      ),
    ),
    _ => _Question(
      key: const ValueKey(_stepPace),
      question: AppStrings.profilePaceQuestion,
      why: AppStrings.profilePaceWhy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PickerRow(value: _paceLabel, onTap: _pickPace),
          const SizedBox(height: AppSpacing.space6),

          // 재본 적 없는 사람의 출구. 이게 없으면 입문자가 아무 값이나 찍고 넘어가고,
          // 그 값이 그대로 시그니처 컬러가 된다.
          //
          // 눈썹 문구가 **먼저** 온다. 누구를 위한 길인지 밝히지 않으면
          // 페이스를 아는 사람도 이쪽을 편한 길로 여긴다.
          Text(
            AppStrings.profilePaceSkipEyebrow,
            textAlign: TextAlign.center,
            style: AppTypography.micro.copyWith(
              color: context.appColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),

          // secondary는 테두리만 있고 배경이 없다. 버튼으로 보이면서도
          // 하단의 primary CTA와 무게가 겹치지 않는다.
          // 가로를 채우지 않는 것도 같은 이유다 — 채우면 두 번째 CTA처럼 읽힌다.
          Align(
            child: AppButton(
              label: AppStrings.profilePaceSkip,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.md,
              expand: false,
              onPressed: _skipPace,
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            AppStrings.profilePaceSkipWhy,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: context.appColors.textTertiary,
            ),
          ),
        ],
      ),
    ),
  };

  Widget _nicknameField() {
    final status = _nicknameStatus;

    // 경고가 떠 있는 동안은 일반 안내가 덮어쓰지 않는다.
    // 안 그러면 경고가 뜨자마자 '쓸 수 있는 이름이에요'로 지워진다.
    final (String helper, AppInputTone tone) = _limitHit
        ? (AppStrings.profileNicknameTooLong, AppInputTone.error)
        // 서버가 거절한 이름이다. 형식은 멀쩡하므로 아래 switch는
        // '쓸 수 있는 이름이에요'라고 답한다 — 그것을 덮는다.
        : _submitFailure == OnboardingFailure.nicknameTaken
        ? (AppStrings.profileNicknameTaken, AppInputTone.error)
        : switch (status) {
            NicknameStatus.empty => (
              AppStrings.profileNicknameGuide,
              AppInputTone.neutral,
            ),
            NicknameStatus.tooShort => (
              AppStrings.profileNicknameTooShort,
              AppInputTone.error,
            ),
            NicknameStatus.tooLong => (
              AppStrings.profileNicknameTooLong,
              AppInputTone.error,
            ),
            NicknameStatus.invalidChars => (
              AppStrings.profileNicknameInvalidChars,
              AppInputTone.error,
            ),
            NicknameStatus.valid => (
              AppStrings.profileNicknameOk,
              AppInputTone.success,
            ),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shakeOffset,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeOffset.value, 0),
            child: child,
          ),
          child: AppInput(
            controller: _nickname,
            autofocus: true,
            hint: AppStrings.profileNicknameHint,
            helper: helper,
            counter: '$_nicknameLength/${NicknameRule.max}',
            tone: tone,
            textInputAction: TextInputAction.done,
            inputFormatters: [_NicknameLimiter(_onNicknameRejected)],
            // 이름을 고치는 순간 서버의 거절은 낡은 말이 된다.
            onChanged: (_) => setState(() {
              if (_submitFailure == OnboardingFailure.nicknameTaken) {
                _submitFailure = null;
              }
            }),
            onSubmitted: (_) => _submitNickname(),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppButton(
          label: AppStrings.profileNicknameConfirm,
          onPressed: status.isValid ? _submitNickname : null,
        ),
      ],
    );
  }
}

/// 12자를 넘기면 잘라내되, **잘렸다는 사실을 알린다.**
///
/// [LengthLimitingTextInputFormatter]에 자르기를 맡긴다. 자소 클러스터 계산을
/// 직접 하면 이모지에서 틀리고, 화면 카운터와 기준이 어긋난다.
class _NicknameLimiter extends TextInputFormatter {
  const _NicknameLimiter(this.onRejected);

  final VoidCallback onRejected;

  // LengthLimitingTextInputFormatter는 const 생성자가 아니다.
  static final _limit = LengthLimitingTextInputFormatter(NicknameRule.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final limited = _limit.formatEditUpdate(oldValue, newValue);
    if (limited.text != newValue.text) onRejected();
    return limited;
  }
}

/// 답이 끝난 항목 한 줄. 누르면 그 질문으로 돌아간다.
class _AnsweredRow extends StatelessWidget {
  const _AnsweredRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: '$label ${AppStrings.profileEditHint}',
      value: value,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.sm,
          splashFactory: InkSparkle.splashFactory,
          child: Container(
            constraints: const BoxConstraints(minHeight: _rowHeight),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderDefault)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    label,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: AppTypography.body.copyWith(
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.squarePen,
                  size: AppSpacing.space5,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 지금 묻고 있는 질문 한 덩어리. 나타날 때 아래에서 올라온다.
class _Question extends StatelessWidget {
  const _Question({
    required this.question,
    required this.why,
    required this.child,
    super.key,
  });

  final String question;
  final String why;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.base,
      curve: AppMotion.easeStandard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            question,
            style: AppTypography.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            why,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space4),
          child,
        ],
      ),
    );
  }
}

/// 시트를 여는 줄. 값이 있으면 그 값을, 없으면 자리 표시를 보여준다.
class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.value, required this.onTap});

  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final filled = value != null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.md,
        splashFactory: InkSparkle.splashFactory,
        child: Container(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.md,
            border: Border.all(color: colors.borderDefault),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? AppStrings.profileTapToPick,
                  style: AppTypography.body.copyWith(
                    color: filled ? colors.textPrimary : colors.textDisabled,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                size: AppSpacing.space5,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 단일 선택 칩. 고르면 곧바로 다음 질문으로 넘어간다.
///
/// ## 2열 격자인 이유
///
/// 칩을 글자 크기대로 늘어놓으면 왼쪽으로 쏠려 보인다. 그렇다고 페이스 4개를
/// **한 줄에 균등 배치하면 칸이 87px밖에 안 나와** `잘 몰라요`가 잘린다.
///
/// 2열로 두면 칸이 182px로 넉넉하고, 무엇보다 **성별(2개)과 페이스(4개)의 칩 크기가
/// 같아진다.** 질문이 바뀔 때 버튼 크기가 출렁이지 않는다.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  static const _columns = 2;

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var start = 0; start < options.length; start += _columns) {
      final slice = options.skip(start).take(_columns).toList();
      rows.add(
        Row(
          children: [
            for (var i = 0; i < _columns; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.space2),
              // 홀수 개로 끝나면 마지막 칸을 빈 자리로 채운다.
              // 남은 하나가 폭을 다 먹으면 옆줄과 크기가 어긋난다.
              Expanded(
                child: i < slice.length
                    ? PresetChip(
                        label: slice[i],
                        selected: slice[i] == selected,
                        onTap: () => onPick(slice[i]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.space2),
          rows[i],
        ],
      ],
    );
  }
}
