import 'dart:async';

import 'package:flutter/material.dart';
// `RenderParagraph`가 여기 있다. 긴 주소가 잘렸는지 보려면 그려진 글의
// `didExceedMaxLines`를 읽어야 한다.
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/auth/domain/login_type.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';

/// 설정 화면 — **계정 유형에 따른 분기**와 **나가는 길**.
///
/// ## 왜 나가는 길을 테스트하나
///
/// 라우터에 인증 `redirect`가 아직 없다. `AppShell`의 관문도 `AuthSignedIn`일
/// 때만 서는데 이 화면은 **셸 밖**이라 그 앞도 지나지 않는다.
/// **화면이 직접 내보내지 않으면 로그아웃한 사람이 설정 화면에 그대로 남는다.**
void main() {
  late InMemoryTokenStore tokens;

  /// 약관 동의 기록. **로그아웃에는 남고 탈퇴에는 지워져야 한다.**
  late InMemoryConsentStore consent;

  Future<void> pumpSettings(
    WidgetTester tester, {
    LoginType? loginType = LoginType.local,
    SettingsFailure? withdrawFailure,
    String email = FakeAuthRepository.seedEmail,
    double? width,
  }) async {
    if (width != null) {
      // 기본 테스트 화면은 800 이라 **좁은 기기에서만 나는 잘림이 안 잡힌다.**
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    tokens = InMemoryTokenStore();
    // 이미 약관에 동의하고 쓰던 사람이다. 처음 깐 사람이 아니다.
    consent = InMemoryConsentStore();
    await consent.markTermsAgreed();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    // 저장소에 직접 넣은 토큰이라 가짜 서버는 이것을 모른다. 알려주지 않으면
    // 자동 로그인이 만료로 끝나고 계정 섹션이 통째로 빈다.
    final auth = FakeAuthRepository(
      latency: Duration.zero,
      loginType: loginType,
    )..seedSession(accessToken: 'a-1', refreshToken: 'r-1', email: email);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(consent),
          bodyProfileStoreProvider.overrideWithValue(
            InMemoryBodyProfileStore(),
          ),
          // ⚠️ 계정 유형은 이제 **auth**가 답한다. `/users/me`가 함께 싣고,
          // 설정 화면은 따로 조회하지 않는다.
          // 스플래시가 서버 상태를 읽는다. 진짜를 두면 dio가 서버 주소를 찾다
          // 죽는다 — 테스트에는 주소가 없다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(
              latency: Duration.zero,
              withdrawFailure: withdrawFailure,
            ),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.settings),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️ **스플래시를 건너뛰고 설정으로 바로 들어왔다.** 실제 앱에서는 스플래시가
    // 자동 로그인을 돌려 `/users/me`를 읽어 두는데, 여기서는 그것이 없어
    // 계정 정보가 비어 있다. 같은 일을 대신 해준다.
    //
    // ⚠️ **`await`하지 않는다.** 위젯 테스트는 가짜 시계를 쓰므로 여기서 기다리면
    // `Future.delayed`가 영영 안 끝나고 테스트가 멈춘다. 시계는 `pump`가 돌린다.
    unawaited(
      ProviderScope.containerOf(
        tester.element(find.byType(RuniverseApp)),
        listen: false,
      ).read(authControllerProvider.notifier).restore(),
    );
    await tester.pumpAndSettle();
  }

  /// 설정 목록의 행 하나를 누른다.
  ///
  /// ⚠️ **먼저 화면 안으로 끌어와야 한다.** 테스트 화면은 800×600이라 목록
  /// 아래쪽 행(로그아웃·탈퇴)은 밖에 있고, 그대로 누르면 "off-screen"으로
  /// 실패한다. 행이 하나 늘 때마다 이 경계가 움직인다.
  Future<void> tapRow(WidgetTester tester, String label) async {
    final row = find.text(label);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  group('비밀번호 메뉴 분기', () {
    testWidgets('로컬 계정이면 보인다', (tester) async {
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsPassword), findsOneWidget);
    });

    testWidgets('⚠️ 카카오 계정이면 숨는다', (tester) async {
      // 보여줬다가 409를 맞는 것보다 안 보이는 편이 낫다.
      await pumpSettings(tester, loginType: LoginType.kakao);

      expect(find.text(AppStrings.settingsPassword), findsNothing);
    });

    testWidgets('⚠️ 애플 계정이면 숨고 라벨은 애플이다', (tester) async {
      // 애플 버튼은 iOS에만 있지만 **이 화면은 안드로이드에서도 이 값을 받는다**
      // — 계정의 성질은 기기와 무관하다. 라벨을 플랫폼으로 가리면 기기를 바꾼
      // 사람이 "확인 불가"를 본다.
      await pumpSettings(tester, loginType: LoginType.apple);

      expect(find.text(AppStrings.settingsPassword), findsNothing);
      expect(find.text(AppStrings.settingsLoginApple), findsOneWidget);
    });

    testWidgets('⚠️ 계정 유형을 모르면 숨는다', (tester) async {
      // 서버가 새 제공자를 보냈다. 모르는 것은 대개 소셜이다.
      await pumpSettings(tester, loginType: null);

      expect(find.text(AppStrings.settingsPassword), findsNothing);
      expect(find.text(AppStrings.settingsLoginUnknown), findsOneWidget);
    });
  });

  group('이메일 칸', () {
    /// 한 줄에 안 들어가는 주소.
    ///
    /// ⚠️ **글자 수로 실제 기기를 가늠하지 말 것.** 테스트 글꼴은 글자마다
    /// 폭이 글자 크기와 같은 네모(16)라 실제 글꼴보다 두 배쯤 넓다. 여기서
    /// 24자가 차지하는 폭이 실제 기기의 45자쯤에 해당한다.
    const long = 'runner.kim@hanyang.ac.kr';

    /// 그려진 글. **잘렸는지는 위젯이 아니라 이것만 안다** —
    /// `Text`는 전체 문자열을 들고 있고, 몇 줄에 담겼는지는 그린 쪽이 센다.
    RenderParagraph drawn(WidgetTester tester, Finder text) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );

    testWidgets('보통 주소는 그대로 보여준다', (tester) async {
      await pumpSettings(tester);

      expect(find.text(FakeAuthRepository.seedEmail), findsOneWidget);
      expect(find.text(AppStrings.settingsEmailHiddenByApple), findsNothing);
    });

    testWidgets('⚠️ 애플이 가린 주소는 그대로 보여주지 않는다', (tester) async {
      // 릴레이 주소는 애플이 앱마다 다르게 만들어 주는 값이다. 그대로 띄우면
      // **처음 보는 주소가 자기 계정에 박혀 있는 것**으로 읽힌다.
      await pumpSettings(
        tester,
        loginType: LoginType.apple,
        email: 'a1b2c3d4e5@privaterelay.appleid.com',
      );

      expect(find.text(AppStrings.settingsEmailHiddenByApple), findsOneWidget);
      expect(find.textContaining('privaterelay'), findsNothing);
      // 가린 것과 **못 읽은 것**은 다르다. 로그인 수단은 그대로 뜬다.
      expect(find.text(AppStrings.settingsLoginApple), findsOneWidget);
    });

    testWidgets('⚠️ 좁은 기기에서 긴 주소가 잘리지 않는다', (tester) async {
      // 값 칸이 `Spacer`와 **남은 폭을 반씩 나눠 가져서** 잘렸다. 오른쪽에
      // 자리가 뻔히 비어 있는데도 `…`가 붙었다.
      await pumpSettings(tester, width: 360, email: long);

      final text = find.text(long);
      expect(text, findsOneWidget);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();

      expect(drawn(tester, text).didExceedMaxLines, isFalse, reason: '주소가 잘렸다');
    });

    testWidgets('값이 라벨을 밀어내지 않는다', (tester) async {
      // 값이 남은 폭을 다 쓰게 했으니, 라벨이 깎이지 않는지도 함께 본다.
      //
      // ⚠️ 카카오 계정으로 세운다. 로컬 계정은 **로그인 수단 칸의 값도
      // `이메일`**이라(`settingsLoginLocal`) 라벨을 글자로 찾을 수 없다.
      await pumpSettings(
        tester,
        width: 360,
        email: long,
        loginType: LoginType.kakao,
      );

      final label = find.text(AppStrings.settingsEmail);
      expect(
        tester.getRect(label).right,
        lessThanOrEqualTo(tester.getRect(find.text(long)).left),
        reason: '라벨과 값이 겹쳤다',
      );
      expect(
        drawn(tester, label).didExceedMaxLines,
        isFalse,
        reason: '라벨이 잘렸다',
      );
    });
  });

  group('고지 문서', () {
    testWidgets('⚠️ 방침과 계정삭제 행이 있다', (tester) async {
      // 구글 플레이 심사가 두 링크를 요구한다. 행이 사라지면 심사에서 막힌다.
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsPrivacy), findsOneWidget);
      expect(find.text(AppStrings.settingsAccountDeletion), findsOneWidget);
    });

    testWidgets('이용약관 행이 있다', (tester) async {
      // 가입 때 필수로 동의한 문서라 다시 볼 길이 있어야 한다.
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsTerms), findsOneWidget);
    });
  });

  group('나가는 길', () {
    testWidgets('⚠️ 로그아웃하면 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsSignOut);

      // 다이얼로그의 확인 버튼. 행과 같은 문구라 마지막 것을 누른다.
      await tester.tap(find.text(AppStrings.settingsSignOut).last);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsNothing);
      expect(find.text(AppStrings.authSignInCta), findsOneWidget);
      // 토큰도 지워져야 한다. 화면만 옮기고 남겨두면 다음에 켤 때 되살아난다.
      expect((await tokens.read()).accessToken, isNull);
    });

    testWidgets('취소하면 그대로 남는다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsSignOut);
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });

    testWidgets('⚠️ 탈퇴해도 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);

      // 시트의 확인 버튼.
      await tester.tap(find.text(AppStrings.withdrawConfirm));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authSignInCta), findsOneWidget);
      expect((await tokens.read()).accessToken, isNull);
    });

    testWidgets('⚠️ 탈퇴하면 약관 동의 기록도 지운다', (tester) async {
      // 계정이 사라졌으므로 **동의도 함께 사라진 것**이다. 남겨 두면 같은
      // 구글 계정으로 다시 들어온 사람이 **약관을 건너뛰고** 프로필 입력부터
      // 보게 된다 — 서버에는 처음 만들어지는 계정인데 동의를 받은 적이 없다.
      //
      // `ConsentStore`는 기기 단위라 로그아웃에는 일부러 남긴다. 탈퇴만 다르다.
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);
      await tester.tap(find.text(AppStrings.withdrawConfirm));
      await tester.pumpAndSettle();

      expect(await consent.hasAgreedTerms(), isFalse);
    });

    testWidgets('⚠️ 로그아웃은 약관 동의를 남긴다', (tester) async {
      // 탈퇴와 **반대**다. 같은 사람이 같은 계정으로 다시 들어오는 것이라,
      // 지우면 같은 것을 두 번 묻게 된다.
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsSignOut);
      await tester.tap(find.text(AppStrings.settingsSignOut).last);
      await tester.pumpAndSettle();

      expect(await consent.hasAgreedTerms(), isTrue);
    });

    testWidgets('⚠️ 탈퇴에 실패하면 약관 동의를 지우지 않는다', (tester) async {
      // 503 — 계정은 그대로 있다. 동의만 지우면 다음에 들어올 때 같은 것을
      // 또 묻는다. **지우는 것은 탈퇴가 성공한 뒤여야 한다.**
      await pumpSettings(tester, withdrawFailure: SettingsFailure.server);

      await tapRow(tester, AppStrings.settingsWithdraw);
      await tester.tap(find.text(AppStrings.withdrawConfirm));
      await tester.pumpAndSettle();

      expect(await consent.hasAgreedTerms(), isTrue);
      // 설정 화면에 그대로 남는다.
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
    });

    testWidgets('탈퇴 시트에서 취소하면 계정이 남는다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });

    /// 애플 쪽에 남는 연결 — **탈퇴로는 끊기지 않는다.**
    ///
    /// 우리가 계정을 지워도 애플의 "이 앱에 로그인했다" 기록은 남는다(연동
    /// 가이드 6절). 그것을 모르면 탈퇴한 뒤 애플 설정에 앱이 남아 있는 것이
    /// 고장으로 읽히고, 다시 로그인하면 **새 계정이 또 만들어진다.**
    testWidgets('⚠️ 애플 계정이면 연결 해제 안내가 뜬다', (tester) async {
      await pumpSettings(tester, loginType: LoginType.apple);

      await tapRow(tester, AppStrings.settingsWithdraw);

      expect(find.text(AppStrings.withdrawAppleNotice), findsOneWidget);
      // 본문도 그대로 있다 — 안내가 본문을 밀어내지 않는다.
      expect(find.text(AppStrings.withdrawBody), findsOneWidget);
    });

    testWidgets('⚠️ 로컬 계정에는 애플 안내가 없다', (tester) async {
      // 이메일로 가입한 사람에게 애플 설정을 열라고 하면 쓸모없는 줄이
      // 하나 늘 뿐이다.
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);

      expect(find.text(AppStrings.withdrawAppleNotice), findsNothing);
    });
  });
}
