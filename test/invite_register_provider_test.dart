import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/presentation/invite_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';

/// 초대 등록 — **앱이 `scheduledStartAt`을 직접 만드는 유일한 자리다.**
///
/// 매칭은 서버 문자열을 되돌려 보내므로 이런 판정이 없었다. 경계가 틀리면
/// 고를 수 없는 시각을 권하고 서버가 409로 거절한다.
void main() {
  final now = DateTime(2026, 10, 29, 19);

  ({ProviderContainer container, FakeMatchRepository matches}) build() {
    final matches = FakeMatchRepository();
    final container = ProviderContainer(
      overrides: [
        matchRepositoryProvider.overrideWithValue(matches),
        matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, matches: matches);
  }

  InviteRegisterController notifier(ProviderContainer c) =>
      c.read(inviteRegisterProvider.notifier);
  InviteRegisterState read(ProviderContainer c) =>
      c.read(inviteRegisterProvider);

  group('보낼 수 있는가', () {
    test('둘 다 고르지 않으면 못 보낸다', () {
      final app = build();

      expect(read(app.container).canSubmit(nowKst: now), isFalse);
    });

    test('시각만 골라도 못 보낸다', () {
      final app = build();
      notifier(app.container).pickTime(DateTime(2026, 10, 29, 19, 30));

      expect(read(app.container).canSubmit(nowKst: now), isFalse);
    });

    test('둘 다 고르면 보낼 수 있다', () {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);

      expect(read(app.container).canSubmit(nowKst: now), isTrue);
    });

    test('⚠️ 999m는 못 보내고 1000m는 보낼 수 있다', () {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(999);
      expect(read(app.container).canSubmit(nowKst: now), isFalse);

      notifier(app.container).setMeters(1000);
      expect(read(app.container).canSubmit(nowKst: now), isTrue);
    });

    test('⚠️ 42,195m는 보낼 수 있고 42,196m는 안 된다', () {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(42195);
      expect(read(app.container).canSubmit(nowKst: now), isTrue);

      notifier(app.container).setMeters(42196);
      expect(read(app.container).canSubmit(nowKst: now), isFalse);
    });

    test('⚠️ 범위보다 이른 시각은 못 보낸다', () {
      // 바닥은 지금 +11분이다.
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 10))
        ..setMeters(5000);

      expect(read(app.container).canSubmit(nowKst: now), isFalse);
    });

    test('⚠️ 익일은 못 보낸다', () {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 30, 7))
        ..setMeters(5000);

      expect(read(app.container).canSubmit(nowKst: now), isFalse);
    });

    test('⚠️ 23:49 이후에는 무엇을 골라도 못 보낸다', () {
      // 바닥이 천장을 넘는다. 화면도 피커 대신 안내로 갈린다.
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 23, 59))
        ..setMeters(5000);

      expect(
        read(app.container).canSubmit(nowKst: DateTime(2026, 10, 29, 23, 50)),
        isFalse,
      );
    });

    test('보내는 중에는 또 못 보낸다', () async {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);

      final sending = notifier(app.container).submit(nowKst: now);
      expect(read(app.container).canSubmit(nowKst: now), isFalse);
      await sending;
    });
  });

  group('시각을 다듬는다', () {
    test('⚠️ 초와 밀리초를 버린다', () {
      // 서버가 분 단위를 받는다. 초가 남으면 400이다.
      final app = build();
      notifier(app.container).pickTime(DateTime(2026, 10, 29, 19, 30, 47, 500));

      expect(read(app.container).startAt, DateTime(2026, 10, 29, 19, 30));
    });
  });

  group('방을 연다', () {
    test('서버 표기로 보낸다 — 오프셋 없는 KST', () async {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(7000);

      final roomId = await notifier(app.container).submit(nowKst: now);

      expect(app.matches.createdStartAt, '2026-10-29T19:30:00');
      expect(app.matches.createdMeters, 7000);
      expect(roomId, app.matches.inviteRoomId);
    });

    test('방 번호를 남긴다 — 신청·러닝·결과를 잇는 고리다', () async {
      final app = build();
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);

      await notifier(app.container).submit(nowKst: now);

      expect(
        await app.container.read(matchRoomStoreProvider).read(),
        app.matches.inviteRoomId,
      );
    });

    test('⚠️ 범위를 벗어나면 서버가 거절하고 그 갈래를 들고 있는다', () async {
      // 기기 시계가 느리면 화면에서 합법이던 값이 여기로 온다.
      final app = build();
      app.matches.createFailure = const InviteException(
        InviteFailure.startAtOutOfRange,
        message: '시작 시각이 허용 범위를 벗어났습니다.',
      );
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);

      final roomId = await notifier(app.container).submit(nowKst: now);

      expect(roomId, isNull);
      expect(read(app.container).failure, InviteFailure.startAtOutOfRange);
      expect(read(app.container).message, '시작 시각이 허용 범위를 벗어났습니다.');
    });

    test('실패를 지울 수 있다 — 스낵바는 한 번만 뜬다', () async {
      final app = build();
      app.matches.createFailure = const InviteException(
        InviteFailure.alreadyInProgress,
      );
      notifier(app.container)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);
      await notifier(app.container).submit(nowKst: now);

      notifier(app.container).clearFailure();

      expect(read(app.container).failure, isNull);
      // 고른 값은 남는다 — 다시 누를 수 있어야 한다.
      expect(read(app.container).meters, 5000);
    });

    test('⚠️ 못 보낼 상태에서는 서버를 부르지 않는다', () async {
      final app = build();
      notifier(app.container).setMeters(5000);

      final roomId = await notifier(app.container).submit(nowKst: now);

      expect(roomId, isNull);
      expect(app.matches.createdStartAt, isNull);
    });
  });

  group('고를 수 있는 범위', () {
    test('화면에 안내할 값을 준다', () {
      final window = InviteRegisterState.windowAt(now)!;

      expect(window.from, DateTime(2026, 10, 29, 19, 11));
      expect(window.to, DateTime(2026, 10, 29, 23, 59));
    });

    test('⚠️ 23:49 이후에는 null이다 — 화면이 전용 안내로 갈린다', () {
      expect(
        InviteRegisterState.windowAt(DateTime(2026, 10, 29, 23, 50)),
        isNull,
      );
    });
  });
}
