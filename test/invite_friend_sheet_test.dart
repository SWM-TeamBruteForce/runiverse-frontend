import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/room_invitation.dart';
import 'package:runiverse/features/matching/presentation/invite_friend_sheet.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/session/domain/user_status.dart';

/// 친구 초대 모달.
///
/// ## ⚠️ 줄마다 버튼인 이유
///
/// 서버가 `inviteeId` 하나만 받는다. 다중 선택 + "초대하기" 한 방이면 **결과를
/// 한 줄씩 보여줄 수 없다** — 실패 사유가 사람마다 다르다.
void main() {
  final startAt = DateTime.now().add(const Duration(minutes: 30));

  RoomInfo room({int players = 2, List<String> invited = const []}) => RoomInfo(
    runningRoomId: 130,
    type: RoomType.invite,
    status: RoomStatus.matching,
    scheduledStartAt: startAt,
    players: [
      for (var i = 0; i < players; i++)
        RoomPlayer(userId: 'u-$i', nickname: '러너$i', isDeleted: false),
    ],
    invitations: [
      for (final id in invited)
        RoomInvitation(userId: id, nickname: '초대$id', isDeleted: false),
    ],
  );

  /// 친구 넷. 그중 둘은 방 안의 사람과 같은 `userId`다.
  FakeFriendRepository friends() => FakeFriendRepository(
    friendEntries: const [
      FriendEntry(
        userId: 'f-1',
        nickname: '철수',
        relation: FriendRelation.friend,
      ),
      FriendEntry(
        userId: 'f-2',
        nickname: '영희',
        relation: FriendRelation.friend,
      ),
      FriendEntry(
        userId: 'u-0',
        nickname: '러너0',
        relation: FriendRelation.friend,
      ),
      FriendEntry(
        userId: 'i-1',
        nickname: '초대i-1',
        relation: FriendRelation.friend,
      ),
    ],
  );

  /// 친구 저장소를 직접 넘겨 띄운다. 3분기 검증에 쓴다.
  Future<void> pumpWith(WidgetTester tester, FakeFriendRepository repo) async {
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
          friendRepositoryProvider.overrideWithValue(repo),
          matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: InviteFriendSheet(room: room())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<FakeMatchRepository> pump(
    WidgetTester tester, {
    required RoomInfo snapshot,
    FakeMatchRepository? matches,
  }) async {
    final repo = matches ?? FakeMatchRepository();
    // 친구 목록은 **내가 누구인지** 알아야 받아진다 — 내 줄에는 버튼을 세우지
    // 않으려고 `FriendController`가 그것을 먼저 읽는다.
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
          friendRepositoryProvider.overrideWithValue(friends()),
          matchRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: InviteFriendSheet(room: snapshot)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  /// 그 닉네임 줄의 버튼 글자.
  String buttonOf(WidgetTester tester, String nickname) {
    final row = find.ancestor(
      of: find.text(nickname),
      matching: find.byType(Row),
    );
    final labels = find
        .descendant(of: row.first, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    return labels.last;
  }

  group('줄 상태', () {
    testWidgets('초대할 수 있으면 초대 버튼이다', (tester) async {
      await pump(tester, snapshot: room());

      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetInvite);
    });

    testWidgets('⚠️ 이미 방에 있으면 참여 중으로 잠긴다', (tester) async {
      await pump(tester, snapshot: room());

      expect(buttonOf(tester, '러너0'), AppStrings.inviteSheetJoined);
    });

    testWidgets('⚠️ 답을 기다리는 중이면 초대 중으로 잠긴다 — 독촉을 안 내보낸다', (tester) async {
      // 남은 횟수를 알 수 없어서, 몇 번 남았는지 못 말하면서 누르라고 권하는
      // 버튼이 된다(설계 §4-4).
      await pump(tester, snapshot: room(invited: ['i-1']));

      expect(buttonOf(tester, '초대i-1'), AppStrings.inviteSheetInvited);
    });

    testWidgets('⚠️ 자리가 없으면 모든 버튼이 잠긴다', (tester) async {
      // 서버는 꽉 찬 방에도 초대를 받아 주지만 상대가 수락할 때 막힌다.
      final repo = await pump(tester, snapshot: room(players: 4));

      await tester.tap(find.text(AppStrings.inviteSheetInvite).first);
      await tester.pumpAndSettle();

      expect(repo.inviteCalls, isEmpty);
    });

    testWidgets('남은 자리를 적는다', (tester) async {
      await pump(tester, snapshot: room(invited: ['i-1']));

      // 정원 4 − 참가자 2 − 초대 1.
      expect(find.text(AppStrings.inviteRoomSeatsLeft(1)), findsOneWidget);
    });
  });

  group('초대를 보낸다', () {
    testWidgets('⚠️ 한 번에 한 명씩, 고른 사람만 보낸다', (tester) async {
      final repo = await pump(tester, snapshot: room());

      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('철수'), matching: find.byType(Row))
              .first,
          matching: find.text(AppStrings.inviteSheetInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.inviteCalls, [(130, 'f-1')]);
    });

    testWidgets('보내면 그 줄이 초대 중으로 바뀐다', (tester) async {
      await pump(tester, snapshot: room());

      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('철수'), matching: find.byType(Row))
              .first,
          matching: find.text(AppStrings.inviteSheetInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetInvited);
    });

    testWidgets('⚠️ 두 번 눌려도 한 번만 간다', (tester) async {
      // 횟수가 헛되이 줄어든다. 남은 횟수를 볼 수 없으니 더 아깝다.
      final repo = await pump(tester, snapshot: room());
      final button = find.descendant(
        of: find
            .ancestor(of: find.text('철수'), matching: find.byType(Row))
            .first,
        matching: find.text(AppStrings.inviteSheetInvite),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      // 이제 잠겨 있어 더 눌리지 않는다.
      expect(repo.inviteCalls, hasLength(1));
    });
  });

  group('실패하면', () {
    testWidgets('⚠️ 서버 문구를 그 줄에 붙인다', (tester) async {
      final repo = FakeMatchRepository()
        ..inviteFailure = const InviteException(
          InviteFailure.notFriend,
          message: '친구에게만 초대할 수 있습니다.',
        );
      await pump(tester, snapshot: room(), matches: repo);

      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('철수'), matching: find.byType(Row))
              .first,
          matching: find.text(AppStrings.inviteSheetInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('친구에게만 초대할 수 있습니다.'), findsOneWidget);
    });

    testWidgets('문구가 없으면 갈래별 기본 문구를 쓴다', (tester) async {
      final repo = FakeMatchRepository()
        ..inviteFailure = const InviteException(InviteFailure.inMatching);
      await pump(tester, snapshot: room(), matches: repo);

      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('철수'), matching: find.byType(Row))
              .first,
          matching: find.text(AppStrings.inviteSheetInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.inviteSheetInMatching), findsOneWidget);
    });

    testWidgets('다시 초대할 수 있다', (tester) async {
      final repo = FakeMatchRepository()
        ..inviteFailure = const InviteException(InviteFailure.running);
      await pump(tester, snapshot: room(), matches: repo);
      final button = find.descendant(
        of: find
            .ancestor(of: find.text('철수'), matching: find.byType(Row))
            .first,
        matching: find.text(AppStrings.inviteSheetInvite),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetRetry);
    });
  });

  group('⚠️ 열어 둔 사이에 방이 바뀐다', () {
    testWidgets('스트림이 나른 최신 방을 본다', (tester) async {
      // 초대 방은 **최소 10분**을 기다린다. 열어 둔 사이에 수락·거절·마감이
      // 오는데, 굳은 스냅샷을 보면 꽉 찬 방에 계속 초대를 보낸다.
      final stream = FakeMatchStream();
      final matches = FakeMatchRepository();
      final tokens = InMemoryTokenStore();
      await tokens.saveSession(
        userId: 'me',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          friendRepositoryProvider.overrideWithValue(friends()),
          matchRepositoryProvider.overrideWithValue(matches),
          matchStreamProvider.overrideWithValue(stream),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: InviteFriendSheet(room: room())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.inviteRoomSeatsLeft(2)), findsOneWidget);

      // 방이 꽉 찼다.
      container.read(matchRoomProvider.notifier).connect();
      await tester.pump();
      stream.emit(InviteRoomUpdated(room(players: 4)));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.inviteRoomSeatsLeft(0)), findsOneWidget);
      // 꽉 찬 방에 더 보내지 않는다.
      await tester.tap(find.text(AppStrings.inviteSheetInvite).first);
      await tester.pumpAndSettle();
      expect(matches.inviteCalls, isEmpty);
    });
  });

  /// ⚠️ **거절했는데 `초대 중`으로 남던 자리다**(실측 2026-10-29).
  group('보낸 뒤 서버 목록을 따른다', () {
    testWidgets('상대가 거절하면 다시 초대할 수 있다', (tester) async {
      final stream = FakeMatchStream();
      final matches = FakeMatchRepository();
      final tokens = InMemoryTokenStore();
      await tokens.saveSession(
        userId: 'me',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          friendRepositoryProvider.overrideWithValue(friends()),
          matchRepositoryProvider.overrideWithValue(matches),
          matchStreamProvider.overrideWithValue(stream),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: InviteFriendSheet(room: room())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(matchRoomProvider.notifier).connect();
      await tester.pump();

      // 철수를 초대한다.
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('철수'), matching: find.byType(Row))
              .first,
          matching: find.text(AppStrings.inviteSheetInvite),
        ),
      );
      await tester.pumpAndSettle();
      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetInvited);

      // 서버가 초대를 확인해 준다.
      stream.emit(InviteRoomUpdated(room(invited: ['f-1'])));
      await tester.pumpAndSettle();
      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetInvited);

      // 철수가 거절했다 — 목록에서 빠진다.
      stream.emit(InviteRoomUpdated(room()));
      await tester.pumpAndSettle();

      // ⚠️ `초대 중`으로 남으면 거짓이고, 다시 보낼 길도 없다.
      expect(buttonOf(tester, '철수'), AppStrings.inviteSheetInvite);
    });
  });

  group('3분기를 처리한다', () {
    testWidgets('⚠️ 못 받았으면 "없다"가 아니라 실패를 말한다', (tester) async {
      // 친구가 많은 사람에게 "초대할 러너가 없어요"라고 하면 안 된다.
      await pumpWith(
        tester,
        FakeFriendRepository(failure: FriendFailure.network),
      );

      expect(find.text(AppStrings.friendLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.inviteSheetEmpty), findsNothing);
    });

    testWidgets('정말 없으면 빈 상태를 그린다', (tester) async {
      await pumpWith(tester, FakeFriendRepository());

      expect(find.text(AppStrings.inviteSheetEmpty), findsOneWidget);
    });
  });

  group('⚠️ 초대할 수 없는 사람에게 버튼을 세우지 않는다', () {
    testWidgets('친구가 아닌 줄은 목록에 없다', (tester) async {
      // `friends()`는 받은 요청·보낸 요청·친구가 섞여 온다. 친구가 아닌 줄에
      // 초대 버튼을 세우면 눌러 봐야 409 NOT_FRIEND다.
      await pumpWith(
        tester,
        FakeFriendRepository(
          friendEntries: const [
            FriendEntry(
              userId: 'f-1',
              nickname: '철수',
              relation: FriendRelation.friend,
            ),
            FriendEntry(
              userId: 'p-1',
              nickname: '보낸요청',
              relation: FriendRelation.requestSent,
            ),
            FriendEntry(
              userId: 'p-2',
              nickname: '받은요청',
              relation: FriendRelation.requestReceived,
            ),
          ],
        ),
      );

      expect(find.text('철수'), findsOneWidget);
      expect(find.text('보낸요청'), findsNothing);
      expect(find.text('받은요청'), findsNothing);
    });
  });
}
