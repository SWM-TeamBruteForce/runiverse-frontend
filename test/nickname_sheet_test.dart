import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/presentation/nickname_sheet.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 닉네임 변경 시트(명세 52번) — **무엇을 물어보고, 언제 잠기는가.**
///
/// 화면 그림이 아니라 상태 전이를 본다. 이 시트에서 잘못될 수 있는 것은
/// 전부 "언제 서버에 묻는가"와 "언제 버튼이 열리는가"에 모여 있다.
void main() {
  late FakeProfileRepository repo;
  late InMemoryTokenStore store;

  /// 시트를 띄운다. [current]가 지금 쓰는 이름이다.
  Future<void> pumpSheet(
    WidgetTester tester, {
    String? current = '별밤러너',
    bool? available = true,
    NicknameChangeFailure? changeFails,
  }) async {
    repo = FakeProfileRepository(
      nickname: current,
      nicknameFailure: changeFails,
    )..available = available;

    store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    await store.saveCurrentUser(
      userId: 'u-1',
      isOnboarded: true,
      nickname: current,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNicknameSheet(context, current: current),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  /// 이름을 고치고 **디바운스가 끝날 때까지** 기다린다.
  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Finder submitButton() => find.text(AppStrings.profileNicknameChangeSubmit);

  /// `AppButton`은 `Material` + `InkWell`이라 `ElevatedButton`이 아니다.
  /// 잠겼는지는 **위젯이 받은 콜백**으로 본다.
  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<AppButton>(
            find.widgetWithText(
              AppButton,
              AppStrings.profileNicknameChangeSubmit,
            ),
          )
          .onPressed !=
      null;

  testWidgets('열면 지금 쓰는 이름이 채워져 있다', (tester) async {
    await pumpSheet(tester);

    // hint(`러너42`)와 겹치지 않는 이름을 쓴다.
    expect(find.text('별밤러너'), findsOneWidget);
  });

  testWidgets('⚠️ 지금 쓰는 이름 그대로면 서버에 묻지 않는다', (tester) async {
    await pumpSheet(tester);

    // 물으면 서버가 "이미 사용 중"이라고 답한다 — 쓰고 있는 사람이 본인이라
    // 그 답은 경고가 될 수 없는데, 화면에는 빨간 경고로 뜬다.
    await typeName(tester, '별밤러너');

    expect(repo.availabilityCalls, 0);
    expect(find.text(AppStrings.profileNicknameUnchanged), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('이름을 바꾸면 묻고, 쓸 수 있으면 버튼이 열린다', (tester) async {
    await pumpSheet(tester);

    await typeName(tester, '완두콩');

    expect(repo.availabilityCalls, 1);
    expect(find.text(AppStrings.profileNicknameOk), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('이미 누가 쓰는 이름이면 버튼이 잠긴다', (tester) async {
    await pumpSheet(tester, available: false);

    await typeName(tester, '완두콩');

    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('⚠️ 못 물어본 것과 이미 있는 것을 갈라 말한다', (tester) async {
    // 묶으면 네트워크가 잠깐 끊긴 것 때문에 쓸 수 있는 이름을 버리게 된다.
    await pumpSheet(tester, available: null);

    await typeName(tester, '완두콩');

    expect(find.text(AppStrings.profileNicknameCheckFailed), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
  });

  testWidgets('형식이 틀리면 서버에 묻지 않는다', (tester) async {
    await pumpSheet(tester);

    // 서버도 400으로 거절하는데, 그 400은 **앱 규칙이 서버와 어긋났다는
    // 신호**로만 써야 한다. 정상 경로에서 만들면 그 신호가 죽는다.
    await typeName(tester, '점 하나');

    expect(repo.availabilityCalls, 0);
    expect(find.text(AppStrings.profileNicknameInvalidChars), findsOneWidget);
  });

  testWidgets('바꾸면 시트가 닫히고 서버에 보낸 이름이 남는다', (tester) async {
    await pumpSheet(tester);

    await typeName(tester, '완두콩');
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(repo.changedTo, '완두콩');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('⚠️ 겹친다고 하면 시트를 닫지 않는다', (tester) async {
    // 고칠 곳이 이 시트의 입력칸이다. 닫으면 다시 열어 처음부터 쳐야 한다.
    await pumpSheet(tester, changeFails: NicknameChangeFailure.taken);

    await typeName(tester, '완두콩');
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
  });

  testWidgets('온보딩을 안 마쳤다고 하면 닫는다 — 여기서 할 수 있는 일이 없다', (tester) async {
    await pumpSheet(tester, changeFails: NicknameChangeFailure.notOnboarded);

    await typeName(tester, '완두콩');
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });
}
