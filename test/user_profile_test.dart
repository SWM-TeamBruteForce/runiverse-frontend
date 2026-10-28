import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/data/http_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/profile/presentation/user_profile_page.dart';

/// 남의 프로필.
///
/// ## ⚠️ 프로필 API는 관계를 다른 말로 준다
///
/// 친구 엔드포인트는 `relationshipType`인데 여기는 `friendStatus`이고 값도
/// 다르다(`ACCEPTED` 대 `FRIEND`). 이걸 빠뜨리면 **친구인 사람에게 "친구
/// 요청" 버튼이 뜨고**, 눌러 봐야 `409`만 돌아온다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('응답 읽기', () {
    test('⚠️ friendStatus 를 관계로 읽는다', () {
      ProfileSummary of(String? status) => HttpProfileRepository.summaryOf({
        'userId': 'u1',
        'nickname': '이서연',
        'friendCount': 38,
        'isMe': false,
        'friendStatus': status,
      });

      expect(of('ACCEPTED').relation, FriendRelation.friend);
      expect(of('PENDING_SENT').relation, FriendRelation.requestSent);
      expect(of('PENDING_RECEIVED').relation, FriendRelation.requestReceived);
      expect(of('NONE').relation, FriendRelation.none);
    });

    test('내 프로필이면 관계가 null 이다', () {
      final summary = HttpProfileRepository.summaryOf({
        'userId': 'me',
        'nickname': '나',
        'friendCount': 12,
        'isMe': true,
        'friendStatus': null,
      });

      expect(summary.isMe, isTrue);
      expect(summary.relation, isNull);
    });

    test('isMe 가 없으면 거짓으로 둔다', () {
      // 없다고 내 프로필로 읽으면 남의 화면에 "프로필 편집"이 뜬다.
      final summary = HttpProfileRepository.summaryOf({
        'userId': 'u1',
        'friendCount': 0,
      });

      expect(summary.isMe, isFalse);
    });
  });

  group('화면', () {
    Future<void> pump(
      WidgetTester tester, {
      required FriendRelation? relation,
      FakeFriendRepository? friends,
    }) async {
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
            friendRepositoryProvider.overrideWithValue(
              friends ?? FakeFriendRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              FakeProfileRepository(
                nickname: '이서연',
                friendCount: 38,
                relation: relation,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const UserProfilePage(userId: 'u1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('관계에 따라 버튼이 바뀐다 — 아직 아무 사이도 아니다', (tester) async {
      await pump(tester, relation: FriendRelation.none);

      expect(find.text(AppStrings.friendRequest), findsOneWidget);
    });

    testWidgets('⚠️ 이미 친구면 요청 버튼이 없다', (tester) async {
      await pump(tester, relation: FriendRelation.friend);

      expect(find.text(AppStrings.friendRequest), findsNothing);
      expect(find.text(AppStrings.friendSectionFriends), findsWidgets);
    });

    testWidgets('받은 요청이면 수락·거절이 선다', (tester) async {
      await pump(tester, relation: FriendRelation.requestReceived);

      expect(find.text(AppStrings.friendAccept), findsOneWidget);
      expect(find.text(AppStrings.friendReject), findsOneWidget);
    });

    testWidgets('보낸 요청이면 취소가 선다', (tester) async {
      await pump(tester, relation: FriendRelation.requestSent);

      expect(find.text(AppStrings.friendCancel), findsOneWidget);
    });

    testWidgets('친구 수를 보여 준다', (tester) async {
      await pump(tester, relation: FriendRelation.none);

      expect(find.text(AppStrings.friendProfileEntry(38)), findsOneWidget);
    });

    testWidgets('요청을 누르면 서버로 간다', (tester) async {
      final friends = FakeFriendRepository();
      await pump(tester, relation: FriendRelation.none, friends: friends);

      await tester.tap(find.text(AppStrings.friendRequest));
      await tester.pumpAndSettle();

      expect(friends.requested, ['u1']);
    });
  });
}
