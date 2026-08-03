import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';

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
/// ## 상태를 provider로 올리지 않은 이유
///
/// 프로필을 보낼 API가 아직 없다. 화면 밖에서 이 값을 알 필요가 없고 화면을 떠나면
/// 버려도 되는 상태다. 서버 전송이 붙는 시점에 provider로 올린다.
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage>
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
  String? _gender;
  int? _height;
  int? _weight;
  String? _pace;

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

  NicknameStatus get _nicknameStatus => NicknameRule.of(_nicknameLength);

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

  void _finish() {
    // ⚠️ 원래는 시그니처 컬러 리빌(S04.5)로 간다. 그 화면이 아직 없어 홈으로 보낸다.
    // 프로필을 서버로 보내는 것도 API가 생긴 뒤다.
    context.go(AppRoutes.home);
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
    _stepGender => _gender!,
    _stepBody =>
      '$_height ${AppStrings.profileUnitHeight} · $_weight ${AppStrings.profileUnitWeight}',
    _ => _pace!,
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
              child: AppButton(
                label: AppStrings.profileNext,
                // 마지막 답까지 채워야 열린다. 중간에 누를 일이 없으므로
                // '무엇이 남았는지' 안내는 두지 않았다 — 남은 건 늘 바로 아래 하나다.
                onPressed: done ? _finish : null,
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
          AppStrings.profileGenderUndisclosed,
        ],
        selected: _gender,
        onPick: (value) {
          setState(() => _gender = value);
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
      child: _ChipRow(
        options: const [
          AppStrings.profilePaceBeginner,
          AppStrings.profilePaceMid,
          AppStrings.profilePaceAdvanced,
          AppStrings.profilePaceUnknown,
        ],
        selected: _pace,
        onPick: (value) {
          setState(() => _pace = value);
          _advance();
        },
      ),
    ),
  };

  Widget _nicknameField() {
    final status = _nicknameStatus;

    // 경고가 떠 있는 동안은 일반 안내가 덮어쓰지 않는다.
    // 안 그러면 경고가 뜨자마자 '쓸 수 있는 이름이에요'로 지워진다.
    final (String helper, AppInputTone tone) = _limitHit
        ? (AppStrings.profileNicknameTooLong, AppInputTone.error)
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
            onChanged: (_) => setState(() {}),
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
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
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
          constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
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

/// 단일 선택 칩 줄. 고르면 곧바로 다음 질문으로 넘어간다.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      children: [
        for (final option in options)
          PresetChip(
            label: option,
            selected: option == selected,
            onTap: () => onPick(option),
          ),
      ],
    );
  }
}
