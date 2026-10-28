import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';

/// 친구 화면의 상태가 어떻게 옮겨 가는가.
///
/// ## ⚠️ 목록을 다시 읽지 않는 것이 규칙이다
///
/// 버튼을 누를 때마다 목록을 다시 받으면, 받은 요청을 수락한 순간 그 줄이
/// 사라졌다가 친구 묶음에 나타난다. 서버도 "다시 불러오지 말고 그 항목을 친구
/// 묶음 맨 위로 옮기라"고 권한다. 그래서 여기 테스트 대부분은 **repository를
/// 몇 번 불렀는가**를 함께 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FriendEntry e(String id, FriendRelation r) =>
      FriendEntry(userId: id, nickname: id, relation: r);

  /// 내 번호를 들고 있는 저장소. `load()` 가 이것으로 내 목록을 부른다.
  late InMemoryTokenStore tokens;

  setUp(() {
    tokens = InMemoryTokenStore();
  });

  Future<ProviderContainer> containerOf(FakeFriendRepository fake) async {
    await tokens.saveSession(
      userId: 'me',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        friendRepositoryProvider.overrideWithValue(fake),
      ],
    );
  }

  /// 디바운스가 끝나고 검색이 다녀올 때까지 기다린다.
  Future<void> settleSearch() =>
      Future<void>.delayed(const Duration(milliseconds: 700));

  group('첫 조회', () {
    test('내 목록을 받아 관계별로 묶는다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [
          e('r1', FriendRelation.requestReceived),
          e('s1', FriendRelation.requestSent),
          e('f1', FriendRelation.friend),
        ],
      );
      final container = await containerOf(fake);

      await container.read(friendProvider.notifier).load();

      final groups = container.read(friendProvider).groups;
      expect(groups.map((g) => g.relation), [
        FriendRelation.requestReceived,
        FriendRelation.requestSent,
        FriendRelation.friend,
      ]);
    });

    test('⚠️ 추천은 탭을 열 때 받는다', () async {
      // 들어오자마자 둘 다 부르면 쓰지도 않을 요청이 매번 나간다.
      final fake = FakeFriendRepository();
      final container = await containerOf(fake);

      await container.read(friendProvider.notifier).load();
      expect(fake.recommendationsCalls, 0);

      await container
          .read(friendProvider.notifier)
          .selectTab(FriendTab.recommendations);
      expect(fake.recommendationsCalls, 1);
    });

    test('실패하면 갈래를 들고 있는다', () async {
      final container = await containerOf(
        FakeFriendRepository(failure: FriendFailure.network),
      );

      await container.read(friendProvider.notifier).load();

      expect(container.read(friendProvider).failure, FriendFailure.network);
    });
  });

  group('검색', () {
    test('⚠️ 검색어가 들어가면 탭이 접힌다', () async {
      final container = await containerOf(FakeFriendRepository());
      await container.read(friendProvider.notifier).load();

      container.read(friendProvider.notifier).onQuery('동완');

      // 디바운스를 기다리지 않는다 — 탭은 글자를 치는 즉시 접혀야 한다.
      expect(container.read(friendProvider).searching, isTrue);
    });

    test('검색어를 지우면 탭이 돌아온다', () async {
      final container = await containerOf(FakeFriendRepository());
      await container.read(friendProvider.notifier).load();

      container.read(friendProvider.notifier).onQuery('동완');
      container.read(friendProvider.notifier).onQuery('');

      expect(container.read(friendProvider).searching, isFalse);
    });

    test('⚠️ 첫 검색은 20이다', () async {
      final fake = FakeFriendRepository(
        searchResults: [
          for (var i = 0; i < 30; i++) e('u$i', FriendRelation.none),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();

      expect(fake.searchLimits, [20]);
    });

    test('⚠️ 더 읽으면 같은 검색어로 50을 다시 받는다', () async {
      // 커서를 쓰지 않는다. 페이지를 넘기는 사이 닉네임을 바꾼 사람이 빠지거나
      // 두 번 오는 구간이 아예 없다.
      final fake = FakeFriendRepository(
        searchResults: [
          for (var i = 0; i < 60; i++) e('u$i', FriendRelation.none),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();

      await container.read(friendProvider.notifier).loadMoreSearch();

      expect(fake.searchLimits, [20, 50]);
      expect(fake.searchQueries, ['동완', '동완']);
    });

    test('⚠️ 50을 받은 뒤에는 더 읽지 않는다', () async {
      // 상한이다. 또 부르면 같은 요청이 계속 나간다.
      final fake = FakeFriendRepository(
        searchResults: [
          for (var i = 0; i < 60; i++) e('u$i', FriendRelation.none),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();
      await container.read(friendProvider.notifier).loadMoreSearch();

      await container.read(friendProvider.notifier).loadMoreSearch();

      expect(fake.searchLimits, [20, 50]);
    });

    test('⚠️ 20개를 다 못 채웠으면 더 읽지 않는다', () async {
      // 결과가 그게 전부다.
      final fake = FakeFriendRepository(
        searchResults: [
          for (var i = 0; i < 5; i++) e('u$i', FriendRelation.none),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();

      await container.read(friendProvider.notifier).loadMoreSearch();

      expect(fake.searchLimits, [20]);
    });

    test('검색 결과는 이미 맺은 것이 위다', () async {
      final fake = FakeFriendRepository(
        searchResults: [
          e('a', FriendRelation.none),
          e('b', FriendRelation.friend),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();

      expect(
        container.read(friendProvider).groups.first.relation,
        FriendRelation.friend,
      );
    });
  });

  group('버튼을 누른 뒤', () {
    test('⚠️ 목록을 다시 읽지 않고 그 줄만 바꾼다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).accept('r1');

      expect(fake.friendsCalls, 1, reason: '첫 조회 한 번뿐이다');
      expect(
        container.read(friendProvider).groups.single.relation,
        FriendRelation.friend,
      );
    });

    test('⚠️ 수락한 사람은 친구 묶음 맨 위로 간다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [
          e('r1', FriendRelation.requestReceived),
          e('f1', FriendRelation.friend),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).accept('r1');

      final friends = container.read(friendProvider).groups.single.entries;
      expect(friends.map((x) => x.userId), ['r1', 'f1']);
    });

    test('거절하면 목록에서 빠진다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).cancel('r1');

      expect(container.read(friendProvider).groups, isEmpty);
    });

    test('친구를 끊으면 목록에서 빠진다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('f1', FriendRelation.friend)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).remove('f1');

      expect(container.read(friendProvider).groups, isEmpty);
    });

    test('⚠️ 이미 처리된 요청(404)이면 그 줄을 NONE 으로 되돌린다', () async {
      // 취소·거절·삭제는 멱등이 아니다. 내가 수락을 누르는 사이 상대가 요청을
      // 취소했으면 404 가 온다 — 그 줄을 그대로 두면 눌러도 계속 404 다.
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
        failure: FriendFailure.notFound,
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).accept('r1');

      expect(container.read(friendProvider).groups, isEmpty);
      // ⚠️ **조회 실패와 가른 자리다.** 404로 그 줄이 빠지면 묶음이 비는데,
      // 하나로 두면 "불러오지 못했어요" 화면이 떠서 멀쩡히 받아 둔 목록을
      // 못 받은 것처럼 보이게 된다.
      expect(
        container.read(friendProvider).actionFailure,
        FriendFailure.notFound,
      );
      expect(container.read(friendProvider).failure, isNull);
    });

    test('⚠️ 같은 줄을 연달아 눌러도 요청은 한 번만 나간다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await Future.wait([
        container.read(friendProvider.notifier).accept('r1'),
        container.read(friendProvider.notifier).accept('r1'),
      ]);

      expect(fake.accepted, ['r1']);
    });

    test('추천에서 요청하면 요청됨이 된다', () async {
      final fake = FakeFriendRepository(
        recommended: [
          FriendRecommendation(
            entry: e('u1', FriendRelation.none),
            reason: FriendReason.ranTogether,
          ),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      await container
          .read(friendProvider.notifier)
          .selectTab(FriendTab.recommendations);

      await container.read(friendProvider.notifier).request('u1');

      expect(
        container.read(friendProvider).recommendations.single.entry.relation,
        FriendRelation.requestSent,
      );
    });
  });

  group('프로필로 돌아갈 때', () {
    test('관계를 바꾸면 changed 가 참이 된다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).accept('r1');

      expect(container.read(friendProvider).changed, isTrue);
    });

    test('⚠️ 아무것도 안 바꾸면 거짓이다', () async {
      // 참이면 프로필이 친구 수를 다시 읽는다. 들여다보기만 한 사람에게까지
      // 요청을 보낼 이유가 없다.
      final container = await containerOf(FakeFriendRepository());
      await container.read(friendProvider.notifier).load();

      expect(container.read(friendProvider).changed, isFalse);
    });

    test('받은 요청 수를 센다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [
          e('r1', FriendRelation.requestReceived),
          e('r2', FriendRelation.requestReceived),
          e('f1', FriendRelation.friend),
        ],
      );
      final container = await containerOf(fake);

      await container.read(friendProvider.notifier).load();

      expect(container.read(friendProvider).receivedCount, 2);
    });
  });
}
