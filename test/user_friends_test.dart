import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/profile/presentation/user_friends_page.dart';

/// 남의 친구 목록.
///
/// ## ⚠️ 내 목록과 다른 점 셋
///
/// - **친구만 담긴다.** 누구에게 요청했고 누가 요청했는지는 본인만 안다.
///   그래서 묶음 머리글도 탭도 없다.
/// - **`relationshipType`은 나와 그 사람의 관계다.** 목록 주인과의 관계가
///   아니다 — 모르는 사람이면 `NONE`이라 "친구 요청" 버튼이 선다.
/// - **내가 그 목록에 있을 수 있다.** 그 줄의 관계는 `null`이고 버튼이 없다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FriendEntry e(String id, FriendRelation? r) =>
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
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const UserFriendsPage(userId: 'u1', nickname: '이서연'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('그 사람의 친구를 보여 준다', (tester) async {
    await pump(
      tester,
      FakeFriendRepository(
        friendEntries: [
          e('철수', FriendRelation.friend),
          e('영희', FriendRelation.none),
        ],
      ),
    );

    expect(find.text('철수'), findsOneWidget);
    expect(find.text('영희'), findsOneWidget);
  });

  testWidgets('⚠️ 묶음 머리글도 탭도 없다', (tester) async {
    // 친구만 담기므로 가를 것이 없다.
    await pump(
      tester,
      FakeFriendRepository(friendEntries: [e('철수', FriendRelation.friend)]),
    );

    expect(find.text(AppStrings.friendSectionFriends), findsNothing);
    expect(find.text(AppStrings.friendTabRecommendations), findsNothing);
  });

  testWidgets('⚠️ 모르는 사람에게는 친구 요청 버튼이 선다', (tester) async {
    // 관계는 목록 주인이 아니라 **나와 그 사람** 사이다.
    await pump(
      tester,
      FakeFriendRepository(friendEntries: [e('영희', FriendRelation.none)]),
    );

    expect(find.text(AppStrings.friendRequest), findsOneWidget);
  });

  testWidgets('⚠️ 목록에 내가 있으면 버튼을 안 그린다', (tester) async {
    // 서버가 그 줄의 관계를 `null` 로 준다. 그려도 누를 수 없고, 눌리면
    // 자기 자신에게 요청하는 400 이다.
    await pump(tester, FakeFriendRepository(friendEntries: [e('바로나', null)]));

    // ⚠️ 아바타가 첫 글자를 그린다. 닉네임과 겹치지 않는 이름을 쓴다.
    expect(find.text('바로나'), findsOneWidget);
    expect(find.text(AppStrings.friendRequest), findsNothing);
  });

  testWidgets('목록 주인 이름이 제목에 있다', (tester) async {
    await pump(tester, FakeFriendRepository());

    expect(find.text(AppStrings.userFriendsTitle('이서연')), findsOneWidget);
  });

  testWidgets('아무도 없으면 말해 준다', (tester) async {
    await pump(tester, FakeFriendRepository());

    expect(find.text(AppStrings.userFriendsEmpty('이서연')), findsOneWidget);
  });

  testWidgets('⚠️ 못 받았을 때 "친구가 없다"고 하지 않는다', (tester) async {
    await pump(tester, FakeFriendRepository(failure: FriendFailure.network));

    expect(find.text(AppStrings.userFriendsEmpty('이서연')), findsNothing);
    expect(find.text(AppStrings.friendLoadFailed), findsOneWidget);
  });
}
