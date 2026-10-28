import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';
import 'package:runiverse/features/friend/presentation/friend_page.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';

/// 친구 화면이 무엇을 보여 주는가.
///
/// ## ⚠️ 버튼이 틀리면 기능이 틀린다
///
/// 관계마다 할 수 있는 일이 다르고, 서버는 엉뚱한 호출에 `404`·`409`로만
/// 답한다. 화면이 맞는 버튼을 그리는 것이 이 기능의 절반이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FriendEntry e(String id, FriendRelation r) =>
      FriendEntry(userId: id, nickname: id, relation: r);

  Future<void> pump(WidgetTester tester, FakeFriendRepository fake) async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'me',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          friendRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const FriendPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('관계마다 다른 버튼이 선다', (tester) async {
    await pump(
      tester,
      FakeFriendRepository(
        friendEntries: [
          e('받은', FriendRelation.requestReceived),
          e('보낸', FriendRelation.requestSent),
          e('친한', FriendRelation.friend),
        ],
      ),
    );

    expect(find.text(AppStrings.friendAccept), findsOneWidget);
    expect(find.text(AppStrings.friendReject), findsOneWidget);
    expect(find.text(AppStrings.friendCancel), findsOneWidget);
    // 친구 줄은 ⋯ 뒤에 숨는다 — 되돌릴 수 없는 동작이 목록에 그대로 노출되면
    // 손이 스친다.
    expect(find.text(AppStrings.friendRemove), findsNothing);
  });

  testWidgets('묶음 머리글이 선다', (tester) async {
    await pump(
      tester,
      FakeFriendRepository(
        friendEntries: [e('받은', FriendRelation.requestReceived)],
      ),
    );

    expect(find.text(AppStrings.friendSectionReceived), findsOneWidget);
  });

  testWidgets('⚠️ 검색하면 탭이 사라지고 결과만 남는다', (tester) async {
    await pump(
      tester,
      FakeFriendRepository(
        friendEntries: [e('친한', FriendRelation.friend)],
        searchResults: [e('동완', FriendRelation.none)],
      ),
    );
    expect(find.text(AppStrings.friendTabRecommendations), findsOneWidget);

    await tester.enterText(find.byType(TextField), '동완');
    await tester.pump();

    expect(find.text(AppStrings.friendTabRecommendations), findsNothing);
  });

  testWidgets('⚠️ 추천 탭에는 친구 요청 하나뿐이다', (tester) async {
    // 서버가 친구·요청이 오간 사람을 빼고 준다. 고를 것이 없다.
    await pump(
      tester,
      FakeFriendRepository(
        recommended: [
          FriendRecommendation(
            entry: e('철수', FriendRelation.none),
            reason: FriendReason.ranTogether,
          ),
        ],
      ),
    );

    await tester.tap(find.text(AppStrings.friendTabRecommendations));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.friendRequest), findsOneWidget);
    expect(find.text(AppStrings.friendAccept), findsNothing);
    expect(find.text(AppStrings.friendCancel), findsNothing);
  });

  testWidgets('추천 이유를 문구로 보여 준다', (tester) async {
    await pump(
      tester,
      FakeFriendRepository(
        recommended: [
          FriendRecommendation(
            entry: e('철수', FriendRelation.none),
            reason: FriendReason.ranTogether,
          ),
          FriendRecommendation(
            entry: e('민수', FriendRelation.none),
            reason: FriendReason.similarPace,
          ),
        ],
      ),
    );

    await tester.tap(find.text(AppStrings.friendTabRecommendations));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.friendReasonRanTogether), findsOneWidget);
    expect(find.text(AppStrings.friendReasonSimilarPace), findsOneWidget);
  });

  testWidgets('⚠️ 친구 삭제는 확인을 묻는다', (tester) async {
    // 되돌릴 수 없다. 한 번의 탭으로 끝나면 안 된다.
    final fake = FakeFriendRepository(
      friendEntries: [e('친한', FriendRelation.friend)],
    );
    await pump(tester, fake);

    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.friendRemove));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.friendRemoveConfirmTitle), findsOneWidget);
    expect(fake.removed, isEmpty, reason: '아직 안 끊었다');
  });

  testWidgets('수락을 누르면 서버로 간다', (tester) async {
    final fake = FakeFriendRepository(
      friendEntries: [e('받은', FriendRelation.requestReceived)],
    );
    await pump(tester, fake);

    await tester.tap(find.text(AppStrings.friendAccept));
    await tester.pumpAndSettle();

    expect(fake.accepted, ['받은']);
  });

  group('빈 상태', () {
    testWidgets('친구가 없으면 말해 준다', (tester) async {
      await pump(tester, FakeFriendRepository());

      expect(find.text(AppStrings.friendEmptyFriends), findsOneWidget);
    });

    testWidgets('추천이 없으면 다른 말을 한다', (tester) async {
      await pump(tester, FakeFriendRepository());

      await tester.tap(find.text(AppStrings.friendTabRecommendations));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.friendEmptyRecommendations), findsOneWidget);
    });

    testWidgets('⚠️ 검색 결과가 없으면 검색어를 되비춘다', (tester) async {
      // "결과가 없어요"만 있으면 무엇으로 찾았는지 알 수 없다.
      await pump(tester, FakeFriendRepository());

      await tester.enterText(find.byType(TextField), '없는이름');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.friendEmptySearch('없는이름')), findsOneWidget);
    });
  });

  group('⚠️ 실패를 화면이 말한다', () {
    testWidgets('못 받았을 때 "친구가 없다"고 하지 않는다', (tester) async {
      // 터널이 끊기면 load() 가 실패하는데, 그대로 두면 친구 40명인 사람에게
      // "아직 친구가 없어요"가 뜬다. 없는 것과 못 받은 것은 다른 일이다.
      await pump(tester, FakeFriendRepository(failure: FriendFailure.network));

      expect(find.text(AppStrings.friendEmptyFriends), findsNothing);
      expect(find.text(AppStrings.friendLoadFailed), findsOneWidget);
    });

    testWidgets('다시 받아볼 수 있다', (tester) async {
      await pump(tester, FakeFriendRepository(failure: FriendFailure.network));

      expect(find.text(AppStrings.friendRetry), findsOneWidget);
    });

    testWidgets('⚠️ 검색이 실패해도 "없다"고 하지 않는다', (tester) async {
      await pump(tester, FakeFriendRepository(failure: FriendFailure.network));

      await tester.enterText(find.byType(TextField), '김');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.friendEmptySearch('김')), findsNothing);
    });

    testWidgets('⚠️ 이미 처리된 요청이면 그렇다고 말한다', (tester) async {
      // 404 다. 내가 수락을 누르는 사이 상대가 취소했다. 아무 말도 없으면
      // 눌러도 안 되는 버튼으로 보인다.
      await pump(
        tester,
        FakeFriendRepository(
          friendEntries: [e('받은', FriendRelation.requestReceived)],
          actionFailure: FriendFailure.notFound,
        ),
      );

      await tester.tap(find.text(AppStrings.friendAccept));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.friendGone), findsOneWidget);
    });
  });

  group('⚠️ 검색창', () {
    testWidgets('글자를 치면 ✕ 가 나타난다', (tester) async {
      // 지우는 길이 없으면 백스페이스로 지워야 한다.
      await pump(tester, FakeFriendRepository());
      expect(find.byIcon(LucideIcons.x), findsNothing);

      await tester.enterText(find.byType(TextField), '김');
      await tester.pump();

      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('⚠️ 다시 들어오면 검색어가 없다', (tester) async {
      // provider 가 살아 있어 지난 검색어가 남는다. 입력창은 비어 있는데
      // 목록만 걸러져 있으면 왜 이것만 보이는지 알 수 없다.
      await pump(tester, FakeFriendRepository());
      await tester.enterText(find.byType(TextField), '김');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // 화면을 다시 세운다. push·pop 처럼 State 가 새로 서야 한다.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, FakeFriendRepository());

      expect(find.text(AppStrings.friendTabRecommendations), findsOneWidget);
    });
  });

  testWidgets('⚠️ 추천에서 요청을 보내면 요청됨이 된다', (tester) async {
    // "요청 취소"가 뜨면 취소하려다 눌리지 않아 고장으로 읽힌다.
    await pump(
      tester,
      FakeFriendRepository(
        recommended: [
          FriendRecommendation(
            entry: e('철수', FriendRelation.none),
            reason: FriendReason.ranTogether,
          ),
        ],
      ),
    );
    await tester.tap(find.text(AppStrings.friendTabRecommendations));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.friendRequest));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.friendRequested), findsOneWidget);
    expect(find.text(AppStrings.friendCancel), findsNothing);
  });
}
