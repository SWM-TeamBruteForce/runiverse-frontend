import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/sign_in_method.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';

/// 로그인 화면이 기억하는 것 — **아이디 저장**과 **최근 사용한 방법**.
///
/// ## 무엇을 위한 기능인가
///
/// 같은 이메일로 계정이 있으면 서버가 409를 주는데 **어느 방법으로 가입했는지는
/// 알려주지 않는다.** 그 자리를 이 기록이 조금 메운다.
///
/// ⚠️ 앱을 지웠다 깔거나 기기를 바꾸면 기록이 없다. 그 한계는 테스트로 막을 수
/// 없고, 서버가 409에 `provider`를 실어 주는 것이 진짜 해법이다.
void main() {
  late InMemorySignInMemoryStore memory;
  late FakeAuthRepository auth;

  // ⚠️ 입력칸 hint가 `runner@example.com`이다. 같은 값을 쓰면 hint에 매치되어
  // 채워지지 않았는데도 테스트가 통과한다.
  const email = 'saved.runner@example.com';
  const password = 'runi123!';

  /// [savedEmail]·[lastMethod]는 **화면을 그리기 전에** 넣는다.
  /// 화면을 띄운 뒤 저장소만 바꾸고 다시 `pumpWidget`하면 State가 재사용되어
  /// `initState`가 돌지 않는다 — 값을 넣어도 화면이 모른다.
  Future<void> pumpSignIn(
    WidgetTester tester, {
    String? savedEmail,
    SignInMethod? lastMethod,
  }) async {
    memory = InMemorySignInMemoryStore();
    if (savedEmail != null) await memory.rememberEmail(savedEmail);
    if (lastMethod != null) await memory.rememberMethod(lastMethod);
    auth = FakeAuthRepository(latency: Duration.zero)
      ..seedAccount(email: email, password: password, isOnboarded: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          signInMemoryStoreProvider.overrideWithValue(memory),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signIn),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, email);
    await tester.enterText(find.byType(TextField).last, password);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, AppStrings.authSignInCta));
    await tester.pumpAndSettle();
  }

  Finder rememberBox() => find.text(AppStrings.authRememberEmail);

  group('아이디 저장', () {
    testWidgets('처음에는 꺼져 있다', (tester) async {
      await pumpSignIn(tester);

      expect(rememberBox(), findsOneWidget);
      expect(await memory.savedEmail(), isNull);
    });

    testWidgets('켜고 로그인하면 다음에 채워진다', (tester) async {
      await pumpSignIn(tester);

      await tester.tap(rememberBox());
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);

      expect(await memory.savedEmail(), email);
    });

    testWidgets('⚠️ 껐으면 저장하지 않는다', (tester) async {
      await pumpSignIn(tester);

      await fillAndSubmit(tester);

      expect(await memory.savedEmail(), isNull);
    });

    testWidgets('⚠️ 로그인에 실패하면 기억하지 않는다', (tester) async {
      // 틀린 이메일을 기억해 주면 다음에도 틀린 값으로 시작한다.
      await pumpSignIn(tester);

      await tester.tap(rememberBox());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'wrong@example.com');
      await tester.enterText(find.byType(TextField).last, password);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.authSignInCta),
      );
      await tester.pumpAndSettle();

      expect(await memory.savedEmail(), isNull);
    });

    testWidgets('저장해 둔 값이 있으면 채운 채로 연다', (tester) async {
      await pumpSignIn(tester, savedEmail: email);

      expect(find.text(email), findsOneWidget);
    });
  });

  group('최근 사용', () {
    testWidgets('로그인하기 전에는 표시가 없다', (tester) async {
      await pumpSignIn(tester);

      expect(find.text(AppStrings.authLastUsed), findsNothing);
    });

    testWidgets('이메일로 로그인하면 카카오에 표시가 붙지 않는다', (tester) async {
      await pumpSignIn(tester);

      await fillAndSubmit(tester);

      expect(await memory.lastMethod(), SignInMethod.email);
    });

    testWidgets('⚠️ 실패한 방법은 기록하지 않는다', (tester) async {
      // 눌러봤다가 안 된 것을 "최근 사용"이라 하면 잘못된 힌트가 된다.
      await pumpSignIn(tester);

      await tester.enterText(find.byType(TextField).first, 'wrong@example.com');
      await tester.enterText(find.byType(TextField).last, password);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.authSignInCta),
      );
      await tester.pumpAndSettle();

      expect(await memory.lastMethod(), isNull);
    });

    testWidgets('기록이 있으면 그 방법에 표시가 뜬다', (tester) async {
      await pumpSignIn(tester, lastMethod: SignInMethod.kakao);

      expect(find.text(AppStrings.authLastUsed), findsOneWidget);
    });
  });
}
