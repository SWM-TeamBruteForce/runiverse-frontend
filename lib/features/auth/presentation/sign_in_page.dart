import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/email_rule.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/domain/sign_in_method.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/auth/presentation/password_field_v2.dart';

/// 로그인 (S02.5).
///
/// **정본 와이어프레임의 S02.5는 소셜 버튼 셋과 하단 링크뿐이다.**
/// 백엔드가 이메일·비밀번호 방식을 요구해 입력칸을 이 화면에 합쳤다.
/// 방식 선택 화면을 따로 두면 탭이 한 번 더 필요한데, 실제로 고를 것은 셋뿐이라
/// 한 화면에 다 보이는 편이 짧다.
///
/// ## 뒤로가기 버튼이 없다
///
/// 온보딩 소개에서 `go`로 들어와 스택이 비어 있다. 되돌아갈 곳이 없다.
/// 가입 흐름(약관 → 정보 입력)은 `push`로 쌓이므로 그쪽에는 뒤로가기가 있다.
///
/// ## 비밀번호 규칙을 검사하지 않는다
///
/// 규칙(6~16자, 3종 혼합)은 **가입할 때만** 본다. 로그인에서 들이대면, 규칙이 바뀌기 전에
/// 만든 계정의 주인이 자기 비밀번호를 정확히 치고도 막힌다.
/// 비어 있지 않은지만 본다.
///
/// ## 로딩·실패를 provider에 올리지 않는다
///
/// "버튼이 도는 중"은 이 화면이 떠 있는 동안만 의미 있는 값이다.
/// 앱 전체의 인증 상태(`authControllerProvider`)와 섞으면, 로그인 실패가
/// 앱을 로그아웃시키는 식의 사고가 난다.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// 아이디를 기기에 남길지. 저장된 값이 있으면 켠 채로 시작한다.
  bool _rememberEmail = false;

  /// 마지막으로 성공한 로그인 방법. 그 버튼에 표시가 붙는다.
  SignInMethod? _lastMethod;

  bool _busy = false;
  AuthFailure? _failure;

  @override
  void initState() {
    super.initState();
    // ⚠️ 첫 프레임 뒤로 미룬다 — `initState`에서 provider를 읽고 setState하면
    // 빌드 도중 상태가 바뀐다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreMemory());
  }

  /// 기기에 남겨 둔 아이디와 마지막 로그인 방법을 되살린다.
  Future<void> _restoreMemory() async {
    final store = ref.read(signInMemoryStoreProvider);
    final email = await store.savedEmail();
    final method = await store.lastMethod();
    if (!mounted) return;

    setState(() {
      _lastMethod = method;
      if (email != null) {
        _email.text = email;
        // 저장된 값이 있다는 것은 지난번에 켜 뒀다는 뜻이다.
        _rememberEmail = true;
      }
    });
  }

  @override
  void dispose() {
    // 컨트롤러를 버리지 않으면 화면을 떠난 뒤에도 메모리에 남는다.
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && EmailRule.of(_email.text).isValid && _password.text.isNotEmpty;

  /// 입력이 바뀌면 이전 실패 문구를 지운다.
  /// 고치는 중에도 빨간 글씨가 남아 있으면 무엇이 반영됐는지 알 수 없다.
  void _onChanged(String _) {
    setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text.trim(), password: _password.text);

    // 성공했든 아니든 **끈 상태면 지운다** — 껐는데 남아 있으면 껐다고 할 수 없다.
    // 저장은 성공했을 때만 한다. 틀린 이메일을 기억해 주면 다음에도 틀린다.
    await ref
        .read(signInMemoryStoreProvider)
        .rememberEmail(
          _rememberEmail && failure == null ? _email.text.trim() : null,
        );

    // await 사이에 화면이 사라졌을 수 있다. setState나 context를 쓰기 전에 반드시 본다.
    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = failure;
    });

    if (failure == null) _goAfterSignIn();
  }

  /// 로그인에 성공했다. 어디로 갈 것인가.
  ///
  /// **프로필이 없으면 폼이다.** 매칭도 기록도 그 값들 위에 서므로 채워야 쓸 수 있다.
  ///
  /// 이메일과 카카오가 이 한 곳을 함께 쓴다 — 나누면 "로그인 방식에 따라 도착지가
  /// 다르다"는 규칙이 생기고, 한쪽만 고치는 사고가 난다. 스플래시도 같은 기준이다.
  void _goAfterSignIn() {
    final state = ref.read(authControllerProvider);
    final isOnboarded = state is AuthSignedIn && state.isOnboarded;

    // go는 스택을 통째로 갈아치운다. 도착한 뒤 뒤로 눌러 로그인으로 돌아가면 안 된다.
    context.go(isOnboarded ? AppRoutes.home : AppRoutes.profileSetup);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final emailStatus = EmailRule.of(_email.text);

    return Scaffold(
      backgroundColor: colors.bgBase,
      // ⚠️ SafeArea 로 감싸지 않는다. 시안은 사진을 상태바 **뒤까지** 깐다.
      // 아래쪽 여백만 아래에서 따로 준다.
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Hero(),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space9,
                AppSpacing.space6,
                AppSpacing.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.authSignInTitle,
                    style: AppTypographyV2.heading05.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    AppStrings.authSignInSubtitle,
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  AppInputV2(
                    controller: _email,
                    // ⚠️ 라벨을 넘기지 않는다. 시안의 로그인 칸은 힌트만 있고,
                    // 라벨을 주면 칸이 회원가입 쪽 큰 모양으로 바뀐다.
                    hint: AppStrings.authEmailLabel,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: _onChanged,
                    // 입력하는 도중에 "형식이 아니에요"가 뜨면 안 된다.
                    // 아직 다 치지 않았을 뿐이다. 빈 칸도 오류가 아니다.
                    tone: emailStatus == EmailStatus.invalid
                        ? AppInputToneV2.error
                        : AppInputToneV2.neutral,
                    helper: emailStatus == EmailStatus.invalid
                        ? AppStrings.authEmailInvalid
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.space2),

                  PasswordFieldV2(
                    controller: _password,
                    hint: AppStrings.authPasswordLabel,
                    textInputAction: TextInputAction.done,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _submit(),
                  ),

                  const SizedBox(height: AppSpacing.space2),
                  _RememberEmail(
                    value: _rememberEmail,
                    onChanged: (on) => setState(() => _rememberEmail = on),
                  ),

                  if (_failure != null) ...[
                    const SizedBox(height: AppSpacing.space4),
                    _FailureNotice(failure: _failure!),
                  ],

                  const SizedBox(height: AppSpacing.space6),
                  // 높이를 고정해 로딩 중에 아래 버튼들이 밀려 올라가지 않게 한다.
                  SizedBox(
                    height: AppSizes.touchRunning,
                    child: _busy
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
                            label: AppStrings.authSignInCta,
                            onPressed: _canSubmit ? _submit : null,
                          ),
                  ),

                  const SizedBox(height: AppSpacing.space5),
                  const _OrDivider(),
                  const SizedBox(height: AppSpacing.space6),

                  // 시안(`158:2929` `158:2946`)의 간편 로그인은 **글자 없는
                  // 아이콘 타일 둘**이다. 각 서비스의 로고만으로 무엇인지
                  // 알아보게 하는 방식이라, 라벨은 툴팁과 스크린리더에만 준다.
                  //
                  // **회색으로 잠그지 않는다** — 잠긴 타일이 있으면 앱이
                  // 미완성으로 읽힌다. 눌리고, 준비 중임을 알린다.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SocialTile(
                        label: AppStrings.authGoogle,
                        logo: Image.asset('assets/brand/google.png'),
                        background: AppPaletteV2.neutral50,
                        // 구글 로그인은 아직 붙일 구현이 없다.
                        onPressed: () => _notReady(context),
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      _SocialTile(
                        label: AppStrings.authKakao,
                        logo: SvgPicture.asset('assets/brand/kakao.svg'),
                        background: AppPaletteV2.kakaoYellow,
                        lastUsed: _lastMethod == SignInMethod.kakao,
                        onPressed: _busy ? null : _startKakao,
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.space6),
                  _TextLink(
                    label: AppStrings.authToSignUp,
                    // 가입은 **약관 동의부터** 시작한다. 동의를 받기 전에
                    // 이메일·비밀번호를 받아두면 동의 없이 개인정보를 쥐게 된다.
                    //
                    // push라 뒤로가기 한 번에 로그인으로 돌아온다.
                    onPressed: () => context.push(AppRoutes.terms),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카카오 버튼이 부르는 첫 걸음. **인가보다 약관이 먼저다.**
  ///
  /// 카카오 화면에서 받는 동의는 *카카오가 우리에게 이메일을 넘기는 것*에 대한
  /// 동의다. 우리가 서비스를 제공하고 개인정보를 수집하는 것에 대한 동의는 아니다.
  ///
  /// ⚠️ **순서를 바꾸면 안 된다.** 인가가 끝나면 서버가 곧바로 계정을 만들고
  /// 이메일을 저장한다. 그 뒤에 약관을 보이면 이미 수집한 뒤다.
  ///
  /// 한 번 동의하면 기기에 남아 다음부터 건너뛴다. 기기 단위라 재설치하면 다시
  /// 묻는데, 서버가 `termsAgreed`를 저장하면 그 한계가 사라진다.
  Future<void> _startKakao() async {
    final agreedBefore = await ref.read(consentStoreProvider).hasAgreedTerms();
    if (!mounted) return;

    if (agreedBefore) {
      await _signInWithKakao();
      return;
    }

    // 약관 화면은 **동의를 기록하고 `true`를 돌려주기만 한다.** 카카오 SDK를
    // 거기서 부르면 온보딩 화면이 auth의 구현을 알게 된다. 인가는 이쪽 몫이다.
    //
    // 뒤로가기로 나오면 `null`이 온다 — 그때는 인가하지 않는다.
    final agreed = await context.push<bool>(
      AppRoutes.terms,
      extra: TermsNext.kakao,
    );
    if (!mounted || agreed != true) return;

    await _signInWithKakao();
  }

  /// 카카오로 로그인한다. **[_startKakao]를 거쳐서만 들어온다.**
  ///
  /// ## 취소는 화면에 남기지 않는다
  ///
  /// 사용자가 인가 화면에서 뒤로 가면 실패 이유가 돌아오지만, **그것을 그리면
  /// 스스로 그만둔 사람에게 오류를 보여주는 셈**이다. 여기서 걸러낸다.
  Future<void> _signInWithKakao() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    // ⚠️ **여기를 감싸지 않으면 예외 하나가 이 화면을 영구히 잠근다.**
    // `_busy`가 `true`로 굳으면 `_canSubmit`이 `false`가 되어 **이메일 로그인까지
    // 같이 막힌다** — 앱을 다시 켜는 것 말고는 길이 없다.
    //
    // `on Exception`으로는 부족하다. SDK를 초기화하지 않은 채 부르면
    // `LateInitializationError`가 오는데 그것은 `Exception`이 아니라 **`Error`**라
    // `KakaoCodeSource`의 `on Exception`에도, `AuthController`의
    // `on AuthException`에도 걸리지 않고 여기까지 그대로 올라온다.
    // 에뮬레이터에서 카카오 키 없이 눌러 실제로 겪었다.
    AuthFailure? failure;
    try {
      failure = await ref
          .read(authControllerProvider.notifier)
          .signInWithOauth(OauthProvider.kakao);
    } catch (error) {
      // 삼키되 **흔적은 남긴다.** 무엇이 오는지 모르면 고칠 수도 없다 —
      // `KakaoCodeSource`가 로그를 남기는 이유와 같다.
      if (kDebugMode) {
        debugPrint('[kakao] 예상 못 한 오류: ${error.runtimeType} · $error');
      }
      failure = AuthFailure.oauthFailed;
    }

    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = failure == AuthFailure.oauthCancelled ? null : failure;
    });

    // 카카오는 **가입과 로그인이 한 경로다.** 계정이 없으면 서버가 그 자리에서
    // 만들고 `isOnboarded=false`로 답한다. 그래서 첫 로그인은 이메일의 *가입*에
    // 해당하고, [_goAfterSignIn]이 그것을 폼으로 보낸다.
    if (failure == null) _goAfterSignIn();
  }

  void _notReady(BuildContext context) {
    final colors = context.appColorsV2;

    // 이전 안내가 남아 있으면 겹쳐서 쌓인다. 하나만 띄운다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.authSocialComingSoon,
            style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
          ),
          backgroundColor: colors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      );
  }
}

/// 화면 맨 위의 사진. 아래로 갈수록 배경색에 녹는다.
///
/// 비율은 시안 그대로다(412×392). 가로에 맞춰 늘어나므로 폭이 다른 기기에서도
/// 사진이 잘리지 않는다.
///
/// ## ⚠️ 높이에 천장을 둔다
///
/// 비율만 지키면 넓은 화면에서 사진이 화면을 삼킨다 — 폭 800이면 높이가 761이라
/// 로그인 칸이 접힌 곳 아래로 밀려난다. 시안에서 사진이 화면의 43%를 차지하므로
/// 그 비율을 넘지 않게 막는다.
///
/// 그라데이션이 **아래 절반**에만 걸린다. 사진 전체를 덮으면 사진이 흐려지고,
/// 경계에만 걸면 선이 보인다.
class _Hero extends StatelessWidget {
  const _Hero();

  /// 시안의 사진 크기 412×392.
  static const _ratio = 412 / 392;

  /// 시안에서 사진이 차지하는 세로 비율 (392 / 917).
  static const _maxHeightRatio = 392 / 917;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final size = MediaQuery.sizeOf(context);
    final height = math.min(size.width / _ratio, size.height * _maxHeightRatio);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/sign_in_hero.png', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [colors.bgBase.withValues(alpha: 0), colors.bgBase],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 버튼이 아닌 글자 링크. 가입으로 가는 한 줄이 이것이다.
///
/// ⚠️ **시안에 이 줄이 없다.** 없으면 가입할 길이 사라지므로 남겼고,
/// `AppButtonV2`에는 테두리도 면도 없는 변형이 없어 여기서 만든다.
/// 다른 화면이 같은 것을 필요로 하면 그때 `core/widgets/v2/`로 올린다.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.md,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.md,
        child: Container(
          height: AppSizes.touchDefault,
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypographyV2.body11.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// `☐ 아이디 저장` — 라벨까지 눌린다.
///
/// 체크박스만 과녁으로 두면 44를 못 채우고, 옆의 글자를 눌러도 안 켜지면
/// 고장으로 읽힌다.
class _RememberEmail extends StatelessWidget {
  const _RememberEmail({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      checked: value,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: AppRadius.md,
        // 손가락이 닿는 칸을 44 아래로 내리지 않는다. 네모를 44 상자 안에
        // 가운데 두면 **입력 칸보다 안쪽에서 시작해** 왼쪽 줄이 어긋난다.
        // 줄 전체를 44로 세우고 네모는 왼쪽 끝에 붙인다.
        child: Container(
          height: AppSizes.touchDefault,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CheckBox(checked: value),
              const SizedBox(width: AppSpacing.space3),
              Text(
                AppStrings.authRememberEmail,
                style: AppTypographyV2.body12.copyWith(
                  color: value ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 네모 체크 표시.
///
/// ⚠️ **디자인 아이콘 33개에 빈 네모가 없다.** `check`·`check_2`는 둘 다 체크
/// 표시라 꺼진 상태를 그릴 것이 없다. 그래서 네모는 여기서 그리고 안에만
/// 디자인 아이콘을 넣는다 — 빈 네모 아이콘이 오면 이 클래스를 지운다.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SizedBox.square(
      dimension: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: checked ? colors.primary : Colors.transparent,
          borderRadius: AppRadius.xs,
          border: Border.all(
            color: checked ? colors.primary : colors.borderStrong,
          ),
        ),
        // 꺼져 있으면 **빈 네모**다. 회색 체크를 그려두면 켜진 것처럼 읽힌다.
        // 켜진 쪽은 면이 차므로 색 말고 모양으로도 구분된다.
        child: checked
            ? AppIcon(
                AppIcons.check,
                size: AppSpacing.space4,
                color: colors.textOnPrimary,
              )
            : null,
      ),
    );
  }
}

/// 로고 하나만 놓인 간편 로그인 타일. 시안 `158:2929` · `158:2946`.
///
/// ## 글자가 없다
///
/// 시안이 로고만으로 알아보게 한다. 그래서 [label]은 화면에 그려지지 않고
/// **툴팁과 스크린리더에만** 들어간다 — 아이콘만 있는 버튼에 이름이 없으면
/// 스크린리더가 읽을 것이 없다. 위젯 테스트도 이 이름으로 타일을 찾는다.
///
/// ## ⚠️ 바탕색을 테마에서 가져오지 않는다
///
/// 구글의 흰색도 카카오의 노랑도 **그쪽이 정한 값**이다. 다크·라이트에서
/// 갈리는 [AppColorsV2] 대신 팔레트의 고정값을 쓴다.
class _SocialTile extends StatelessWidget {
  const _SocialTile({
    required this.label,
    required this.logo,
    required this.background,
    required this.onPressed,
    this.lastUsed = false,
  });

  final String label;

  /// 로고 그림. ⚠️ **파일 형식이 서비스마다 다르다** — 카카오는 경로 하나짜리
  /// SVG 라 그대로 쓰지만, 구글의 G 는 시안에서 마스크와 색층을 겹쳐 만든
  /// 것이라 SVG 로 옮기면 깨진다. Figma 가 렌더한 PNG 를 쓴다.
  final Widget logo;

  final Color background;
  final VoidCallback? onPressed;

  /// 이 기기에서 마지막으로 성공한 방법인가.
  final bool lastUsed;

  /// 시안 실측. 로고 26, 좌우 여백 16, 위아래 14 → 58×54.
  static const _logoSize = 26.0;
  static const _padX = 16.0;
  static const _padY = 14.0;

  /// `최근 사용` 점의 지름.
  static const _dotSize = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    final tile = Material(
      color: background,
      borderRadius: AppRadius.lg,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.lg,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: _padX, vertical: _padY),
          child: SizedBox.square(dimension: _logoSize),
        ),
      ),
    );

    return Tooltip(
      // ⚠️ 툴팁은 [lastUsed]와 무관하게 늘 같은 문구다. 위젯 테스트가 이것으로
      // 타일을 찾으므로, 여기에 상태를 섞으면 표시가 붙는 순간 못 찾게 된다.
      message: label,
      child: Semantics(
        button: true,
        // 점만 찍으면 스크린리더가 읽을 것이 없다. 이름에 함께 넣는다.
        label: lastUsed ? '$label, ${AppStrings.authLastUsed}' : label,
        enabled: onPressed != null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 로고는 [InkWell] 밖에 얹는다. 안에 두면 잉크 리플이 로고 위를
            // 덮어 브랜드 색이 흐려진다.
            tile,
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: SizedBox.square(dimension: _logoSize, child: logo),
                ),
              ),
            ),

            // 지난번에 쓴 방법 표시. ⚠️ 타일 **밖으로** 나간다 — 안에 넣으면
            // 로고를 가리고, 타일을 키우면 두 타일의 크기가 달라진다.
            if (lastUsed)
              Positioned(
                top: -_dotSize / 3,
                right: -_dotSize / 3,
                child: IgnorePointer(
                  child: Container(
                    width: _dotSize,
                    height: _dotSize,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.bgBase, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        Expanded(child: Divider(color: colors.borderStrong, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
          child: Text(
            AppStrings.authOr,
            style: AppTypographyV2.body17.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(child: Divider(color: colors.borderStrong, height: 1)),
      ],
    );
  }
}

/// 실패 안내 — 아이콘 + 문구.
///
/// **색만으로 알리지 않는다.** 빨간 테두리만 남으면 색을 구분하지 못하는 사용자에게는
/// 아무 정보가 아니다 (디자인 시스템 §1-5).
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final AuthFailure failure;

  /// 서버 `message`를 쓰지 않는다. 서버는 습니다체, 앱은 해요체다.
  String get _message => switch (failure) {
    AuthFailure.invalidCredentials => AppStrings.authFailedCredentials,
    AuthFailure.network => AppStrings.authFailedNetwork,
    // 갔는지 모른다 — 실패로 단정하지 않는다.
    AuthFailure.deliveryUnknown => AppStrings.authFailedTimeout,
    AuthFailure.server => AppStrings.authFailedServer,
    // 앱의 EmailRule·PasswordRule이 못 막은 값이 서버까지 갔다.
    AuthFailure.validation => AppStrings.authFailedValidation,

    // 소셜 로그인 — 이 화면에서 실제로 난다.
    AuthFailure.oauthFailed => AppStrings.authFailedOauth,
    // 이 빌드에 앱 키가 없다. **"다시 시도해주세요"를 쓰지 않는다** —
    // 다시 눌러도 키는 생기지 않는다. 애플 버튼과 같은 말을 한다.
    AuthFailure.oauthUnavailable => AppStrings.authSocialComingSoon,
    AuthFailure.oauthEmailMissing => AppStrings.authFailedOauthEmail,
    // 카카오 계정의 이메일로 이미 가입한 사람이다. 서버가 자동 연동하지 않으므로
    // **이메일 로그인으로 안내한다** — "이미 가입했다"만으로는 갈 곳을 모른다.
    AuthFailure.emailAlreadyExists => AppStrings.authFailedEmailTaken,
    // 취소는 `_signInWithKakao`가 걸러내 여기까지 오지 않는다.
    // enum이라 자리는 있어야 하고, 빈 문구가 그 사실을 드러낸다.
    AuthFailure.oauthCancelled => '',

    // 가입·인증·갱신 전용 실패다. 이 화면에 올 일이 없지만 enum이라
    // 컴파일러가 빠짐을 잡아준다. 뭉뚱그린 문구로 받는다.
    AuthFailure.invalidCode ||
    AuthFailure.codeExpired ||
    AuthFailure.tooManyCodeAttempts ||
    AuthFailure.sendCooldown ||
    AuthFailure.sendDailyLimit ||
    AuthFailure.sendFailed ||
    AuthFailure.emailNotVerified ||
    AuthFailure.sessionExpired ||
    AuthFailure.unknown => AppStrings.authFailedUnknown,
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
