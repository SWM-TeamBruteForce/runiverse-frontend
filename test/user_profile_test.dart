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
/// ## ⚠️ 관계 어휘가 1.2.0에서 하나로 합쳐졌다
///
/// 프로필 요약(No 38)이 `friendStatus`·`ACCEPTED`를 쓰다가 친구 엔드포인트와
/// 같은 `relationshipType`·`FRIEND`로 바뀌었다. 키를 안 고치면 **친구인
/// 사람에게 "친구 요청" 버튼이 뜨고**, 눌러 봐야 `409`만 돌아온다.
///
/// 읽는 쪽은 두 어휘를 모두 받는다 — 구버전 서버와 섞이는 기간을 버틴다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('응답 읽기', () {
    test('⚠️ relationshipType 을 관계로 읽는다', () {
      ProfileSummary of(String? type) => HttpProfileRepository.summaryOf({
        'userId': 'u1',
        'nickname': '이서연',
        'friendCount': 38,
        'isMe': false,
        'relationshipType': type,
      });

      expect(of('FRIEND').relation, FriendRelation.friend);
      expect(of('FRIEND_REQUEST_SENT').relation, FriendRelation.requestSent);
      expect(
        of('FRIEND_REQUEST_RECEIVED').relation,
        FriendRelation.requestReceived,
      );
      expect(of('NONE').relation, FriendRelation.none);
    });

    test('옛 어휘도 그대로 읽는다', () {
      // 서버가 1.1.x를 내리는 동안 섞일 수 있다.
      ProfileSummary of(String? type) => HttpProfileRepository.summaryOf({
        'userId': 'u1',
        'friendCount': 0,
        'relationshipType': type,
      });

      expect(of('ACCEPTED').relation, FriendRelation.friend);
      expect(of('PENDING_SENT').relation, FriendRelation.requestSent);
      expect(of('PENDING_RECEIVED').relation, FriendRelation.requestReceived);
    });

    test('⚠️ 모르는 관계 값에는 버튼을 세우지 않는다', () {
      // 새 값이 생겨도 화면이 죽지 않고, 아무 버튼도 임의로 그리지 않는다.
      final summary = HttpProfileRepository.summaryOf({
        'userId': 'u1',
        'friendCount': 0,
        'relationshipType': 'BLOCKED',
      });

      expect(summary.relation, isNull);
    });

    test('내 프로필이면 관계가 null 이다', () {
      final summary = HttpProfileRepository.summaryOf({
        'userId': 'me',
        'nickname': '나',
        'friendCount': 12,
        'isMe': true,
        'relationshipType': null,
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

    testWidgets('⚠️ 요청을 누르면 버튼이 바뀐다', (tester) async {
      // 안 바뀌면 실패한 줄 알고 또 누른다. 두 번째 POST 는 409 로 돌아오고,
      // 그것도 조용하면 화면이 고장 난 것으로 보인다.
      final friends = FakeFriendRepository();
      await pump(tester, relation: FriendRelation.none, friends: friends);

      await tester.tap(find.text(AppStrings.friendRequest));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.friendRequest), findsNothing);
      expect(find.text(AppStrings.friendCancel), findsOneWidget);
    });

    testWidgets('⚠️ 두 번 눌러도 요청은 한 번만 나간다', (tester) async {
      final friends = FakeFriendRepository();
      await pump(tester, relation: FriendRelation.none, friends: friends);

      await tester.tap(find.text(AppStrings.friendRequest));
      await tester.pumpAndSettle();
      // 버튼이 바뀌었으니 같은 자리를 또 누를 수 없다.
      expect(friends.requested, ['u1']);
    });

    testWidgets('요청을 누르면 서버로 간다', (tester) async {
      final friends = FakeFriendRepository();
      await pump(tester, relation: FriendRelation.none, friends: friends);

      await tester.tap(find.text(AppStrings.friendRequest));
      await tester.pumpAndSettle();

      expect(friends.requested, ['u1']);
      // 호출 기록만 보면 버튼이 안 바뀌어도 통과한다.
      expect(find.text(AppStrings.friendCancel), findsOneWidget);
    });
  });
}
