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

    // 통지가 온 사람이 앞으로 온다 — 나머지는 아직 0m다.
    expect(board.rows.first.userId, 'u-2');
    expect(board.rows.first.progress?.distanceMeters, 1520);
    expect(board.rows.last.progress, isNull);
  });

  test('같은 사람의 통지는 덮는다', () {
    // 갱신분만 오므로 최신값을 들고 있어야 한다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-1', 100))
        .withProgress(progress('u-1', 260));

    expect(board.rows.first.progress?.distanceMeters, 260);
  });

  test('진행률 높은 순으로 세운다', () {
    // 정본 S13이 정한 순서다. 금지된 것은 등수 숫자이지 정렬이 아니다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-2', 3000))
        .withProgress(progress('u-1', 500));

    expect(board.rows.first.userId, 'u-2');
    expect(board.rows.last.userId, 'u-1');
  });

  test('⚠️ 같은 거리면 명단 순서를 지킨다', () {
    // 나란히 달릴 때 통지마다 자리가 바뀌면 줄이 깜빡인다. 기준값 미만으로
    // 앞서거니 뒤서거니 하는 동안은 처음 순서(명단 순)가 그대로다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-2', 5))
        .withProgress(progress('u-1', 5))
        .withProgress(progress('u-2', 9));

    expect(board.rows.map((row) => row.userId), ['u-1', 'u-2']);
  });

  test('아직 통지가 없는 사람은 뒤로 간다', () {
    // 0m로 읽는다. 앞에 두면 달리고 있는 사람이 아래로 밀린다.
    final board = empty.withRoster(members).withProgress(progress('u-2', 10));

    expect(board.rows.first.userId, 'u-2');
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

  test('모르는 사람도 거리대로 섞인다', () {
    // 이름을 몰라도 함께 달리는 중이다. 뒤로 몰면 화면이 사실과 달라진다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-9', 800))
        .withProgress(progress('u-1', 100));

    expect(board.rows.map((row) => row.userId), ['u-9', 'u-1', 'u-2']);
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

    test('콤보를 갈아도 진행은 남는다', () {
      // 둘은 다른 통지다. 하나가 오면 다른 하나를 지워야 할 이유가 없다.
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 500))
          .withCombos(const RunCombo([]));

      expect(board.rows.first.progress?.distanceMeters, 500);
    });
  });

  group('자리 바꾸기 히스테리시스', () {
    // FE노트 S13: 순위 교체는 격차가 기준값 이상 확정될 때만. 접전에서 통지마다
    // 줄이 튀는 것을 막는다. 기준값은 `PartyBoard.swapThresholdMeters` 하나다.
    test('기준값 미만으로 앞서면 자리를 지킨다', () {
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 1000))
          .withProgress(progress('u-2', 1000))
          .withProgress(progress('u-2', 1009));

      expect(board.rows.map((row) => row.userId), ['u-1', 'u-2']);
    });

    test('기준값만큼 앞서면 자리를 바꾼다', () {
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 1000))
          .withProgress(progress('u-2', 1000))
          .withProgress(progress('u-2', 1010));

      expect(board.rows.map((row) => row.userId), ['u-2', 'u-1']);
    });

    test('⚠️ 바뀐 뒤에는 되돌리는 쪽도 기준값이 필요하다', () {
      // 5m 다시 앞섰다고 되돌리면 경계에서 줄이 왔다 갔다 한다.
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 1000))
          .withProgress(progress('u-2', 1010))
          .withProgress(progress('u-1', 1015));

      expect(board.rows.map((row) => row.userId), ['u-2', 'u-1']);
      expect(
        board.withProgress(progress('u-1', 1020)).rows.map((row) => row.userId),
        ['u-1', 'u-2'],
      );
    });

    test('처음 순서는 거리순이다', () {
      // 기억이 없을 때는 기준값을 적용할 대상이 없다 — 5m 차이도 거리순.
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-2', 1005))
          .withProgress(progress('u-1', 1000));

      expect(board.rows.first.userId, 'u-2');
    });
  });

  group('내 레인', () {
    // 정본 S13은 나를 파티원과 같은 목록에서 진행률순으로 세운다.
    test('lanes에는 내가 들어 있고 rows에는 없다', () {
      final board = empty.withRoster(members).withMyDistance(500);

      expect(board.lanes.where((lane) => lane.isMe), hasLength(1));
      expect(board.rows.any((row) => row.isMe), isFalse);
      expect(board.lanes, hasLength(3));
    });

    test('내 거리도 같은 규칙으로 섞인다', () {
      final board = empty
          .withRoster(members)
          .withProgress(progress('u-1', 1000))
          .withMyDistance(1005);

      // 5m 앞선 것으로는 못 올라간다 — 처음 순서는 거리순이지만 이미 기억이 있다.
      expect(board.lanes.map((lane) => lane.userId), [
        'u-1',
        PartyBoard.meId,
        'u-2',
      ]);
      expect(board.withMyDistance(1010).lanes.map((lane) => lane.userId), [
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

      expect(board.colorSlotOf('u-5'), 2);
      expect(board.colorSlotOf('u-9'), 3);
    });

    test('솔로인 나는 첫 자리다', () {
      expect(empty.colorSlotOf(PartyBoard.meId), 0);
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

      expect(board.rows.map((row) => row.gapMeters), [160, -120]);
    });

    test('통지가 없으면 격차도 없다', () {
      final board = empty.withRoster(members).withMyDistance(1000);

      expect(board.rows.first.gapMeters, isNull);
      expect(board.lanes.where((lane) => lane.isMe).single.gapMeters, isNull);
    });
  });

  test('솔로 러닝은 줄이 없다', () {
    // 화면은 줄이 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
    expect(empty.rows, isEmpty);
  });
}
