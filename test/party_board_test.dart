import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';

/// 명단과 통지를 **어떻게 맞추는가.**
///
/// 이름은 대기방에서 들고 오고 수치는 러닝 채널이 민다. 둘이 어긋나는 경우가
/// 이 로직의 전부다 — 이름만 있고 수치가 없거나, 그 반대이거나.
void main() {
  const members = [
    PartyMember(userId: 'u-1', nickname: '이서연'),
    PartyMember(userId: 'u-2', nickname: '박지훈'),
  ];

  RunProgress progress(String userId, int meters) =>
      RunProgress(userId: userId, distanceMeters: meters);

  ComboPeer peer(String userId, int combo) => ComboPeer(
    userId: userId,
    gapMeters: 0,
    comboCount: combo,
    maxComboCount: combo,
  );

  const empty = PartyBoard();

  test('명단만 있으면 수치 없는 줄이 된다', () {
    // 러닝을 막 시작해 아직 통지가 오지 않았다.
    final board = empty.withRoster(members);

    expect(board.rows, hasLength(2));
    expect(board.rows.first.member?.nickname, '이서연');
    expect(board.rows.first.progress, isNull);
  });

  test('진행 통지가 줄에 붙는다', () {
    final board = empty.withRoster(members).withProgress(progress('u-2', 1520));

    // 자리는 명단 순 그대로다. 통지가 온 사람의 수치만 채워진다.
    expect(board.rows.last.userId, 'u-2');
    expect(board.rows.last.progress?.distanceMeters, 1520);
    expect(board.rows.first.progress, isNull);
  });

  test('같은 사람의 통지는 덮는다', () {
    // 갱신분만 오므로 최신값을 들고 있어야 한다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-1', 100))
        .withProgress(progress('u-1', 260));

    expect(board.rows.first.progress?.distanceMeters, 260);
  });

  test('⚠️ 거리가 뒤집혀도 명단 순서 그대로다', () {
    // 2026-09-18 결정: 진행·콤보 통지가 10초마다 같이 오는 화면에서 카드까지
    // 자리를 옮기면 혼잡하다. 앞뒤는 막대와 격차 문장으로 보인다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-2', 3000))
        .withProgress(progress('u-1', 500));

    expect(board.rows.map((row) => row.userId), ['u-1', 'u-2']);
  });

  test('아직 통지가 없어도 명단 자리를 지킨다', () {
    final board = empty.withRoster(members).withProgress(progress('u-2', 10));

    expect(board.rows.map((row) => row.userId), ['u-1', 'u-2']);
  });

  test('⚠️ 명단에 없어도 통지가 오면 그린다', () {
    // 러닝 중 앱을 재시작하면 명단이 비어 있다. 통지까지 버리면 화면이 통째로
    // 빈다 — 이름만 없을 뿐 수치는 그릴 수 있다.
    final board = empty.withProgress(progress('u-9', 800));

    expect(board.rows, hasLength(1));
    expect(board.rows.single.userId, 'u-9');
    expect(board.rows.single.member, isNull);
    expect(board.rows.single.progress?.distanceMeters, 800);
  });

  test('모르는 사람은 명단 뒤에 userId 순으로 붙는다', () {
    // 통지가 온 순서로 두면 재시작할 때마다 줄이 달라진다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-9', 800))
        .withProgress(progress('u-8', 100))
        .withProgress(progress('u-1', 100));

    expect(board.rows.map((row) => row.userId), ['u-1', 'u-2', 'u-8', 'u-9']);
  });

  group('콤보', () {
    test('통지가 줄에 붙는다', () {
      final board = empty
          .withRoster(members)
          .withCombos(RunCombo([peer('u-1', 12)]));

      expect(board.rows.first.combo?.comboCount, 12);
      expect(board.rows.last.combo, isNull);
    });

    test('⚠️ 합치지 않고 통째로 갈아끼운다', () {
      // 끊긴 상대는 목록에서 빠지는 것으로 끊김을 알린다. 덧붙이면 끊긴 콤보가
      // 화면에 영영 남는다.
      final board = empty
          .withRoster(members)
          .withCombos(RunCombo([peer('u-1', 12), peer('u-2', 3)]))
          .withCombos(RunCombo([peer('u-2', 4)]));

      expect(board.rows.first.combo, isNull);
      expect(board.rows.last.combo?.comboCount, 4);
    });

    test('빈 목록이 오면 전부 끊긴 것이다', () {
      final board = empty
          .withRoster(members)
          .withCombos(RunCombo([peer('u-1', 12)]))
          .withCombos(const RunCombo([]));

      expect(board.rows.every((row) => row.combo == null), isTrue);
    });

    test('최고 콤보는 끊겨도 기억한다', () {
      // 콤보가 끊기면 목록에서 빠져 `maxComboCount`도 같이 사라진다. 카드에
      // "최고 N"을 남기려면 보드가 따로 들고 있어야 한다.
      final board = empty
          .withRoster(members)
          .withCombos(
            const RunCombo([
              ComboPeer(
                userId: 'u-1',
                gapMeters: 0,
                comboCount: 5,
                maxComboCount: 7,
              ),
            ]),
          )
          .withCombos(RunCombo([peer('u-1', 9), peer('u-2', 2)]))
          .withCombos(const RunCombo([]));

      expect(board.bestComboOf('u-1'), 9);
      expect(board.bestComboOf('u-2'), 2);
      expect(board.bestComboOf('u-9'), 0);
      expect(board.myBestCombo, 9);
      expect(board.rows.every((row) => row.combo == null), isTrue);
    });

    test('콤보를 갈아도 진행은 남는다', () {
      // 둘은 다른 통지다. 하나가 오면 다른 하나를 지워야 할 이유가 없다.
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 500))
          .withCombos(const RunCombo([]));

      expect(board.rows.first.progress?.distanceMeters, 500);
    });
  });

  group('내 레인', () {
    // 나는 거리와 상관없이 맨 위다.
    test('lanes에는 내가 들어 있고 rows에는 없다', () {
      final board = empty.withRoster(members).withMyDistance(500);

      expect(board.lanes.where((lane) => lane.isMe), hasLength(1));
      expect(board.rows.any((row) => row.isMe), isFalse);
      expect(board.lanes, hasLength(3));
    });

    test('⚠️ 내가 뒤처져도 맨 위다', () {
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 1000))
          .withMyDistance(5);

      expect(board.lanes.map((lane) => lane.userId), [
        PartyBoard.meId,
        'u-1',
        'u-2',
      ]);
    });

    test('솔로는 내 레인 하나뿐이다', () {
      expect(empty.withMyDistance(300).lanes.map((lane) => lane.isMe), [true]);
    });
  });

  group('명단에 내가 있을 때', () {
    // 대기방 명단은 방 전원이라 나도 들어 있다. 서버는 내 진행을 보내지 않으므로
    // 이 줄을 파티원으로 두면 0m에 영영 멈춘 내 이름이 "나" 레인 옆에 또 뜬다.
    const everyone = [
      PartyMember(userId: 'me-1', nickname: '러너42'),
      ...members,
    ];

    test('내 줄은 하나이고 내 이름을 안다', () {
      final board = empty.withRoster(everyone, myUserId: 'me-1');

      final me = board.lanes.where((lane) => lane.isMe).single;
      expect(me.userId, 'me-1');
      expect(me.member?.nickname, '러너42');
      expect(board.lanes, hasLength(3));
      expect(board.rows.map((row) => row.userId), ['u-1', 'u-2']);
    });

    test('내 줄의 거리는 서버가 아니라 내 값이다', () {
      final board = empty
          .withRoster(everyone, myUserId: 'me-1')
          .withMyDistance(1200)
          .withProgress(progress('u-1', 1000));

      expect(board.lanes.first.userId, 'me-1');
      expect(board.lanes.first.progress, isNull);
    });
  });

  group('색 자리', () {
    // 정본 "각자의 색으로 칠해요". 시그니처 컬러가 아직 없어 명단 순서로 돌린다.
    // 명단은 서버가 준 순서라 어느 기기에서 봐도 같은 사람이 같은 자리다.
    const everyone = [
      PartyMember(userId: 'me-1', nickname: '러너42'),
      ...members,
    ];

    test('명단 순서가 곧 자리다', () {
      final board = empty.withRoster(everyone, myUserId: 'me-1');

      expect(board.colorSlotOf('me-1'), 0);
      expect(board.colorSlotOf('u-1'), 1);
      expect(board.colorSlotOf('u-2'), 2);
    });

    test('⚠️ 명단에 없는 사람도 자리를 받는다', () {
      // 재시작 뒤 명단이 비어도 색이 사람마다 달라야 한다. 명단 뒤에 이어 붙이고
      // 그들끼리는 userId 순으로 고정한다 — 통지 순서에 따라 색이 바뀌면 안 된다.
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-9', 10))
          .withProgress(progress('u-5', 20));

      // 명단(2) 뒤가 내 자리(2), 낯선 사람은 그 뒤(3, 4).
      expect(board.colorSlotOf(PartyBoard.meId), 2);
      expect(board.colorSlotOf('u-5'), 3);
      expect(board.colorSlotOf('u-9'), 4);
    });

    test('솔로인 나는 첫 자리다', () {
      expect(empty.colorSlotOf(PartyBoard.meId), 0);
    });

    test('⚠️ 명단이 비어도 나와 낯선 사람의 색이 다르다', () {
      // 재시작 뒤 명단이 없을 때. 실주행에서 둘 다 같은 색으로 그려졌다.
      final board = empty.withProgress(progress('u-9', 800));

      expect(board.colorSlotOf(PartyBoard.meId), 0);
      expect(board.colorSlotOf('u-9'), 1);
    });
  });

  group('격차', () {
    // 정본 표의 `+160m` / `-120m`. 양수면 상대가 앞이다.
    test('서버 콤보 값이 있으면 그것을 쓴다', () {
      final board = empty
          .withRoster(members)
          .withMyDistance(1000)
          .withProgress(progress('u-1', 1300))
          .withCombos(
            const RunCombo([
              ComboPeer(
                userId: 'u-1',
                gapMeters: 12,
                comboCount: 3,
                maxComboCount: 3,
              ),
            ]),
          );

      expect(board.rows.first.gapMeters, 12);
    });

    test('없으면 거리 차로 만든다', () {
      final board = empty
          .withRoster(members)
          .withMyDistance(1000)
          .withProgress(progress('u-1', 880))
          .withProgress(progress('u-2', 1160));

      // 명단 순(u-1, u-2)이다. u-1은 120m 뒤, u-2는 160m 앞.
      expect(board.rows.map((row) => row.gapMeters), [-120, 160]);
    });

    test('통지가 없으면 격차도 없다', () {
      final board = empty.withRoster(members).withMyDistance(1000);

      expect(board.rows.first.gapMeters, isNull);
      expect(board.lanes.where((lane) => lane.isMe).single.gapMeters, isNull);
    });
  });

  test('통지에 받은 시각을 찍을 수 있다', () {
    // 서버는 끊김을 알리지 않는다. 마지막 통지가 언제였는지가 유일한 단서다.
    final at = DateTime(2026, 9, 17, 19, 5);
    final stamped = progress('u-1', 500).stamped(at);

    expect(stamped.receivedAt, at);
    expect(stamped.distanceMeters, 500);
    expect(stamped.userId, 'u-1');
  });

  test('솔로 러닝은 줄이 없다', () {
    // 화면은 줄이 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
    expect(empty.rows, isEmpty);
  });
}
