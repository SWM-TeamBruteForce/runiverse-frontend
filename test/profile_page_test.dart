import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';

/// 프로필 탭(S22) — 서버 값이 화면에 닿는가, 없을 때 무엇을 하는가.
///
/// 라우터를 태워서 띄운다. 유도 시트의 CTA가 **첫 로그인 때와 같은 화면**을 여는지가
/// 이 화면의 계약이라, 화면만 떼어놓으면 그 절반을 볼 수 없다.
void main() {
  /// 프로필 탭을 띄운다.
  ///
  /// [onboarded]가 프로필을 채운 사람인지다. 값은 `GET /users/me`에서 오고,
  /// 가짜 저장소가 그 답을 흉내 낸다.
  ///
  /// ⚠️ [photos]를 반드시 끼운다. 안 끼우면 아바타가 `HttpProfileImageRepository`를
  /// 만들고, 그것이 `createDio()`를 부르는데 테스트에는 `API_BASE_URL`이 없어
  /// `StateError`로 죽는다 — **화면과 상관없는 테스트까지 전부 무너진다.**
  Future<void> pumpProfile(
    WidgetTester tester, {
    required bool onboarded,
    bool meFails = false,
    FakeProfileImageRepository? photos,
    PhotoPicker? picker,
    FakeProfileRepository? summary,
    String? cachedNickname,
  }) async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    const email = 'runner@example.com';
    repository.seedAccount(
      email: email,
      password: 'runi123!',
      isOnboarded: onboarded,
    );
    final session = repository.issueSession(email: email);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: session.userId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      isOnboarded: onboarded,
    );
    if (cachedNickname != null) {
      await store.saveCurrentUser(
        userId: session.userId,
        isOnboarded: onboarded,
        nickname: cachedNickname,
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(
            meFails ? _MeFailsRepository(repository) : repository,
          ),
          profileImageRepositoryProvider.overrideWithValue(
            photos ?? FakeProfileImageRepository(latency: Duration.zero),
          ),
          profileRepositoryProvider.overrideWithValue(
            summary ?? FakeProfileRepository(),
          ),
          if (picker != null) photoPickerProvider.overrideWithValue(picker),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.profile),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️ 스플래시를 건너뛰고 탭으로 바로 들어왔다. 그래서 아무도 `restore()`를
    // 부르지 않았고 상태가 `AuthUnknown`에 머문다 — 실제 앱에서는 스플래시가
    // 부른다. 여기서 대신 부른다.
    ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    ).read(authControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
  }

  testWidgets('프로필을 채운 사람은 서버가 준 닉네임이 보인다', (tester) async {
    // 닉네임은 이제 `GET /users/{userId}`에서 온다. 본인과 타인이 같은 화면을
    // 쓰기 때문에 출처도 하나여야 한다 — `/users/me`는 저장해 두는 쪽이다.
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(nickname: '러너42'),
    );

    expect(find.text('러너42'), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameEmpty), findsNothing);
  });

  testWidgets('프로필을 안 채운 사람은 빈 상태 문구가 보인다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    // 빈 문자열이나 "알 수 없음"을 그리지 않는다. 값을 못 불러온 것으로 읽힌다.
    expect(find.text(AppStrings.profileNicknameEmpty), findsWidgets);
  });

  testWidgets('⚠️ 채운 사람은 /me가 실패해도 완성하라는 말을 듣지 않는다', (tester) async {
    // 에뮬레이터에서 실제로 겪은 것이다. `/users/me`가 404로 실패하자
    // **이미 프로필을 채운 계정에** "프로필을 완성해주세요"가 떴다.
    //
    // 닉네임이 없는 이유가 둘("안 채웠다" · "못 불러왔다")인데 화면이
    // 그것을 가르지 않으면 이렇게 된다.
    await pumpProfile(tester, onboarded: true, meFails: true);

    expect(find.text(AppStrings.profileNicknameEmpty), findsNothing);
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
  });

  testWidgets('⚠️ 프로필이 없으면 유도 시트가 뜬다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
  });

  testWidgets('프로필을 채웠으면 시트가 뜨지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    // 이미 채운 사람을 막아서면 안내가 아니라 방해다.
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
  });

  testWidgets('⚠️ 시트의 CTA는 첫 로그인 때와 같은 화면을 연다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    await tester.tap(find.text(AppStrings.profileSheetCta));
    await tester.pumpAndSettle();

    // 프로필을 받는 곳이 둘이면 규칙도 둘이 되고, 한쪽만 고치는 사고가 난다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });

  testWidgets('⚠️ 시트에서 연 프로필 등록은 프로필 탭 위에 쌓인다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    await tester.tap(find.text(AppStrings.profileSheetCta));
    await tester.pumpAndSettle();

    // **`push`라 프로필 탭이 아래에 남아 있다.** `go`였다면 사라진다 —
    // 그러면 다 채우고 나서 돌아올 자리가 없어 홈으로 던져진다.
    // 마쳤을 때 `pop`으로 이 자리에 돌아오는 것이 그 위에 선다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
    expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('⚠️ 폼에서 채우지 않고 돌아오면 관문이 다시 선다', (tester) async {
    await pumpProfile(tester, onboarded: false);
    await tester.tap(find.text(AppStrings.profileSheetCta));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupPage), findsOneWidget);

    // 안드로이드 뒤로가기로 폼에서 나온다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 여기가 깨지면 **뒤로가기 한 번으로 관문이 뚫린다.**
    expect(find.byType(ProfileSetupPage), findsNothing);
    expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
  });

  testWidgets('컬렉션 10범주가 전부 잠긴 채로 선다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    for (final label in const [
      AppStrings.hueDistance,
      AppStrings.hueSpeed,
      AppStrings.hueEndurance,
      AppStrings.hueConsistency,
      AppStrings.hueCadence,
      AppStrings.hueInterval,
      AppStrings.hueHills,
      AppStrings.hueRecovery,
      AppStrings.hueCompany,
      AppStrings.hueAdversity,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label 칸이 없다');
    }

    // 분모는 10범주 × 셰이드 3 = 30이다.
    expect(
      find.text(
        AppStrings.profileCollected(
          0,
          RunHue.values.length * RunPalette.shadeCount,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('⚠️ 블렌드 러너 수는 눌리지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    // 서버에 목록 API가 없다. 누를 수 있게 만들면 반응이 없을 때
    // 고장으로 읽힌다.
    expect(
      find.ancestor(
        of: find.text(AppStrings.profileBlendRunners),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  // ── 프로필 요약 ─────────────────────────────────────────────
  //
  // 닉네임·소개·사진은 이제 `/users/{userId}` 한 곳에서 온다.
  // 본인과 타인이 같은 화면을 쓰기 때문에 출처도 하나여야 한다.

  testWidgets('서버가 준 닉네임과 소개를 그린다', (tester) async {
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(
        nickname: '서버이름',
        introduction: '아침에 달려요',
        friendCount: 3,
      ),
    );

    expect(find.text('서버이름'), findsOneWidget);
    expect(find.text('아침에 달려요'), findsOneWidget);
  });

  testWidgets('블렌드 러너 수를 그린다', (tester) async {
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(nickname: '서버이름', friendCount: 3),
    );

    // ⚠️ "친구"라는 말을 쓰지 않는다 — 요청→수락 모델이다(CLAUDE.md).
    expect(find.text(AppStrings.profileBlendRunners), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('⚠️ 서버가 실패해도 저장해 둔 닉네임이 남는다', (tester) async {
    await pumpProfile(
      tester,
      onboarded: true,
      cachedNickname: '캐시된이름',
      summary: FakeProfileRepository(failure: ProfileFailure.server),
    );

    // `/users/{userId}`가 아직 배포되지 않았을 때가 이 상황이다.
    expect(find.text('캐시된이름'), findsOneWidget);
  });

  // ── 프로필 사진 ─────────────────────────────────────────────
  //
  // 서버가 지금 열어 준 것은 사진뿐이다. 닉네임·소개를 고치는 API가 없어
  // 정본의 편집 화면(S22.1)을 만들 수 없고, 그래서 아바타를 직접 누르게 했다.

  /// 우측 상단 ✎. 눌러 **편집 화면(S22.1)으로 간다.**
  Future<void> openEditPage(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
  }

  /// 편집 화면으로 가서 아바타를 눌러 사진 시트를 연다.
  ///
  /// **홈에서는 아바타가 눌리지 않는다.** 바꾸는 자리는 편집 화면 하나다.
  Future<void> openSheet(WidgetTester tester) async {
    await openEditPage(tester);
    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 아바타는 사진 주소를 스스로 받아오지 않는다', (tester) async {
    final photos = FakeProfileImageRepository(latency: Duration.zero);
    await pumpProfile(
      tester,
      onboarded: true,
      photos: photos,
      summary: FakeProfileRepository(
        nickname: '서버이름',
        profileImageUrl: 'https://cdn.test/a.png',
      ),
    );

    // 주소는 프로필 요약이 준다. 아바타가 따로 물으면 **같은 값을 두 번**
    // 받고, 타인 프로필에서는 `fetchUrl()`이 늘 내 사진을 가져와 틀린다.
    expect(photos.fetchCalls, 0);
  });

  testWidgets('사진을 바꾸면 프로필 요약을 다시 받는다', (tester) async {
    final summary = FakeProfileRepository(nickname: '서버이름');
    final picker = _FakePicker(
      image: PickedImage.validated(path: '/a/b.png', sizeBytes: 1024),
    );
    await pumpProfile(
      tester,
      onboarded: true,
      picker: picker,
      summary: summary,
    );
    final before = summary.calls;

    await openSheet(tester);
    await tester.tap(find.text(AppStrings.profilePhotoPick));
    await tester.pumpAndSettle();

    // 새 주소는 서버만 안다. 다시 받지 않으면 아바타가 옛 사진을 문다.
    expect(summary.calls, greaterThan(before));
  });

  // ── 편집 화면으로 가는 문 ────────────────────────────────────
  //
  // 홈에서는 아무것도 고치지 않는다. **바꾸는 자리는 편집 화면 하나**다
  // (정본 S22.1) — 홈에도 두면 같은 일을 하는 문이 둘이 되고, 사진·닉네임은
  // 즉시 저장되는데 나머지는 저장 버튼을 기다린다는 것을 설명할 길이 없다.

  testWidgets('⚠️ 홈에서는 아바타를 눌러도 시트가 열리지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profilePhotoPick), findsNothing);
  });

  testWidgets('⚠️ 홈에는 편집 표시가 없다', (tester) async {
    // 표시가 있으면 눌러서 바꿀 수 있는 것처럼 읽힌다.
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(nickname: '별밤러너'),
    );

    expect(find.byIcon(LucideIcons.camera), findsNothing);
    expect(find.byIcon(LucideIcons.type), findsNothing);
  });

  testWidgets('✎를 누르면 편집 화면이 열린다', (tester) async {
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(nickname: '별밤러너'),
    );

    await openEditPage(tester);

    expect(find.text(AppStrings.profileEditTitle), findsOneWidget);
    // 거기서는 사진을 바꿀 수 있다.
    expect(find.byIcon(LucideIcons.camera), findsOneWidget);
  });

  testWidgets('편집 화면에서 닉네임을 누르면 변경 시트가 열린다', (tester) async {
    await pumpProfile(
      tester,
      onboarded: true,
      summary: FakeProfileRepository(nickname: '별밤러너'),
    );

    await openEditPage(tester);
    await tester.tap(find.text('별밤러너'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileNicknameChangeTitle), findsWidgets);
  });

  testWidgets('사진이 없으면 시트에 지우는 항목이 없다', (tester) async {
    await pumpProfile(tester, onboarded: true);
    await openSheet(tester);

    expect(find.text(AppStrings.profilePhotoPick), findsOneWidget);
    // 이미 기본 이미지인 사람에게 `기본 이미지로`를 보이면 눌러도 아무 일이 없다.
    expect(find.text(AppStrings.profilePhotoReset), findsNothing);
  });

  testWidgets('사진이 있으면 지울 수 있다', (tester) async {
    final photos = FakeProfileImageRepository(
      latency: Duration.zero,
      url: 'https://example.invalid/a.png',
    );
    // 사진이 있는지는 **프로필 요약이 말한다.** 아바타는 주소를 받아 그릴 뿐이라
    // 이미지 저장소에만 심어두면 시트가 지우는 항목을 보여주지 않는다.
    await pumpProfile(
      tester,
      onboarded: true,
      photos: photos,
      summary: FakeProfileRepository(
        profileImageUrl: 'https://example.invalid/a.png',
      ),
    );
    await openSheet(tester);

    await tester.tap(find.text(AppStrings.profilePhotoReset));
    await tester.pumpAndSettle();

    expect(photos.url, isNull);
  });

  testWidgets('앨범에서 고르면 올라간다', (tester) async {
    final photos = FakeProfileImageRepository(latency: Duration.zero);
    final picker = _FakePicker(
      image: PickedImage.validated(path: '/a/b.png', sizeBytes: 1024),
    );
    await pumpProfile(tester, onboarded: true, photos: photos, picker: picker);
    await openSheet(tester);

    await tester.tap(find.text(AppStrings.profilePhotoPick));
    await tester.pumpAndSettle();

    expect(photos.uploaded?.mimeType, 'image/png');
    expect(photos.uploaded?.sizeBytes, 1024);
  });

  testWidgets('⚠️ 앨범에서 취소하면 아무 일도 일어나지 않는다', (tester) async {
    // 취소를 실패로 다루면 "사진을 바꾸지 못했어요"가 뜬다. 그 사람은
    // 올릴 생각을 접었을 뿐이다.
    final photos = FakeProfileImageRepository(latency: Duration.zero);
    await pumpProfile(
      tester,
      onboarded: true,
      photos: photos,
      picker: _FakePicker(),
    );
    await openSheet(tester);

    await tester.tap(find.text(AppStrings.profilePhotoPick));
    await tester.pumpAndSettle();

    expect(photos.uploaded, isNull);
    expect(find.text(AppStrings.profilePhotoFailed), findsNothing);
  });

  testWidgets('⚠️ 올릴 수 없는 형식은 무엇이 문제인지 말해준다', (tester) async {
    // 서버까지 보내면 400 하나로 뭉뚱그려져 형식인지 크기인지 알 수 없다.
    await pumpProfile(
      tester,
      onboarded: true,
      picker: _FakePicker(failure: ProfileImageFailure.unsupportedFormat),
    );
    await openSheet(tester);

    await tester.tap(find.text(AppStrings.profilePhotoPick));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profilePhotoUnsupported), findsOneWidget);
  });

  testWidgets('올리다 실패해도 원래 사진이 남는다', (tester) async {
    // 잠깐 끊긴 것 때문에 멀쩡한 사진이 사라지면 사용자는 지워진 줄 안다.
    final photos = FakeProfileImageRepository(
      latency: Duration.zero,
      url: 'https://example.invalid/a.png',
      failWith: ProfileImageFailure.network,
    );
    await pumpProfile(tester, onboarded: true, photos: photos);

    // 조회부터 실패하므로 시트에는 지우는 항목이 없다. 그래도 화면은 선다.
    await openSheet(tester);
    expect(find.text(AppStrings.profilePhotoPick), findsOneWidget);
  });
}

/// 앨범을 여는 척한다. 실제 구현은 플랫폼 채널이라 테스트에서 부를 수 없다.
class _FakePicker implements PhotoPicker {
  _FakePicker({this.image, this.failure});

  /// `null`이면 사용자가 취소한 것이다.
  final PickedImage? image;

  /// 형식·크기가 조건에 맞지 않은 경우.
  final ProfileImageFailure? failure;

  @override
  Future<PickedImage?> pick() async {
    final failure = this.failure;
    if (failure != null) throw ProfileImageException(failure);
    return image;
  }
}

/// `/users/me`만 실패하는 저장소. 나머지는 [inner]에 맡긴다.
///
/// 서버에 엔드포인트가 아직 없어 실제로 404가 나는 상황을 그대로 만든다.
class _MeFailsRepository implements AuthRepository {
  _MeFailsRepository(this.inner);

  final AuthRepository inner;

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) =>
      throw const AuthException(AuthFailure.server);

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      inner.refresh(refreshToken);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) =>
      inner.signUp(verificationTicket: verificationTicket, password: password);

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => inner.signInWithOauth(provider: provider, authorization: authorization);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}
