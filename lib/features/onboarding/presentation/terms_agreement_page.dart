import 'package:flutter/material.dart';
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
// 저장소를 고르는 provider는 auth에 모여 있다. `onboarding_provider.dart`가
// `tokenStoreProvider`를 가져다 쓰는 것과 같은 규칙이다 — 화면이 아니라 인프라다.
import 'package:runiverse/features/auth/presentation/auth_provider.dart';

/// 가입 1 · 약관 동의 (S03).
///
/// **가입 흐름의 첫 화면이다.** 이메일·비밀번호를 받기 전에 동의를 먼저 받는다 —
/// 순서가 반대면 동의를 묻기도 전에 개인정보가 서버에 저장된다.
///
/// 로그인 화면에서 `push`로 들어온다. 그래서 뒤로가기로 로그인으로 돌아갈 수 있다.
///
/// **카카오도 여기를 지난다.** 카카오 화면의 동의는 *카카오가 우리에게 이메일을
/// 넘기는 것*에 대한 동의라 우리 약관을 갈음하지 못한다. 다음에 갈 곳은
/// [TermsNext]로 밖에서 정한다.
///
/// ## 필수와 선택
///
/// 마케팅 수신이 선택 항목이다. ⚠️ **선택은 CTA를 막지 않는다** — 막으면 그것은
/// 선택이 아니다. 그래서 [_allAgreed](전체 동의 카드)와 [_canContinue](CTA)를 나눈다.
///
/// ## 상태를 provider로 올리지 않은 이유
///
/// 마케팅 동의를 보낼 API가 아직 없다. 화면 밖에서 이 값을 알 필요가 없고,
/// 화면을 떠나면 버려도 되는 상태라 [StatefulWidget]으로 둔다.
/// 서버 전송이 붙는 시점에 provider로 올린다.
class TermsAgreementPage extends ConsumerStatefulWidget {
  const TermsAgreementPage({super.key, this.next = TermsNext.signUp});

  /// 동의를 마치면 무엇을 할 것인가. 기본값이 [TermsNext.signUp]인 이유는
  /// **딥링크로 이 화면에 바로 와도** 기존 동작이 유지되게 하기 위해서다.
  final TermsNext next;

  @override
  ConsumerState<TermsAgreementPage> createState() => _TermsAgreementPageState();
}

class _TermsAgreementPageState extends ConsumerState<TermsAgreementPage> {
  /// 항목 순서는 **법적 무게 순**이다. 이용약관 → 개인정보 → 민감정보 → 선택.
  static const _terms = [
    _Term(AppStrings.termsService),
    _Term(AppStrings.termsPrivacy),
    _Term(AppStrings.termsHealth),
    _Term(AppStrings.termsMarketing, isRequired: false),
  ];

  /// 동의한 항목의 인덱스. [_terms]와 길이가 같은 `List<bool>` 대신 [Set]을 쓴 이유는
  /// 항목이 늘거나 순서가 바뀌어도 초기화 코드를 고칠 필요가 없어서다.
  final _agreed = <int>{};

  /// 전체 동의 카드의 체크 상태. **선택까지 전부** 켜져야 켜진다.
  bool get _allAgreed => _agreed.length == _terms.length;

  /// CTA 활성 조건. **필수만** 본다.
  ///
  /// ⚠️ [_allAgreed]와 섞으면 마케팅에 동의하지 않은 사람이 가입할 수 없게 된다.
  bool get _canContinue => _terms.indexed
      .where((entry) => entry.$2.isRequired)
      .every((entry) => _agreed.contains(entry.$1));

  void _toggleAll() {
    setState(() {
      if (_allAgreed) {
        _agreed.clear();
      } else {
        _agreed.addAll(List.generate(_terms.length, (i) => i));
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      // 개별 항목을 전부 켜면 전체 동의도 저절로 켜진다 — [_allAgreed]가 파생값이라
      // 따로 동기화할 상태가 없다. 두 값을 각각 들고 있으면 어긋나기 시작한다.
      if (!_agreed.remove(index)) _agreed.add(index);
    });
  }

  Future<void> _submit() async {
    // 동의를 받은 화면이 기록까지 맡는다. 부르는 쪽에 맡기면 흐름이 늘 때
    // **한 곳이 빠뜨린다** — 그러면 동의 없이 지나가는 길이 생긴다.
    //
    // ⚠️ 마케팅 동의는 기록하지 않는다. 서버로 갈 값인데 보낼 곳이 없어
    // 로컬에 남기면 "저장했으니 반영됐다"고 오해할 자리가 생긴다.
    await ref.read(consentStoreProvider).markTermsAgreed();
    if (!mounted) return;

    switch (widget.next) {
      // push라 정보 입력 화면에서 뒤로가기를 누르면 여기로 돌아온다.
      // 동의한 것을 잃지 않는다 — 이 화면이 살아 있어 상태가 남는다.
      case TermsNext.signUp:
        context.push(AppRoutes.signUp);

      // 카카오 SDK를 여기서 부르지 않는다. 부르면 온보딩이 auth의 구현을 알게 된다.
      // **동의했다는 사실만 돌려주고** 인가는 로그인 화면이 시작한다.
      case TermsNext.kakao:
        context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => context.pop(),
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
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space4,
                  AppSpacing.space5,
                  AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.termsTitle,
                      style: AppTypography.h1.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    Text(
                      AppStrings.termsSubtitle,
                      style: AppTypography.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space7),

                    _AgreeAllCard(checked: _allAgreed, onTap: _toggleAll),
                    const SizedBox(height: AppSpacing.space2),

                    for (var i = 0; i < _terms.length; i++)
                      _TermRow(
                        term: _terms[i],
                        checked: _agreed.contains(i),
                        onTap: () => _toggle(i),
                      ),

                    const SizedBox(height: AppSpacing.space6),
                    const _LocationNotice(),
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
                label: AppStrings.termsCta,
                // null이면 비활성이다. 필수 항목이 남아 있는데 눌리면
                // 그 뒤에서 막아야 하고, 사용자는 왜 안 되는지 모른다.
                onPressed: _canContinue ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 약관 한 건. 약관 전문 URL이 정해지면 여기 붙는다.
class _Term {
  const _Term(this.label, {this.isRequired = true});

  final String label;

  /// 선택 항목은 **CTA를 막지 않는다.** 막으면 그것은 선택이 아니다.
  final bool isRequired;
}

/// 누름 피드백 색.
///
/// 기본 잉크 리플은 어두운 배경에서 거의 보이지 않는다. 동의는 **되돌릴 수 있는
/// 법적 의사표시**라, 눌렸는지 아닌지가 분명해야 한다. primary를 옅게 깐다.
WidgetStateProperty<Color?> _pressOverlay(AppColors colors) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return colors.primary.withValues(alpha: 0.16);
      }
      if (states.contains(WidgetState.hovered)) {
        return colors.primary.withValues(alpha: 0.08);
      }
      return null;
    });

/// 전체 동의 — 카드형. 개별 항목보다 시각적으로 무겁게 만든다.
///
/// 선택되면 배경이 `primaryMuted`, 테두리가 `primary`로 바뀐다.
/// 색만으로 상태를 알리지 않도록 체크 아이콘도 함께 바뀐다.
class _AgreeAllCard extends StatelessWidget {
  const _AgreeAllCard({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      checked: checked,
      button: true,
      // 배경이 **바깥**에 있어야 한다. 잉크 리플은 Material 표면에 그려지는데,
      // 색을 가진 컨테이너를 InkWell 안에 두면 그 위를 덮어 리플이 안 보인다.
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easeStandard,
        decoration: BoxDecoration(
          color: checked ? colors.primaryMuted : colors.bgSurface,
          borderRadius: AppRadius.md,
          border: Border.all(
            color: checked ? colors.primary : colors.borderDefault,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.md,
            splashFactory: InkSparkle.splashFactory,
            overlayColor: _pressOverlay(colors),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSizes.touchDefault,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space3,
              ),
              child: Row(
                children: [
                  _CheckMark(checked: checked, filled: true),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      AppStrings.termsAgreeAll,
                      style: AppTypography.bodyLg.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 개별 약관 한 줄. 체크 + `필수`/`선택` 배지 + 라벨.
class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.term,
    required this.checked,
    required this.onTap,
  });

  final _Term term;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 배지 색을 나눈다. 둘 다 primary면 눈으로 구분되지 않아
    // **글자를 읽어야만** 필수인지 알 수 있다.
    final badgeColor = term.isRequired ? colors.primary : colors.textTertiary;

    return Semantics(
      checked: checked,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.sm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.sm,
          splashFactory: InkSparkle.splashFactory,
          overlayColor: _pressOverlay(colors),
          child: Container(
            // 글자는 작지만 누르는 영역은 44px를 지킨다.
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Row(
              children: [
                _CheckMark(checked: checked, filled: false),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  term.isRequired
                      ? AppStrings.termsRequired
                      : AppStrings.termsOptional,
                  style: AppTypography.caption.copyWith(color: badgeColor),
                ),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(
                    term.label,
                    style: AppTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 체크 표시.
///
/// [filled]는 전체 동의 카드용이다. 원을 채워 개별 항목보다 무게를 준다.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked, required this.filled});

  final bool checked;
  final bool filled;

  static const _size = 22.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.easeStandard,
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: checked && filled ? colors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: checked ? colors.primary : colors.borderStrong,
        ),
      ),
      // 꺼져 있으면 **빈 원**이다. 회색 체크를 그려두면 이미 동의한 것처럼 읽힌다.
      // 켜질 때는 커지며 들어온다 — 눌렀다는 사실이 원 안에서도 보여야 한다.
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        switchInCurve: AppMotion.easeStandard,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: checked
            ? Icon(
                LucideIcons.check,
                size: AppSpacing.space4,
                color: filled ? colors.textOnPrimary : colors.primary,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// 다음에 올 권한 요청을 미리 알리는 안내 카드.
///
/// 위치 권한을 여기서 묻지 않는다. 왜 필요한지 모르는 상태에서 물으면 거절당하고,
/// 한 번 거절되면 설정에서 직접 켜야 한다. 매칭 등록(S08) 시점에 묻는다.
class _LocationNotice extends StatelessWidget {
  const _LocationNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: AppRadius.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.info,
            size: AppSpacing.space5,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              AppStrings.termsLocationNotice,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
