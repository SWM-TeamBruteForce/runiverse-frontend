import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/features/profile/presentation/profile_edit_page.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 편집 (S22.1) — **무엇이 저장 버튼에 묶이고 무엇이 아닌가.**
///
/// 이 화면에서 잘못될 수 있는 것은 거의 전부 거기에 모여 있다. 사진과 닉네임은
/// 누르는 자리에서 이미 저장되고, 저장 버튼은 소개글·신체 정보만 다룬다.
void main() {
  late FakeProfileRepository repo;

  Future<void> pumpEdit(
    WidgetTester tester, {
    String? nickname = '별밤러너',
    String? introduction,
    ProfileEditFailure? editFails,
  }) async {
    repo = FakeProfileRepository(
      nickname: nickname,
      introduction: introduction,
      editFailure: editFails,
    );

    final auth = FakeAuthRepository(latency: Duration.zero);
    const email = 'runner@example.com';
    auth.seedAccount(email: email, password: 'runi123!', isOnboarded: true);
    final session = auth.issueSession(email: email);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: session.userId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      isOnboarded: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(auth),
          // ⚠️ 없으면 아바타가 진짜 저장소를 만들고 `API_BASE_URL`이 없어 죽는다.
          profileImageRepositoryProvider.overrideWithValue(
            FakeProfileImageRepository(latency: Duration.zero),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.profile),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️ 스플래시를 건너뛰어 아무도 `restore()`를 부르지 않았다. 대신 부른다.
    ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    ).read(authControllerProvider.notifier).restore();
    await tester.pumpAndSettle();

    // ⚠️ **프로필 탭을 거쳐 들어간다.** 편집 화면을 첫 화면으로 띄우면 뒤에
    // 아무것도 없어 `pop`이 죽는다 — 실제 앱에서는 늘 탭 위에 쌓인다.
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
  }

  Finder saveButton() =>
      find.widgetWithText(TextButton, AppStrings.profileEditSave);

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<TextButton>(saveButton()).onPressed != null;

  testWidgets('⚠️ 바꾼 게 없으면 저장이 잠긴다', (tester) async {
    await pumpEdit(tester);

    // 열자마자 눌리면 아무것도 안 바꾸고 요청이 나간다.
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('소개글을 고치면 저장이 열린다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(find.byType(TextField), '즐겁게 달려요');
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('⚠️ 바뀐 것만 보낸다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(find.byType(TextField), '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    // 안 건드린 신체 정보가 실려 나가면 **다른 기기에서 방금 바꾼 값을 덮는다.**
    expect(repo.updated, {'introduction': '즐겁게 달려요'});
  });

  testWidgets('저장에 성공하면 화면이 닫힌다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(find.byType(TextField), '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsNothing);
  });

  testWidgets('저장에 실패하면 화면에 남고 이유가 보인다', (tester) async {
    // 입력을 잃지 않는다. 다시 채우게 하지 않는 것이 이 화면의 약속이다.
    await pumpEdit(tester, editFails: ProfileEditFailure.network);

    await tester.enterText(find.byType(TextField), '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsOneWidget);
    expect(find.text(AppStrings.profileSubmitFailed), findsOneWidget);
    expect(find.text('즐겁게 달려요'), findsOneWidget);
  });

  testWidgets('⚠️ 성별은 화면에 없다', (tester) async {
    // 기능정의서(SETTING-PERSONAL-001)가 **설정 UI 미노출**로 정했다.
    // 보이기만 하고 못 바꾸면 고장으로 읽힌다.
    await pumpEdit(tester);

    expect(find.text(AppStrings.profileGenderLabel), findsNothing);
    expect(find.text(AppStrings.profileGenderMale), findsNothing);
    expect(find.text(AppStrings.profileGenderFemale), findsNothing);
  });

  testWidgets('⚠️ 못 불러온 값은 채우라고 하지 않고 —로 둔다', (tester) async {
    // 서버에 값이 없는 게 아니라 **불러올 API가 없는 것**이다. 온보딩에서
    // 이미 넣은 값이라 "설정하기"는 틀린 말이 된다.
    await pumpEdit(tester);

    expect(find.text(AppStrings.profileEditUnknown), findsWidgets);
  });

  testWidgets('바꾼 게 있는데 나가려 하면 묻는다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(find.byType(TextField), '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileEditDiscardTitle), findsOneWidget);
    // 아직 나가지 않았다.
    expect(find.byType(ProfileEditPage), findsOneWidget);
  });

  testWidgets('바꾼 게 없으면 묻지 않고 나간다', (tester) async {
    await pumpEdit(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileEditDiscardTitle), findsNothing);
  });
}
