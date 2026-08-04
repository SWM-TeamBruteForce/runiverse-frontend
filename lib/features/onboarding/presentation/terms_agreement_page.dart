import 'package:flutter/material.dart';
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

/// 약관 동의 (S03).
///
/// ## 전부 필수다
///
/// 마케팅 정보 수신을 뺐다. 남은 3항목은 모두 필수라 `[선택]` 항목이 없다.
/// 그래서 `isRequired` 같은 필드를 두지 않았다 — 항상 `true`인 값은 분기를 만들지 않는다.
/// 선택 항목이 다시 생기면 그때 [_Term]에 필드를 추가한다.
///
/// ## 상태를 provider로 올리지 않은 이유
///
/// 동의 결과를 보낼 API가 아직 없다. 화면 밖에서 이 값을 알 필요가 없고,
/// 화면을 떠나면 버려도 되는 상태라 [StatefulWidget]으로 둔다.
/// 서버 전송이 붙는 시점에 provider로 올린다.
class TermsAgreementPage extends StatefulWidget {
  const TermsAgreementPage({super.key});

  @override
  State<TermsAgreementPage> createState() => _TermsAgreementPageState();
}

class _TermsAgreementPageState extends State<TermsAgreementPage> {
  /// 항목 순서는 **법적 무게 순**이다. 이용약관 → 개인정보 → 민감정보.
  static const _terms = [
    _Term(AppStrings.termsService),
    _Term(AppStrings.termsPrivacy),
    _Term(AppStrings.termsHealth),
  ];

  /// 동의한 항목의 인덱스. [_terms]와 길이가 같은 `List<bool>` 대신 [Set]을 쓴 이유는
  /// 항목이 늘거나 순서가 바뀌어도 초기화 코드를 고칠 필요가 없어서다.
  final _agreed = <int>{};

  bool get _allAgreed => _agreed.length == _terms.length;

  /// 전부 필수라 CTA 활성 조건과 전체 동의 상태가 같은 값이 된다.
  /// 선택 항목이 생기면 이 둘이 갈라지므로 지금부터 이름을 나눠 둔다.
  bool get _canContinue => _allAgreed;

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

  void _submit() {
    // 동의 결과를 서버에 보내는 것은 API가 생긴 뒤다.
    context.go(AppRoutes.profileSetup);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space8,
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
                        label: _terms[i].label,
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

/// 약관 한 건. 지금은 라벨뿐이지만, 약관 전문 URL이 정해지면 여기 붙는다.
class _Term {
  const _Term(this.label);

  final String label;
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

/// 개별 약관 한 줄. 체크 + `필수` 배지 + 라벨.
class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
                  AppStrings.termsRequired,
                  style: AppTypography.caption.copyWith(color: colors.primary),
                ),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(
                    label,
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
