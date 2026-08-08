# 홈 프로필 유도 카드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱을 열자마자 프로필 입력 폼이 뜨지 않게 하고, 대신 홈에서 눈에 띄는 카드로 유도한다.

**Architecture:** `isOnboarded`의 역할을 **"어디로 보낼지"에서 "무엇을 보여줄지"로** 옮긴다. 스플래시와 로그인은 이 값을 보지 않고 항상 홈으로 보낸다. 홈이 그 값을 watch해서 유도 카드를 켜고 끈다. 저장·전송 계층은 손대지 않는다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · go_router 17

**설계 문서:** `docs/specs/2026-08-08-onboarding-flow-design.md` **2-9절** — 왜 뒤집는지가 거기 있다.

**선행 PR:** #15 · #16 머지 완료. 이 계획은 `AuthSignedIn(isOnboarded:)`를 읽기만 한다.

**브랜치:** `feat/profile-prompt` (upstream/dev 기준)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만: `context.appColors` `AppSpacing` `AppRadius` `AppTypography` `AppStrings`
- **`core/theme/tokens/` 밖에서 `Color(0x...)`를 쓰지 않는다.**
- 아이콘은 **Lucide만.** `Icons.*`(Material)·이모지 금지
- 커밋 메시지는 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test`
- **AI를 공동 작성자로 넣지 않는다.**
- 각 태스크 끝에 `analyze` 경고 0개를 확인한다
- 위젯은 필요한 필드만 `select`해서 watch한다
- 한 커밋에 논리적 변경 하나. 각 커밋 시점에 빌드가 되어야 한다

---

## 반드시 먼저 알아야 할 것 셋

**① 화면당 primary 버튼은 하나다.** `app_button.dart:10`에 못박혀 있고 홈에는 이미
"지금 매칭하기"가 primary다. **유도 카드의 버튼은 `secondary`여야 한다.**
요구받은 "눈에 띄게"는 **카드 테두리와 배경**으로 낸다 — 버튼을 primary로 만들면 안 된다.

**② `testWidgets` 안에서 `pumpWidget` 전에 `await`하면 테스트가 영원히 멈춘다.**
가짜 시간 위에서 도는데 시간을 진행시킬 `pump`가 없기 때문이다. **그래서 이 계획은
`signIn()`으로 상태를 만들지 않고 `AuthController`를 상속한 스텁으로 상태를 고정한다.**

**③ 홈이 `authControllerProvider`를 watch해도 `tokenStoreProvider`는 만들어지지 않는다.**
`AuthController.build()`가 `const AuthUnknown()`만 돌려주고 저장소는 getter라 lazy다.
그래서 `home_page_test`에 저장소 override를 넣지 않아도 된다 — 스텁으로 상태만 주면 된다.

---

## File Structure

```
신규  features/home/presentation/profile_prompt_card.dart   유도 카드 위젯

수정  features/home/presentation/home_page.dart             ConsumerWidget + select
      features/onboarding/presentation/splash_page.dart     isOnboarded 분기 제거
      features/auth/presentation/sign_in_page.dart          isOnboarded 분기 제거
      features/onboarding/presentation/profile_setup_page.dart  "나중에 하기"
      core/strings/app_strings.dart                         문구 4개
      docs/implementation-notes.md                          정본 이탈 사유

테스트 home_page_test          카드 표시/미표시 2개
      onboarding_flow_test     기존 1개가 뒤집힌다
      sign_in_page_test        기존 1개가 뒤집힌다
```

**10파일.** PR 하나로 충분하다.

---

## Task 1: 유도 카드 위젯

**Files:**
- Create: `lib/features/home/presentation/profile_prompt_card.dart`
- Modify: `lib/core/strings/app_strings.dart`

**Interfaces:**
- Produces: `ProfilePromptCard({required VoidCallback onTap})`

**이 태스크에는 자동 테스트가 없다.** 콜백을 받아 그리기만 하는 위젯이라 검증할 로직이 없다.
Task 2의 홈 테스트가 이것이 뜨는지 확인한다.

- [ ] **Step 1: 문구를 더한다**

`app_strings.dart`의 홈 문구 근처(`homeEmptyRecentRunHint` 뒤)에 넣는다.

```dart
  // ── 프로필 유도 (S05) ────────────────────────────────────────
  //
  // 정본 S05에 없는 카드다. 온보딩을 마치지 않은 사람을 프로필 등록으로
  // 강제 이동시키는 대신 여기서 만난다(설계 문서 2-9).

  static const homeProfilePromptTitle = '프로필을 완성해주세요';

  /// **왜 필요한지를 말한다.** "완성해주세요"만으로는 미룰 이유밖에 안 준다.
  static const homeProfilePromptBody = '매칭과 칼로리 계산에 필요해요';

  static const homeProfilePromptCta = '완성하기';
```

- [ ] **Step 2: `profile_prompt_card.dart`를 만든다**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 프로필을 아직 안 채운 사람에게 보이는 카드 (S05).
///
/// ## `EmptyStateCard`와 다르게 생겨야 한다
///
/// 빈 상태 카드는 **없다는 사실을 담담하게** 알린다. 이 카드는 **행동을 요구한다.**
/// 같은 회색으로 그리면 "대회가 없어요" 옆에 묻혀서 아무도 누르지 않는다.
/// 그래서 primary 테두리와 옅은 배경을 줘 화면에서 유일하게 튀게 만든다.
///
/// ## ⚠️ 버튼은 secondary다
///
/// `AppButtonVariant.primary`는 **화면당 하나**고(`app_button.dart`), 홈에서는
/// 히어로의 "지금 매칭하기"가 그것이다. 여기까지 primary로 만들면 무엇을 눌러야
/// 하는지가 흐려진다. 강조는 **카드 자체**가 낸다.
///
/// ## 왜 정본에 없는데 만드는가
///
/// 온보딩을 마치지 않은 사람을 앱 진입 시 프로필 폼으로 밀어 넣던 것을 그만두면서,
/// 대신 만날 자리가 필요해졌다(설계 문서 2-9). `docs/implementation-notes.md`에 사유가 있다.
class ProfilePromptCard extends StatelessWidget {
  const ProfilePromptCard({required this.onTap, super.key});

  /// 누르면 프로필 등록으로. **`push`로 여는 것이 호출자의 책임이다** —
  /// 강제가 아니므로 뒤로가기로 나올 수 있어야 한다.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        // 채우지 않고 옅게 깐다. 채우면 히어로의 primary 버튼과 무게가 겹친다.
        color: colors.primaryMuted,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.primary),
      ),
      child: Row(
        children: [
          // EmptyStateCard와 같은 규격(원 40 · 글리프 20)이되 색만 다르다.
          Container(
            width: AppSpacing.space8,
            height: AppSpacing.space8,
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: AppRadius.full,
            ),
            child: Icon(
              LucideIcons.user,
              size: AppSpacing.space5,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.homeProfilePromptTitle,
                  style: AppTypography.body.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space0),
                Text(
                  AppStrings.homeProfilePromptBody,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          AppButton(
            label: AppStrings.homeProfilePromptCta,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.md,
            expand: false,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: analyze**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 경고 0개

쓰는 토큰은 전부 있는 것을 확인했다 — `primary`(`app_colors.dart:62`) ·
`primaryMuted`(`:66`) · `bgSurface`(`:41`).

- [ ] **Step 4: 커밋**

```bash
git add lib/features/home/presentation/profile_prompt_card.dart lib/core/strings/app_strings.dart
git commit -m "📍 Feat: 프로필 완성을 권하는 카드를 만든다"
```

---

## Task 2: 홈에 붙인다

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart`
- Test: `test/home_page_test.dart`

**Interfaces:**
- Consumes: Task 1의 `ProfilePromptCard` · `AuthSignedIn(userId, isOnboarded:)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/home_page_test.dart` 맨 위에 상태를 고정하는 스텁을 더한다 (파일 끝, `main()` 밖).

```dart
/// 상태를 고정한 컨트롤러.
///
/// `signIn()`으로 상태를 만들면 안 된다 — `testWidgets`는 가짜 시간 위에서 도는데
/// `pumpWidget` 전에 Future를 기다리면 시간을 진행시킬 `pump`가 없어 **테스트가 멈춘다.**
/// 여기서는 화면이 주어진 상태를 어떻게 그리는지만 본다.
class _StubAuthController extends AuthController {
  _StubAuthController(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}
```

`pumpHome`을 상태를 받도록 바꾼다.

```dart
  Future<void> pumpHome(WidgetTester tester, {AuthState? auth}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (auth != null)
            authControllerProvider.overrideWith(() => _StubAuthController(auth)),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();
  }
```

파일 끝에 테스트 묶음을 더한다.

```dart
  group('프로필 유도 카드', () {
    testWidgets('온보딩을 안 마쳤으면 카드가 보인다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      expect(find.byType(ProfilePromptCard), findsOneWidget);
      expect(find.text(AppStrings.homeProfilePromptTitle), findsOneWidget);
    });

    testWidgets('온보딩을 마쳤으면 카드가 없다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: true),
      );

      expect(find.byType(ProfilePromptCard), findsNothing);
    });

    testWidgets('로그인 상태를 모를 때도 카드가 없다', (tester) async {
      // 스플래시를 거치지 않고 홈에 바로 온 경우다. 모르는 상태에서
      // 카드를 띄우면 이미 프로필을 채운 사람에게도 잠깐 보인다.
      await pumpHome(tester, auth: const AuthUnknown());

      expect(find.byType(ProfilePromptCard), findsNothing);
    });

    testWidgets('카드를 누르면 프로필 등록으로 간다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      await tester.tap(find.text(AppStrings.homeProfilePromptCta));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupPage), findsOneWidget);
    });
  });
```

import를 더한다.

```dart
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/home/presentation/profile_prompt_card.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/home_page_test.dart
```
기대: 컴파일 실패 — `ProfilePromptCard`가 홈에 없다.

- [ ] **Step 3: `HomePage`를 `ConsumerWidget`으로 바꾼다**

```dart
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    // 필요한 것은 bool 하나다. 상태 전체를 watch하면 관계없는 변화에도
    // 홈이 통째로 다시 그려진다(CLAUDE.md).
    //
    // AuthUnknown일 때 false가 아니라 **true 취급**한다 — 모르는 상태에서
    // 카드를 띄우면 이미 채운 사람에게도 잠깐 보인다.
    final needsProfile = ref.watch(
      authControllerProvider.select(
        (state) => state is AuthSignedIn && !state.isOnboarded,
      ),
    );
```

`HomeHero` 아래에 카드를 끼운다.

```dart
            HomeHero(
              greeting: _greetingText(GreetingRule.of(DateTime.now())),
              onMatch: () => _notReady(context, AppStrings.homeMatchComingSoon),
              onSolo: () => _notReady(context, AppStrings.homeSoloPending),
            ),

            // 매칭 버튼 **바로 아래**에 둔다. "이 버튼을 쓰려면 저게 필요하다"가
            // 눈으로 이어진다.
            if (needsProfile) ...[
              const SizedBox(height: AppSpacing.space4),
              ProfilePromptCard(
                // push다. 강제가 아니므로 뒤로가기로 나올 수 있어야 한다.
                onTap: () => context.push(AppRoutes.profileSetup),
              ),
            ],
            const SizedBox(height: AppSpacing.space7),
```

import를 더한다.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/home/presentation/profile_prompt_card.dart';
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/home_page_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 5: 커밋**

```bash
git add lib/features/home/presentation/home_page.dart test/home_page_test.dart
git commit -m "📍 Feat: 프로필을 안 채운 사람에게 홈에서 유도 카드를 보인다"
```

---

## Task 3: 스플래시와 로그인이 항상 홈으로 보낸다

**Files:**
- Modify: `lib/features/onboarding/presentation/splash_page.dart`
- Modify: `lib/features/auth/presentation/sign_in_page.dart`
- Test: `test/onboarding_flow_test.dart` · `test/sign_in_page_test.dart`

**이 태스크가 이번 변경의 핵심이다.** 기존 테스트 둘이 **뒤집힌다.**

- [ ] **Step 1: 뒤집히는 테스트를 먼저 고친다**

`test/onboarding_flow_test.dart`의 `'온보딩을 안 마쳤으면 프로필 등록으로 간다'`를 통째로 바꾼다.

```dart
    testWidgets('온보딩을 안 마쳤어도 홈으로 간다', (tester) async {
      final (store, repository) = await signedIn(isOnboarded: false);

      await pumpApp(tester, store: store, repository: repository);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      // 앱을 열자마자 폼이 뜨는 것이 당황스럽다(설계 문서 2-9).
      // 프로필은 홈의 유도 카드에서 만난다.
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(ProfileSetupPage), findsNothing);
    });
```

`ProfileSetupPage` import가 이미 있다. `HomePage` import도 있다.

`test/sign_in_page_test.dart`의 `'프로필을 아직 안 채웠으면 홈이 아니라 프로필 등록으로 간다'`를 바꾼다.

```dart
  testWidgets('프로필을 아직 안 채웠어도 홈으로 간다', (tester) async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    // 가입은 했지만 프로필을 안 채운 계정. isOnboarded가 false로 온다.
    //
    // ⚠️ signUp()을 쓰면 안 된다. testWidgets는 가짜 시간 위에서 도는데
    // pumpWidget 전에 Future를 기다리면 시간을 진행시킬 pump가 없어 멈춘다.
    repository.seedAccount(email: 'new@example.com', password: 'runi123!');

    await pumpSignIn(tester, repository: repository);
    await fill(tester, email: 'new@example.com', password: 'runi123!');

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    // 돌아온 사람을 폼으로 가로막지 않는다(설계 문서 2-9).
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ProfileSetupPage), findsNothing);
  });
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/onboarding_flow_test.dart test/sign_in_page_test.dart
```
기대: 두 테스트 FAIL — 아직 프로필 등록으로 간다.

- [ ] **Step 3: 스플래시 분기를 지운다**

`splash_page.dart`의 `_goNext()`에서 `AuthSignedIn` 케이스를 바꾼다.

```dart
      case AuthSignedIn():
        // isOnboarded를 보지 않는다. 프로필을 안 채웠어도 홈으로 보내고
        // 홈의 유도 카드가 그것을 알린다(설계 문서 2-9).
        context.go(AppRoutes.home);
```

클래스 문서의 갈림길 표도 고친다.

```dart
/// ```
/// 토큰이 살아 있다  → 홈 (프로필을 안 채웠으면 홈의 유도 카드가 알린다)
/// 토큰이 만료됐다   → 로그인 (소개는 건너뛴다. 처음 온 사람이 아니다)
/// 저장된 것이 없다  → 온보딩 소개
/// 판정하지 못했다   → 이 화면에 머물며 재시도
/// ```
```

- [ ] **Step 4: 로그인 분기를 지운다**

`sign_in_page.dart`의 성공 처리를 바꾼다.

```dart
    if (failure == null) {
      // isOnboarded를 보지 않는다. 돌아온 사람을 폼으로 가로막지 않는다 —
      // 프로필은 홈의 유도 카드에서 만난다(설계 문서 2-9).
      //
      // go는 스택을 통째로 갈아치운다. 홈에서 뒤로 눌러 로그인으로 돌아가면 안 된다.
      context.go(AppRoutes.home);
    }
```

**쓰이지 않게 된 import를 지운다** — `auth_state.dart`. analyze가 잡아준다.

- [ ] **Step 5: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 6: 커밋**

```bash
git add lib/features/onboarding/presentation/splash_page.dart lib/features/auth/presentation/sign_in_page.dart test/onboarding_flow_test.dart test/sign_in_page_test.dart
git commit -m "🤖 Refactor: 돌아온 사람을 프로필 폼으로 가로막지 않는다"
```

---

## Task 4: 프로필 등록에 "나중에 하기"

**Files:**
- Modify: `lib/features/onboarding/presentation/profile_setup_page.dart`
- Modify: `lib/core/strings/app_strings.dart`

**왜 필요한가** — 가입 직후 프로필 화면은 `go`로 열려 **스택에 그것 하나만 남는다.**
Android 뒤로가기를 누르면 앱이 꺼진다. 사용자가 의도한 동작이 아니다.

- [ ] **Step 1: 문구를 더한다**

`app_strings.dart`의 `profileNext` 근처에 넣는다.

```dart
  /// 프로필을 지금 채우지 않고 나가는 문. **가입 직후 화면은 `go`로 열려
  /// 뒤로가기를 누르면 앱이 꺼진다** — 출구를 눈에 보이게 둔다.
  /// 홈의 유도 카드에서 언제든 돌아올 수 있다.
  static const profileSkipForNow = '나중에 하기';
```

- [ ] **Step 2: 버튼을 더한다**

`profile_setup_page.dart` 하단 `Column`의 `AppButton` 아래에 넣는다.

```dart
                  AppButton(
                    label: AppStrings.profileNext,
                    onPressed: (done && !_submitting) ? _finish : null,
                  ),
                  const SizedBox(height: AppSpacing.space2),

                  // 지금 채우지 않고 나가는 문. 전송 중에는 잠근다.
                  Align(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => context.go(AppRoutes.home),
                      child: Text(
                        AppStrings.profileSkipForNow,
                        style: AppTypography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
```

⚠️ **`AppButton`을 쓰지 않는다.** 이 화면에는 이미 `AppButton`이 여럿 있고(하단 CTA,
닉네임 확인, 페이스 건너뛰기), 여기에 하나 더 두면 **나가는 문이 채우는 길과 같은 무게**가 된다.
`TextButton` + `caption` + `textTertiary`로 가장 낮은 위계를 준다.

- [ ] **Step 3: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/profile_setup_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

⚠️ `profile_setup_test.dart:26`의 `nextEnabled()`가 **라벨로 버튼을 찾는다**
(`find.widgetWithText(AppButton, AppStrings.profileNext)`). `TextButton`을 더해도
`AppButton`을 찾으므로 영향이 없다. 깨지면 그 함수를 확인한다.

- [ ] **Step 4: 커밋**

```bash
git add lib/features/onboarding/presentation/profile_setup_page.dart lib/core/strings/app_strings.dart
git commit -m "📍 Feat: 프로필 등록에서 나중에 하기로 빠져나갈 수 있다"
```

---

## Task 5: 문서 · 검증 · PR

**Files:**
- Modify: `docs/implementation-notes.md`

- [ ] **Step 1: 정본 이탈 사유를 남긴다**

`implementation-notes.md`의 §9-3 뒤에 넣는다.

```markdown
### 9-3-2. 정본에 없는 것 둘 — 홈 유도 카드와 "나중에 하기"

온보딩을 마치지 않은 사람을 **앱 진입 시 프로필 폼으로 밀어 넣던 것을 그만뒀다.**
앱을 열자마자 입력 폼이 뜨는 것이 당황스럽고, 돌아온 사람은 자기 계획이 있는데 폼이
그것을 가로막는다(설계 문서 2-9).

대신 두 곳을 정본에 없이 추가했다.

| 어디 | 무엇 | 왜 |
|---|---|---|
| 홈 (S05) | `ProfilePromptCard` | 강제를 그만두면 만날 자리가 필요하다. 매칭 버튼 바로 아래에 둬서 "이 버튼을 쓰려면 저게 필요하다"가 이어진다 |
| 프로필 등록 (S04) | "나중에 하기" | 가입 직후 화면은 `go`로 열려 **뒤로가기를 누르면 앱이 꺼진다.** 출구를 눈에 보이게 둔다 |

**가입 직후만 프로필로 보낸다.** 그 사람은 방금 계정을 만들었고 흐름을 타고 있다.
가입 흐름까지 놓으면 프로필을 채울 계기가 사실상 사라진다 — 매칭도 러닝도 준비 중이라
카드를 눌러야 할 이유를 실감하기 어렵다.

⚠️ **지금 매칭 버튼에 게이트를 걸면 헛수고가 된다** — 프로필을 다 채우고 다시 눌러도
"매칭은 아직 준비 중이에요"가 뜬다. 게이트는 각 화면(매칭 · S11~S13 러닝 · S20 프로필 탭)이
붙을 때 함께 넣는다.
```

- [ ] **Step 2: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```
기대: 전체 PASS · 경고 0개 · 빌드 성공

⚠️ `format`이 **이번에 손대지 않은 파일**을 바꾸면 되돌린다 (`git checkout -- <파일>`).
지난 두 PR에서 `dio_client.dart`와 `home_page_test.dart`가 매번 걸렸다.

- [ ] **Step 3: 에뮬레이터에서 확인한다**

터널을 열고 에뮬레이터를 띄운 뒤 서버 주소를 주입해 빌드·설치한다.
**화면이 얼면 콜드 부팅한다** (`-no-snapshot-load`) — 앱 문제가 아니다.

| # | 조작 | 기대 |
|---|---|---|
| 1 | 온보딩 안 마친 계정으로 로그인 | **홈** (프로필 폼 아님) |
| 2 | 홈 화면 | 히어로 아래 **유도 카드**가 눈에 띈다 |
| 3 | 카드 [완성하기] | 프로필 등록으로 이동 |
| 4 | 프로필에서 **뒤로가기** | 홈으로 (앱이 꺼지지 않는다) |
| 5 | 프로필 [나중에 하기] | 홈으로 · 카드가 그대로 있다 |
| 6 | 프로필을 끝까지 채우고 완료 | 홈 · **카드가 사라진다** |
| 7 | 온보딩 마친 계정으로 로그인 | 홈 · 카드 없음 |

**6번과 7번이 이 PR의 핵심 검증이다.** 카드가 켜지고 꺼지는 조건이 맞는지 본다.

⚠️ 온보딩을 안 마친 계정이 필요하다. 기존 테스트 계정은 이미 마쳤으므로
**새 계정 가입이 필요하다** — 서버에 계정이 하나 생긴다. 진행 전에 확인받는다.

- [ ] **Step 4: PR을 연다**

```bash
git push -u origin feat/profile-prompt
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 프로필 완성을 홈에서 권한다"
```

**base가 `dev`인지 확인한다.** GitHub는 `main`을 기본으로 잡는다.

PR 본문의 💬 리뷰 포인트에 적는다.

- **기존 테스트 둘이 뒤집혔다** — 스플래시·로그인이 프로필로 보내던 것을 홈으로 바꿨다. 이것이 변경의 증거다
- **카드 버튼을 secondary로 둔 판단** — 홈에는 이미 "지금 매칭하기"가 primary고, `app_button.dart`가 "화면당 하나"를 못박고 있다. 강조는 테두리·배경으로 냈다
- **정본에 없는 요소 둘** — 사유는 `implementation-notes.md` §9-3-2
- **`AuthUnknown`일 때 카드를 숨긴다** — 모르는 상태에서 띄우면 이미 채운 사람에게도 잠깐 보인다
- 카드 문구 3개와 "나중에 하기"는 디자인 확인이 필요하다

---

## 완료 조건

- [ ] `flutter test` 전체 통과
- [ ] `flutter analyze` 경고 0개
- [ ] `flutter build apk --debug` 성공
- [ ] Task 5 Step 3의 에뮬레이터 확인 7개 항목 (특히 6·7)
- [ ] PR이 `dev`를 base로 열려 있음

---

## 이 PR이 하지 않는 것

| | 어디서 |
|---|---|
| 프로필 탭(S20) 유도 | 그 화면이 생길 때 |
| 매칭 진입 게이트 | 매칭 화면이 생길 때 |
| 러닝 칼로리 게이트 | S11~S13이 생길 때 |
| 마케팅 동의 항목 | 별도 작업 (보류 중) |
