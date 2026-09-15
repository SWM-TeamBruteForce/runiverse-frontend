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
    // 나란히 달릴 때 통지마다 자리가 바뀌면 줄이 깜빡인다.
    final board = empty
        .withRoster(members)
        .withProgress(progress('u-2', 1000))
        .withProgress(progress('u-1', 1000));

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

  test('솔로 러닝은 줄이 없다', () {
    // 화면은 줄이 비었는지만 보면 된다 — 솔로인지 매칭인지 따로 묻지 않는다.
    expect(empty.rows, isEmpty);
  });
}
