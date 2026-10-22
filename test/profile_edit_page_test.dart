import 'package:flutter/material.dart';
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
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/background_picker.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_edit_page.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 프로필 편집 (S22.1) — **무엇이 저장 버튼에 묶이고 무엇이 아닌가.**
///
/// 이 화면에서 잘못될 수 있는 것은 거의 전부 거기에 모여 있다. 사진과 닉네임은
/// 누르는 자리에서 이미 저장되고, 저장 버튼은 소개글·신체 정보만 다룬다.
void main() {
  late FakeProfileRepository repo;
  late FakeProfileImageRepository photos;

  /// 커버가 읽는 저장소. 테스트는 배경을 다루지 않지만 **끼우지 않으면**
  /// 진짜 저장소가 만들어져 서버 주소를 찾다 죽는다.
  late FakeProfileImageRepository background;

  Future<void> pumpEdit(
    WidgetTester tester, {
    String? nickname = '별밤러너',
    String? introduction,
    ProfileEditFailure? editFails,
    String? photoUrl,
    ProfileImageFailure? photoFails,
    String? backgroundUrl,
    ProfileImageFailure? backgroundFails,
    PhotoPicker? picker,
    // 서버가 가지고 있다고 할 신체 정보(51번). 기본은 **온보딩 전**이다.
    StoredBody body = StoredBody.empty,
    ProfileFailure? bodyFails,
    // 중복확인이 돌려줄 답. `null`이면 **못 물어본 것**이다.
    bool? nicknameAvailable = true,
    NicknameChangeFailure? nicknameFails,
  }) async {
    repo = FakeProfileRepository(
      nickname: nickname,
      introduction: introduction,
      profileImageUrl: photoUrl,
      editFailure: editFails,
      body: body,
      bodyFailure: bodyFails,
      nicknameFailure: nicknameFails,
    )..available = nicknameAvailable;
    photos = FakeProfileImageRepository(
      latency: Duration.zero,
      url: photoUrl,
      failWith: photoFails,
    );
    background = FakeProfileImageRepository(
      latency: Duration.zero,
      url: backgroundUrl,
      failWith: backgroundFails,
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
          // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
          tokenStoreProvider.overrideWithValue(store),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          // 스플래시가 서버 상태를 읽는다. 진짜를 두면 dio가 서버 주소를 찾다
          // 죽는다 — 테스트에는 주소가 없다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          // ⚠️ 없으면 아바타가 진짜 저장소를 만들고 `API_BASE_URL`이 없어 죽는다.
          profileImageRepositoryProvider.overrideWithValue(photos),
          // ⚠️ 배경도 끼운다. 커버가 이 provider를 읽는데, 안 끼우면 진짜
          // 저장소가 만들어져 테스트에 없는 서버 주소를 찾다 죽는다.
          backgroundImageRepositoryProvider.overrideWithValue(background),
          // ⚠️ 앨범을 여는 것은 플랫폼 채널이라 테스트에 없다.
          photoPickerProvider.overrideWithValue(picker ?? _FakePicker()),
          profileRepositoryProvider.overrideWithValue(repo),
          // ⚠️ **없으면 신체 정보 칸이 잠긴 채로 열린다.** 기본값은 `null`
          // (묻지 않는다)이고, 화면은 못 물어본 것을 못 불러온 것으로 다룬다.
          // 진짜 앱에서 이 자리를 잇는 것은 `main.dart`다.
          bodyProfileRemoteProvider.overrideWithValue(repo),
          // 플랫폼 채널이 없어 진짜 저장소는 읽기·쓰기에서 던진다.
          bodyProfileStoreProvider.overrideWithValue(
            InMemoryBodyProfileStore(),
          ),
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
    // ⚠️ 연필 아이콘이 아니라 **글자 버튼**이다(시안 `158:3933`).
    await tester.tap(find.text(AppStrings.profileEditOpen));
    await tester.pumpAndSettle();
  }

  /// 저장 버튼. **문구로 찾는다** — `TextButton` 인지 무엇인지에 기대지 않는다.
  Finder saveButton() => find.text(AppStrings.profileEditSave);

  /// 소개글 입력. **부품 타입이 아니라 키로 찾는다** — 디자인을 바꿔도 키만
  /// 이어받으면 이 테스트가 산다.
  final introductionField = find.byKey(const ValueKey('profile-introduction'));

  /// 저장이 열려 있는가. **부품의 `onPressed` 를 보지 않는다.**
  ///
  /// 눌러 보고 **서버로 나갔는지**로 판단한다. 잠김은 부품의 속성이 아니라
  /// 화면의 약속이고, 디자인이 바뀌어도 그 약속은 그대로다.
  ///
  /// ⚠️ **세 길을 다 본다.** 사진은 `PATCH` 가 아니라 제 갈 길로 가므로,
  /// `repo.updated` 만 보면 사진만 바꿨을 때 **열린 저장을 잠겼다고 읽는다.**
  Future<bool> saveOpens(WidgetTester tester) async {
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    return repo.updated != null ||
        repo.changedTo != null ||
        photos.uploaded != null ||
        photos.removed;
  }

  /// 아바타를 눌러 사진 시트를 연다.
  Future<void> openPhotoSheet(WidgetTester tester) async {
    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();
  }

  /// 앨범에서 한 장 고른 셈 친다.
  Future<void> pickPhoto(WidgetTester tester) async {
    await openPhotoSheet(tester);
    await tester.tap(find.text(AppStrings.profilePhotoPick));
    await tester.pumpAndSettle();
  }

  /// 배경 이미지 — **사진과 같은 규칙, 다른 자리** (1.1.1 배경 가이드).
  ///
  /// ⚠️ 고른 것은 화면에만 남고 **저장 버튼이 보낸다.** 배경만 즉시 올리면 한
  /// 화면에 규칙이 둘이 되고, 사용자는 무엇이 이미 갔는지 알 수 없다.
  group('배경 이미지', () {
    /// 고른 사진. **기본 picker는 (취소)이라** 심어 줘야 한다.
    final picked = _FakePicker(
      image: PickedImage.validated(path: '/a/cover.png', sizeBytes: 2048),
    );

    /// 미리보기를 눌러 **앨범에서 선택**까지 고른다.
    Future<void> pickBackground(WidgetTester tester) async {
      await tester.tap(find.byType(BackgroundPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.profilePhotoPick));
      await tester.pumpAndSettle();
    }

    testWidgets('편집 화면에 배경 자리가 있다', (tester) async {
      await pumpEdit(tester, picker: picked);

      expect(find.byType(BackgroundPicker), findsOneWidget);
    });

    /// ⚠️ **프로필 화면과 같은 배치다.** 커버가 맨 위에서 폭을 다 쓰고, 아바타가
    /// 그 아래변에 걸친다. 편집 화면만 다른 모양이면 같은 것을 두 가지로
    /// 기억해야 한다 — 바꾸는 자리와 보이는 자리가 닮아야 무엇을 바꾸는지 안다.
    group('⚠️ 프로필 화면과 같은 배치다', () {
      testWidgets('커버가 맨 위에서 폭을 다 쓴다', (tester) async {
        await pumpEdit(tester, picker: picked);

        final screen = tester.getSize(find.byType(Scaffold)).width;
        final cover = tester.getRect(find.byType(BackgroundPicker));

        expect(cover.left, 0, reason: '좌우 여백 없이 가장자리까지 간다');
        expect(cover.width, screen);
      });

      testWidgets('커버가 아바타보다 위에 있다', (tester) async {
        await pumpEdit(tester, picker: picked);

        final cover = tester.getRect(find.byType(BackgroundPicker));
        final avatar = tester.getRect(find.byType(ProfileAvatar));

        expect(cover.top, lessThan(avatar.top));
      });

      testWidgets('⚠️ 아바타가 커버에 걸친다', (tester) async {
        // 걸치지 않으면 커버와 프로필이 **두 덩어리**로 보인다. 프로필 화면이
        // 같은 이유로 같은 일을 한다(`ProfileHeader.coverOverlap`).
        await pumpEdit(tester, picker: picked);

        final cover = tester.getRect(find.byType(BackgroundPicker));
        final avatar = tester.getRect(find.byType(ProfileAvatar));

        expect(avatar.top, lessThan(cover.bottom), reason: '윗변이 커버 안에 든다');
        expect(avatar.bottom, greaterThan(cover.bottom), reason: '아래는 커버 밖');
      });

      testWidgets('아바타가 왼쪽에 선다', (tester) async {
        await pumpEdit(tester, picker: picked);

        final screen = tester.getSize(find.byType(Scaffold)).width;
        final avatar = tester.getRect(find.byType(ProfileAvatar));

        expect(avatar.center.dx, lessThan(screen / 2));
      });
    });

    testWidgets('⚠️ 누를 수 있다는 표시가 있다', (tester) async {
      // 누르면 열리기는 하는데 **그냥 사각형**이면 아무도 누를 줄 모른다.
      // 아바타가 카메라 배지로 같은 일을 한다 — 같은 화면에서 한쪽만 말하지
      // 않으면 그 자리는 없는 것과 같다.
      //
      // ⚠️ **글자는 없다**(2026-10-22 요청). 그래서 낭독기가 읽을 것은
      // `Semantics` 라벨뿐이고, 그것이 빠지면 **눈으로만 쓸 수 있는 버튼**이
      // 된다. 아이콘과 라벨을 함께 본다.
      await pumpEdit(tester, picker: picked);

      expect(
        find.descendant(
          of: find.byType(BackgroundPicker),
          matching: find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == AppIcons.camera,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BackgroundPicker),
          matching: find.bySemanticsLabel(AppStrings.profileEditBackground),
        ),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 아바타에도 글자가 없다 — 라벨만 남는다', (tester) async {
      // 커버 버튼과 같은 규칙이다(2026-10-22 요청). `사진 바꾸기` 글자를 뺀
      // 만큼 **낭독기가 읽을 것은 `Semantics` 라벨뿐**이고, 그것이 빠지면
      // 눈으로만 쓸 수 있는 버튼이 된다.
      await pumpEdit(tester, picker: picked);

      expect(find.text('사진 바꾸기'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ProfileAvatar),
          matching: find.bySemanticsLabel(AppStrings.profilePhotoChangeLabel),
        ),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 버튼에 글자를 넣지 않는다', (tester) async {
      // 홈과 같은 그림으로 두기 위한 결정이다(2026-10-22 요청). 글자가 돌아오면
      // 커버 위에 말풍선 같은 덩어리가 생겨 홈과 다시 달라진다.
      await pumpEdit(tester, picker: picked);

      expect(find.text(AppStrings.profileEditBackground), findsNothing);
    });

    testWidgets('⚠️ 고른 것은 저장 전까지 올라가지 않는다', (tester) async {
      await pumpEdit(tester, picker: picked);

      await pickBackground(tester);

      expect(background.uploaded, isNull);
    });

    testWidgets('저장을 누르면 올라간다', (tester) async {
      await pumpEdit(tester, picker: picked);
      await pickBackground(tester);

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(background.uploaded, isNotNull);
    });

    testWidgets('⚠️ 배경만 바꿔도 저장이 열린다', (tester) async {
      // 사진·소개글은 그대로인데 저장이 잠기면 **고른 배경이 버려진다.**
      await pumpEdit(tester, picker: picked);

      await pickBackground(tester);
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(background.uploaded, isNotNull);
    });

    testWidgets('기본 이미지로를 고르면 지운다', (tester) async {
      await pumpEdit(
        tester,
        picker: picked,
        backgroundUrl: 'https://cdn.test/cover.jpg',
      );

      await tester.tap(find.byType(BackgroundPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.profilePhotoReset));
      await tester.pumpAndSettle();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(background.removed, isTrue);
    });

    testWidgets('⚠️ 올릴 수 없는 사진을 고르면 무엇이 문제인지 말해 준다', (tester) async {
      // 10MB를 넘거나 허용 외 형식이면 `PickedImage`가 서버에 가기 전에
      // 막는다. 조용히 삼키면 **미리보기도 안 바뀌고 문구도 안 떠서**,
      // 사용자는 같은 사진을 다시 고른다. 프로필 사진은 이미 말해 준다.
      await pumpEdit(
        tester,
        picker: _FakePicker(failure: ProfileImageFailure.tooLarge),
      );

      await tester.tap(find.byType(BackgroundPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.profilePhotoPick));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('⚠️ 배경이 실패하면 프로필 값이 안 나간다', (tester) async {
      // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다.
      await pumpEdit(
        tester,
        picker: picked,
        backgroundFails: ProfileImageFailure.upload,
      );
      await pickBackground(tester);
      await tester.enterText(introductionField, '바뀐 소개');
      await tester.pumpAndSettle();

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.updated, isNull, reason: '프로필 값은 나가지 않는다');
      expect(find.byType(ProfileEditPage), findsOneWidget, reason: '화면에 남는다');
    });
  });

  /// 닉네임 — **시트에서 내려왔다**(2026-10-22 요청).
  ///
  /// ## ⚠️ 저장 시점이 바뀌었다
  ///
  /// 전에는 시트에서 **누르는 자리에서 즉시** 저장됐다. 지금은 사진·배경·
  /// 소개글과 같이 **저장 버튼이 보낸다.** 중복확인이 치는 동안 도는 것은
  /// 그대로다 — 그 규칙은 `nickname_field_test.dart`가 지킨다.
  group('닉네임', () {
    /// 이름을 고치고 **디바운스가 끝날 때까지** 기다린다.
    Future<void> typeNickname(WidgetTester tester, String name) async {
      await tester.enterText(find.byType(TextField).first, name);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ 고친 것만으로는 아직 안 간다', (tester) async {
      // 즉시 저장이던 시절의 습관이 남으면, 저장을 안 누르고 나간 사람의
      // 이름이 바뀌어 있다.
      await pumpEdit(tester);

      await typeNickname(tester, '완두콩');

      expect(repo.changedTo, isNull);
    });

    testWidgets('저장을 누르면 그때 간다', (tester) async {
      await pumpEdit(tester);

      await typeNickname(tester, '완두콩');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.changedTo, '완두콩');
    });

    testWidgets('⚠️ 닉네임만 바꿔도 저장이 열린다', (tester) async {
      // 저장 버튼이 세는 값에 닉네임을 안 넣으면, 이름만 고친 사람은
      // **잠긴 버튼을 보며 왜 안 눌리는지 모른다.**
      await pumpEdit(tester);

      await typeNickname(tester, '완두콩');

      expect(await saveOpens(tester), isTrue);
    });

    testWidgets('⚠️ 보낼 수 없는 이름이면 저장이 열리지 않는다', (tester) async {
      // 형식이 틀렸거나 겹치는 이름이다. 열어 두면 눌러봐야 서버가 거절한다.
      await pumpEdit(tester, nicknameAvailable: false);

      await typeNickname(tester, '완두콩');

      expect(await saveOpens(tester), isFalse);
    });

    testWidgets('⚠️ 보내다 겹치면 화면에 남고 칸이 말해 준다', (tester) async {
      // 묻고 누르는 사이에 남이 가져갈 수 있다. 닫아 버리면 다시 들어와
      // 처음부터 쳐야 한다.
      await pumpEdit(tester, nicknameFails: NicknameChangeFailure.taken);

      await typeNickname(tester, '완두콩');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(find.byType(ProfileEditPage), findsOneWidget);
      expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
    });

    testWidgets('⚠️ 닉네임이 실패하면 소개글도 안 나간다', (tester) async {
      // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다 — 사진·배경과
      // 같은 규칙이다.
      await pumpEdit(tester, nicknameFails: NicknameChangeFailure.taken);

      await tester.enterText(introductionField, '즐겁게 달려요');
      await tester.pumpAndSettle();
      await typeNickname(tester, '완두콩');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.updated, isNull);
    });
  });

  testWidgets('⚠️ 바꾼 게 없으면 저장이 잠긴다', (tester) async {
    await pumpEdit(tester);

    // 열자마자 눌리면 아무것도 안 바꾸고 요청이 나간다.
    expect(await saveOpens(tester), isFalse);
  });

  testWidgets('소개글을 고치면 저장이 열린다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();

    expect(await saveOpens(tester), isTrue);
  });

  testWidgets('⚠️ 바뀐 것만 보낸다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    // 안 건드린 신체 정보가 실려 나가면 **다른 기기에서 방금 바꾼 값을 덮는다.**
    expect(repo.updated, {'introduction': '즐겁게 달려요'});
  });

  testWidgets('저장에 성공하면 화면이 닫힌다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsNothing);
  });

  testWidgets('저장에 실패하면 화면에 남고 이유가 보인다', (tester) async {
    // 입력을 잃지 않는다. 다시 채우게 하지 않는 것이 이 화면의 약속이다.
    await pumpEdit(tester, editFails: ProfileEditFailure.network);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsOneWidget);
    expect(find.text(AppStrings.profileSubmitFailed), findsOneWidget);
    expect(find.text('즐겁게 달려요'), findsOneWidget);
  });

  group('⚠️ 사진도 저장 버튼을 기다린다', () {
    // ⚠️ **예전에는 고르는 즉시 올라갔다.**
    //
    // 저장 버튼은 꺼진 채로 있고 그냥 나가면 이미 반영돼 있었다 — 버튼이
    // 꺼져 있으니 **저장할 것이 없다는 뜻으로 읽히는데 실제로는 이미
    // 저장된 뒤**였다. 되돌릴 방법도 없었다.
    //
    // 이제 고르기·지우기 둘 다 화면에만 반영되고, 저장을 눌러야 서버로 간다.

    final picked = _FakePicker(
      image: PickedImage.validated(path: '/a/b.png', sizeBytes: 1024),
    );

    testWidgets('고르면 저장이 열린다', (tester) async {
      await pumpEdit(tester, picker: picked);

      await pickPhoto(tester);

      expect(await saveOpens(tester), isTrue);
    });

    testWidgets('⚠️ 저장을 누르기 전에는 올라가지 않는다', (tester) async {
      await pumpEdit(tester, picker: picked);

      await pickPhoto(tester);

      expect(photos.uploaded, isNull, reason: '아직 저장을 누르지 않았다');
    });

    testWidgets('저장을 누르면 그때 올라간다', (tester) async {
      await pumpEdit(tester, picker: picked);
      await pickPhoto(tester);

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(photos.uploaded?.mimeType, 'image/png');
      expect(photos.uploaded?.sizeBytes, 1024);
    });

    testWidgets('⚠️ 저장하지 않고 나가면 올라가지 않는다', (tester) async {
      await pumpEdit(tester, picker: picked);
      await pickPhoto(tester);

      await tester.tap(find.byTooltip(AppStrings.authBack));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.profileEditDiscardLeave));
      await tester.pumpAndSettle();

      expect(photos.uploaded, isNull);
    });

    testWidgets('⚠️ 사진만 바꿔도 나갈 때 묻는다', (tester) async {
      // 안 물으면 고른 사진이 말없이 사라진다.
      await pumpEdit(tester, picker: picked);
      await pickPhoto(tester);

      await tester.tap(find.byTooltip(AppStrings.authBack));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileEditDiscardTitle), findsOneWidget);
    });

    testWidgets('⚠️ 기본 이미지로도 저장을 기다린다', (tester) async {
      await pumpEdit(tester, photoUrl: 'https://example.invalid/a.png');

      await openPhotoSheet(tester);
      await tester.tap(find.text(AppStrings.profilePhotoReset));
      await tester.pumpAndSettle();

      expect(photos.removed, isFalse, reason: '아직 저장을 누르지 않았다');
      expect(await saveOpens(tester), isTrue);
      expect(photos.removed, isTrue, reason: '저장을 눌렀으니 지워져야 한다');
    });

    testWidgets('⚠️ 앨범에서 취소하면 저장이 열리지 않는다', (tester) async {
      // 취소는 아무 일도 일어나지 않은 것이다.
      await pumpEdit(tester, picker: _FakePicker());

      await pickPhoto(tester);

      expect(await saveOpens(tester), isFalse);
    });

    testWidgets('⚠️ 올릴 수 없는 형식은 고르는 자리에서 말해준다', (tester) async {
      // 저장까지 기다렸다 말하면 **무엇 때문에 실패했는지** 멀어진다.
      await pumpEdit(
        tester,
        picker: _FakePicker(failure: ProfileImageFailure.unsupportedFormat),
      );

      await pickPhoto(tester);

      expect(find.text(AppStrings.profilePhotoUnsupported), findsOneWidget);
      expect(await saveOpens(tester), isFalse);
    });

    testWidgets('⚠️ 사진만 바꿨으면 프로필은 보내지 않는다', (tester) async {
      // 전부 `null` 인 `PATCH` 를 보내는 셈이다. 서버가 무엇을 할지 모르고,
      // 다른 기기에서 방금 바꾼 값을 덮을 수도 있다.
      await pumpEdit(tester, picker: picked);
      await pickPhoto(tester);

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(photos.uploaded, isNotNull, reason: '사진은 갔어야 한다');
      expect(repo.updated, isNull, reason: '보낼 프로필 값이 없다');
    });

    testWidgets('⚠️ 사진이 실패하면 나머지도 보내지 않는다', (tester) async {
      // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다. 화면에 남아
      // 다시 누르게 한다.
      await pumpEdit(
        tester,
        picker: picked,
        photoFails: ProfileImageFailure.network,
      );
      await pickPhoto(tester);
      await tester.enterText(introductionField, '오늘도 달린다');
      await tester.pumpAndSettle();

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.updated, isNull, reason: '사진이 실패했으면 멈춘다');
      expect(find.byType(ProfileEditPage), findsOneWidget);
    });
  });

  testWidgets('⚠️ 성별은 화면에 없다', (tester) async {
    // 기능정의서(SETTING-PERSONAL-001)가 **설정 UI 미노출**로 정했다.
    // 보이기만 하고 못 바꾸면 고장으로 읽힌다.
    await pumpEdit(tester);

    expect(find.text(AppStrings.profileGenderLabel), findsNothing);
    expect(find.text(AppStrings.profileGenderMale), findsNothing);
    expect(find.text(AppStrings.profileGenderFemale), findsNothing);
  });

  // ⚠️ **신체 정보는 설정으로 갔다**(2026-10-22 요청). 모르는 값 위에
  // 기본값을 쓰지 않는 규칙은 그대로이고, 그것을 지키는 테스트는
  // `settings_page_test.dart`의 같은 이름 묶음에 있다.

  testWidgets('⚠️ 화면 위의 뒤로가기 버튼으로 나갈 수 있다', (tester) async {
    // 다른 테스트는 전부 시스템 뒤로가기(`handlePopRoute`)를 쓴다.
    // **화면 위의 버튼은 아무도 눌러보지 않았다** — 아이콘을 v2 세트로
    // 갈아끼우면서 드러났다. 나가는 길이라 비워 둘 자리가 아니다.
    await pumpEdit(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsNothing);
  });

  testWidgets('바꾼 게 있는데 나가려 하면 묻는다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
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
