import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_list.dart';
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

  group('⚠️ 친구 목록 이어 읽기', () {
    test('커서가 있으면 더 읽어 뒤에 붙인다', () async {
      // 21번째 친구부터 영영 못 보면 목록이 아니다.
      final fake = FakeFriendRepository(
        friendEntries: [e('f1', FriendRelation.friend)],
        nextCursor: 'c1',
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).loadMoreFriends();

      expect(fake.friendsCalls, 2);
      expect(fake.cursors, [null, 'c1']);
      expect(container.read(friendProvider).friends, hasLength(2));
    });

    test('⚠️ 커서가 없으면 더 읽지 않는다', () async {
      // 마지막 장이다. 또 부르면 같은 요청이 계속 나간다.
      final fake = FakeFriendRepository(
        friendEntries: [e('f1', FriendRelation.friend)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await container.read(friendProvider.notifier).loadMoreFriends();

      expect(fake.friendsCalls, 1);
    });

    test('⚠️ 다녀오는 중이면 또 부르지 않는다', () async {
      // 스크롤 알림마다 불리는 자리다. 막지 않으면 같은 요청이 수십 개 나간다.
      final fake = FakeFriendRepository(
        friendEntries: [e('f1', FriendRelation.friend)],
        nextCursor: 'c1',
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();

      await Future.wait([
        container.read(friendProvider.notifier).loadMoreFriends(),
        container.read(friendProvider.notifier).loadMoreFriends(),
      ]);

      expect(fake.friendsCalls, 2, reason: '첫 조회 + 더 읽기 한 번');
    });

    test('⚠️ 검색 중에는 친구 목록을 더 읽지 않는다', () async {
      final fake = FakeFriendRepository(
        friendEntries: [e('f1', FriendRelation.friend)],
        nextCursor: 'c1',
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      container.read(friendProvider.notifier).onQuery('김');

      await container.read(friendProvider.notifier).loadMoreFriends();

      expect(fake.friendsCalls, 1);
    });

    test('⚠️ 검색 더 읽기도 다녀오는 중이면 막는다', () async {
      final fake = FakeFriendRepository(
        searchResults: [
          for (var i = 0; i < 60; i++) e('u$i', FriendRelation.none),
        ],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      container.read(friendProvider.notifier).onQuery('동완');
      await settleSearch();

      await Future.wait([
        container.read(friendProvider.notifier).loadMoreSearch(),
        container.read(friendProvider.notifier).loadMoreSearch(),
      ]);

      expect(fake.searchLimits, [20, 50]);
    });
  });

  group('⚠️ 다녀온 뒤', () {
    test('프로필이 읽고 나면 changed 를 지운다', () async {
      // 안 지우면 한 번 바꾼 뒤로는 들여다보기만 해도 매번 다시 읽는다.
      final fake = FakeFriendRepository(
        friendEntries: [e('r1', FriendRelation.requestReceived)],
      );
      final container = await containerOf(fake);
      await container.read(friendProvider.notifier).load();
      await container.read(friendProvider.notifier).accept('r1');
      expect(container.read(friendProvider).changed, isTrue);

      container.read(friendProvider.notifier).clearChanged();

      expect(container.read(friendProvider).changed, isFalse);
    });
  });

  group('⚠️ 앱을 끄지 않고 계정을 바꾸면', () {
    // 이 provider는 로그아웃해도 살아 있다. 추천은 처음 열 때만 받으므로 그대로
    // 두면 다음 사람에게 앞 사람의 추천(이유 문구까지)이 보이고, 그 사람 자신이
    // 섞이면 요청이 거절된다.
    late _AccountFriends friends;
    late _Auth auth;

    /// u-1로 로그인한 상태. 친구 provider를 세워 계정을 듣게 한다.
    Future<ProviderContainer> signedIn() async {
      await tokens.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      friends = _AccountFriends();
      final container = ProviderContainer.test(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          friendRepositoryProvider.overrideWithValue(friends),
          authControllerProvider.overrideWith(
            () => _Auth(const AuthSignedIn('u-1', isOnboarded: true)),
          ),
        ],
      );
      auth = container.read(authControllerProvider.notifier) as _Auth;
      container.read(friendProvider);
      return container;
    }

    /// 로그아웃하고 [userId]로 들어온다.
    Future<void> switchTo(String userId) async {
      auth.set(const AuthSignedOut(returning: true));
      friends.owner = userId;
      await tokens.saveSession(
        userId: userId,
        accessToken: 'a-$userId',
        refreshToken: 'r-$userId',
        isOnboarded: true,
      );
      auth.set(AuthSignedIn(userId, isOnboarded: true));
    }

    List<String> idsOf(Iterable<FriendEntry> entries) => [
      for (final entry in entries) entry.userId,
    ];

    List<String> recommendedIds(ProviderContainer container) => idsOf(
      container.read(friendProvider).recommendations.map((item) => item.entry),
    );

    test('받아 둔 친구·추천을 버리고, 추천 탭을 다시 열면 새로 받는다', () async {
      final container = await signedIn();
      final notifier = container.read(friendProvider.notifier);
      await notifier.load();
      await notifier.selectTab(FriendTab.recommendations);

      await switchTo('u-2');

      final cleared = container.read(friendProvider);
      expect(cleared.friends, isEmpty);
      expect(cleared.recommendations, isEmpty, reason: '앞 사람의 추천이 남았다');
      expect(cleared.tab, FriendTab.friends);

      await notifier.load();
      await notifier.selectTab(FriendTab.recommendations);

      expect(idsOf(container.read(friendProvider).friends), ['u-2-friend']);
      expect(recommendedIds(container), ['u-2-pick']);
      expect(friends.recommendationsCalls, 2);
    });

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 떠난 조회가 늦게 ${fails ? '실패해도' : '와도'} 새 계정 화면을 덮지 않는다',
        () async {
          final container = await signedIn();
          final notifier = container.read(friendProvider.notifier);
          final held = friends.hold = Completer<void>();
          final stale = [
            notifier.load(),
            notifier.selectTab(FriendTab.recommendations),
          ];
          await pumpEventQueue();
          friends.hold = null;

          await switchTo('u-2');
          await notifier.load();
          await notifier.selectTab(FriendTab.recommendations);
          friends.fails = fails;
          held.complete();
          await Future.wait(stale);

          final state = container.read(friendProvider);
          expect(idsOf(state.friends), ['u-2-friend']);
          expect(recommendedIds(container), ['u-2-pick']);
          expect(state.failure, isNull, reason: '앞 사람의 실패가 새 계정 화면에 떴다');
          expect(state.loading, isFalse);
        },
      );
    }

    test('검색을 미루는 사이 바뀌면 그 검색은 나가지 않는다', () async {
      final container = await signedIn();
      container.read(friendProvider.notifier).onQuery('김');

      await switchTo('u-2');
      await settleSearch();

      expect(friends.searchQueries, isEmpty);
      expect(container.read(friendProvider).query, isEmpty);
    });

    for (final fails in [false, true]) {
      test(
        '⚠️ 검색이 다녀오는 사이 바뀌면, 새 계정이 같은 말로 찾아도 앞 사람 ${fails ? '실패를' : '결과를'} 버린다',
        () async {
          // 검색어만 비교해서는 못 거른다 — 둘 다 '김'이다.
          final container = await signedIn();
          final notifier = container.read(friendProvider.notifier);
          final held = friends.hold = Completer<void>();
          notifier.onQuery('김');
          await settleSearch();
          friends.hold = null;

          await switchTo('u-2');
          notifier.onQuery('김');
          await settleSearch();
          friends.fails = fails;
          held.complete();
          await pumpEventQueue();

          final state = container.read(friendProvider);
          expect(idsOf(state.results), ['u-2-김']);
          expect(state.failure, isNull, reason: '앞 사람의 검색 실패가 새 계정 화면에 떴다');
        },
      );
    }

    for (final fails in [false, true]) {
      test(
        '⚠️ 더 읽는 사이 바뀌면 앞 사람 ${fails ? '실패를 띄우지' : '다음 장을 붙이지'} 않고, 새 계정의 더 읽기를 막지도 풀지도 않는다',
        () async {
          final container = await signedIn();
          final notifier = container.read(friendProvider.notifier);
          await notifier.load();
          final heldOld = friends.hold = Completer<void>();
          final stale = notifier.loadMoreFriends();
          await pumpEventQueue();
          friends.hold = null;

          await switchTo('u-2');
          await notifier.load();
          // 앞 사람의 더 읽기가 아직 붙잡혀 있어도 새 계정은 더 읽을 수 있다.
          final heldNew = friends.hold = Completer<void>();
          final mine = notifier.loadMoreFriends();
          await pumpEventQueue();
          friends.hold = null;
          expect(
            friends.friendsCalls,
            4,
            reason: '앞 사람 첫 장·더 읽기, 새 계정 첫 장·더 읽기',
          );

          // 앞 사람 것이 끝나도 새 계정이 다녀오는 중이라는 표시는 그대로다.
          friends.fails = fails;
          heldOld.complete();
          await stale;
          expect(
            container.read(friendProvider).actionFailure,
            isNull,
            reason: '앞 사람의 더 읽기 실패가 새 계정 화면에 떴다',
          );
          await notifier.loadMoreFriends();
          expect(friends.friendsCalls, 4, reason: '앞 사람의 더 읽기가 새 계정의 표시를 풀었다');

          friends.fails = false;
          heldNew.complete();
          await mine;
          expect(idsOf(container.read(friendProvider).friends), [
            'u-2-friend',
            'u-2-friend-2',
          ]);
        },
      );
    }

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 누른 버튼의 응답이 늦게 ${fails ? '실패해도' : '와도'} 새 계정 화면을 바꾸지 않는다',
        () async {
          final container = await signedIn();
          final notifier = container.read(friendProvider.notifier);
          final heldOld = friends.hold = Completer<void>();
          final stale = notifier.request('u-9');
          await pumpEventQueue();
          friends.hold = null;

          await switchTo('u-2');
          // 새 계정도 같은 사람에게 요청을 보내 다녀오는 중이다.
          final heldNew = friends.hold = Completer<void>();
          final mine = notifier.request('u-9');
          await pumpEventQueue();
          friends.hold = null;

          friends.fails = fails;
          heldOld.complete();
          await stale;

          final state = container.read(friendProvider);
          expect(state.pending, {'u-9'}, reason: '앞 사람 응답이 새 계정이 누른 줄을 풀었다');
          expect(state.changed, isFalse);
          expect(state.actionFailure, isNull);

          friends.fails = false;
          heldNew.complete();
          await mine;
          expect(container.read(friendProvider).changed, isTrue);
        },
      );
    }

    test('같은 계정으로 다시 들어와도 추천을 다시 받는다', () async {
      final container = await signedIn();
      final notifier = container.read(friendProvider.notifier);
      await notifier.selectTab(FriendTab.recommendations);

      await switchTo('u-1');
      await notifier.selectTab(FriendTab.recommendations);

      expect(friends.recommendationsCalls, 2);
      expect(recommendedIds(container), ['u-1-pick']);
    });

    test('같은 계정의 프로필만 바뀌면 비우지 않는다', () async {
      // `/me`가 닉네임을 채워 오는 것처럼 같은 사람 안에서 상태만 바뀐다.
      final container = await signedIn();
      final notifier = container.read(friendProvider.notifier);
      await notifier.load();
      await notifier.selectTab(FriendTab.recommendations);
      final shown = container.read(friendProvider);

      auth.set(
        const AuthSignedIn(
          'u-1',
          isOnboarded: true,
          user: CurrentUser(userId: 'u-1', isOnboarded: true, nickname: '애플찬'),
        ),
      );

      expect(container.read(friendProvider), same(shown));
    });
  });
}

/// 테스트가 로그인 상태를 바꿔 끼우는 컨트롤러.
class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}

/// 계정마다 다른 답을 주는 저장소. 친구 목록은 넘겨받은 번호로, 추천·검색은
/// 요청이 떠날 때의 [owner]로 답한다.
class _AccountFriends implements FriendRepository {
  /// 지금 로그인한 사람.
  var owner = 'u-1';

  /// 있으면 그때 떠난 요청이 이것을 기다린다.
  Completer<void>? hold;

  /// 붙잡혔던 요청이 풀릴 때 실패로 끝내는가.
  var fails = false;

  var friendsCalls = 0;
  var recommendationsCalls = 0;
  final searchQueries = <String>[];

  /// 요청이 떠난다. 그때 로그인해 있던 사람을 돌려준다.
  Future<String> _leave() async {
    final who = owner;
    final gate = hold;
    if (gate != null) {
      await gate.future;
      if (fails) throw const FriendException(FriendFailure.network);
    }
    return who;
  }

  FriendEntry _entry(String userId) => FriendEntry(
    userId: userId,
    nickname: userId,
    relation: FriendRelation.none,
  );

  @override
  Future<FriendList> friends({
    required String userId,
    String? cursor,
    int limit = 20,
  }) async {
    friendsCalls++;
    await _leave();
    // 진짜처럼 **넘겨받은 번호**의 목록을 준다 — 컨트롤러가 앞 사람 번호로
    // 물으면 그 사람 목록이 와서 단언이 깨진다.
    // 첫 장은 다음 장이 있다고 답한다 — 이어 읽기를 부를 수 있게.
    return cursor == null
        ? FriendList(
            items: [_entry('$userId-friend')],
            nextCursor: '$userId-c1',
          )
        : FriendList(items: [_entry('$userId-friend-2')]);
  }

  @override
  Future<List<FriendRecommendation>> recommendations() async {
    recommendationsCalls++;
    final who = await _leave();
    return [FriendRecommendation(entry: _entry('$who-pick'))];
  }

  @override
  Future<FriendList> search({required String query, int limit = 20}) async {
    searchQueries.add(query);
    final who = await _leave();
    return FriendList(items: [_entry('$who-$query')]);
  }

  @override
  Future<FriendRelation> request(String userId) async {
    await _leave();
    return FriendRelation.requestSent;
  }

  @override
  Future<FriendRelation> accept(String userId) => throw UnimplementedError();

  @override
  Future<void> cancel(String userId) => throw UnimplementedError();

  @override
  Future<void> remove(String userId) => throw UnimplementedError();
}
