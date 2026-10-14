import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
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
  late FakeProfileImageRepository photos;

  Future<void> pumpEdit(
    WidgetTester tester, {
    String? nickname = '별밤러너',
    String? introduction,
    ProfileEditFailure? editFails,
    String? photoUrl,
    ProfileImageFailure? photoFails,
    PhotoPicker? picker,
  }) async {
    repo = FakeProfileRepository(
      nickname: nickname,
      introduction: introduction,
      profileImageUrl: photoUrl,
      editFailure: editFails,
    );
    photos = FakeProfileImageRepository(
      latency: Duration.zero,
      url: photoUrl,
      failWith: photoFails,
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
          // ⚠️ 앨범을 여는 것은 플랫폼 채널이라 테스트에 없다.
          photoPickerProvider.overrideWithValue(picker ?? _FakePicker()),
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
    return repo.updated != null || photos.uploaded != null || photos.removed;
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

  testWidgets('⚠️ 못 불러온 값은 채우라고 하지 않고 —로 둔다', (tester) async {
    // 서버에 값이 없는 게 아니라 **불러올 API가 없는 것**이다. 온보딩에서
    // 이미 넣은 값이라 "설정하기"는 틀린 말이 된다.
    await pumpEdit(tester);

    expect(find.text(AppStrings.profileEditUnknown), findsWidgets);
  });

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
