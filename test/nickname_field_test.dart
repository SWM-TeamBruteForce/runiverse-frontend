import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/presentation/nickname_field.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 닉네임 칸(명세 52번) — **무엇을 물어보고, 언제 보낼 수 있다고 말하는가.**
///
/// 화면 그림이 아니라 상태 전이를 본다. 여기서 잘못될 수 있는 것은 전부
/// "언제 서버에 묻는가"와 "언제 보낼 수 있다고 하는가"에 모여 있다.
///
/// ## ⚠️ 시트에서 내려온 테스트다
///
/// 2026-10-22까지는 시트였고 **거기서 즉시 저장**됐다. 지금은 편집 화면의
/// 저장 버튼이 보낸다 — 그래서 "버튼이 열린다"를 보던 자리가 전부
/// **[NicknameField.onReady]가 값을 주는가**로 바뀌었다. 묻는 규칙 자체는
/// 그대로다.
void main() {
  late FakeProfileRepository repo;

  /// 칸이 마지막으로 내놓은 값. `null`이면 **보낼 것이 없다**.
  String? ready;

  /// 칸을 띄운다. [current]가 지금 쓰는 이름이다.
  Future<void> pumpField(
    WidgetTester tester, {
    String? current = '별밤러너',
    bool? available = true,
    NicknameChangeFailure? submitFailure,
  }) async {
    ready = null;
    repo = FakeProfileRepository(nickname: current)..available = available;

    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: NicknameField(
              current: current,
              submitFailure: submitFailure,
              onReady: (value) => ready = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 이름을 고치고 **디바운스가 끝날 때까지** 기다린다.
  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  testWidgets('열면 지금 쓰는 이름이 채워져 있다', (tester) async {
    await pumpField(tester);

    // hint(`러너42`)와 겹치지 않는 이름을 쓴다.
    expect(find.text('별밤러너'), findsOneWidget);
  });

  testWidgets('⚠️ 지금 쓰는 이름 그대로면 서버에 묻지 않는다', (tester) async {
    await pumpField(tester);

    // 물으면 서버가 "이미 사용 중"이라고 답한다 — 쓰고 있는 사람이 본인이라
    // 그 답은 경고가 될 수 없는데, 화면에는 빨간 경고로 뜬다.
    await typeName(tester, '별밤러너');

    expect(repo.availabilityCalls, 0);
    expect(find.text(AppStrings.profileNicknameUnchanged), findsOneWidget);
    expect(ready, isNull);
  });

  testWidgets('이름을 바꾸면 묻고, 쓸 수 있으면 값을 내놓는다', (tester) async {
    await pumpField(tester);

    await typeName(tester, '완두콩');

    expect(repo.availabilityCalls, 1);
    expect(find.text(AppStrings.profileNicknameOk), findsOneWidget);
    expect(ready, '완두콩');
  });

  testWidgets('이미 누가 쓰는 이름이면 내놓지 않는다', (tester) async {
    await pumpField(tester, available: false);

    await typeName(tester, '완두콩');

    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
    expect(ready, isNull);
  });

  testWidgets('⚠️ 못 물어본 것과 이미 있는 것을 갈라 말한다', (tester) async {
    // 묶으면 네트워크가 잠깐 끊긴 것 때문에 쓸 수 있는 이름을 버리게 된다.
    await pumpField(tester, available: null);

    await typeName(tester, '완두콩');

    expect(find.text(AppStrings.profileNicknameCheckFailed), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
    expect(ready, isNull);
  });

  testWidgets('형식이 틀리면 서버에 묻지 않는다', (tester) async {
    await pumpField(tester);

    // 서버도 400으로 거절하는데, 그 400은 **앱 규칙이 서버와 어긋났다는
    // 신호**로만 써야 한다. 정상 경로에서 만들면 그 신호가 죽는다.
    await typeName(tester, '점 하나');

    expect(repo.availabilityCalls, 0);
    expect(find.text(AppStrings.profileNicknameInvalidChars), findsOneWidget);
    expect(ready, isNull);
  });

  testWidgets('⚠️ 묻는 중에는 아직 내놓지 않는다', (tester) async {
    // 형식을 통과했다고 바로 내놓으면, 서버가 "이미 있다"고 답하기 전에
    // 저장 버튼이 열린다 — 누르면 그때 겹쳐서 실패한다.
    await pumpField(tester);

    await tester.enterText(find.byType(TextField), '완두콩');
    await tester.pump();

    expect(find.text(AppStrings.profileNicknameCheckPending), findsOneWidget);
    expect(ready, isNull);

    // 디바운스를 재워 남은 타이머로 거부되지 않게 한다.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  });

  testWidgets('⚠️ 저장하다 겹쳤다고 하면 칸이 그렇게 말한다', (tester) async {
    // 묻고 누르는 사이에 남이 가져갈 수 있다. 고칠 곳이 이 칸이다.
    await pumpField(tester, submitFailure: NicknameChangeFailure.taken);

    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
  });

  testWidgets('⚠️ 겹침이 아닌 실패는 칸 아래 따로 선다', (tester) async {
    // helper 자리에 두면 **고칠 곳이 입력칸인 것처럼** 읽힌다.
    await pumpField(tester, submitFailure: NicknameChangeFailure.notOnboarded);

    expect(find.text(AppStrings.profileNicknameNotOnboarded), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
  });
}
