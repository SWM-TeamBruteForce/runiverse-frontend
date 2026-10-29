import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/fake_friend_repository.dart';
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
}
