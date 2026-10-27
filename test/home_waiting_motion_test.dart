import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/home/presentation/home_waiting.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭 대기 히어로의 움직임 — **원만 움직인다**(시안 `158:2951`).
///
/// ## ⚠️ 여기서 검사하는 것은 상태 전이다
///
/// 회전이 예쁜지는 테스트가 답할 수 없다. 답할 수 있는 것은 **언제 축하가
/// 뜨고 언제 안 뜨는가**, 그리고 **원이 실제로 자리를 옮기는가**다. 둘 다
/// 틀리면 화면이 고장 난 것으로 읽힌다 — 들어올 때마다 축하가 뜨거나,
/// 움직인다고 해 놓고 멈춰 있거나.
void main() {
  RoomPlayer player(String id, String nickname) =>
      RoomPlayer(userId: id, nickname: nickname, isDeleted: false);

  RoomInfo roomOf(List<RoomPlayer> players) => RoomInfo(
    runningRoomId: 1,
    status: RoomStatus.matching,
    scheduledStartAt: DateTime(2026, 10, 27, 19),
    players: players,
  );

  /// ⚠️ **폭을 못 박는다.** `Stack`이 폭을 자식에게서 받으므로, 느슨한
  /// 제약을 주면 가장 큰 자식(가운데 아바타 135px)만큼으로 쪼그라든다 —
  /// 실제 화면은 카드가 폭을 꽉 채운다.
  Widget appOf(RoomInfo room) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: SizedBox(
        width: 412,
        child: HomeWaiting(room: room, onLobby: () {}, myUserId: 'me'),
      ),
    ),
  );

  final meAlone = roomOf([player('me', '지환')]);
  final withMinsu = roomOf([player('me', '지환'), player('u2', '민수')]);

  /// 그 사람의 축하가 떠 있는가.
  ///
  /// ⚠️ **문장을 한 덩이로 찾지 않는다.** 화면은 닉네임과 `님과 매칭성공!`을
  /// 따로 세운다 — 긴 닉네임만 줄이려면 그래야 한다.
  ///
  /// 닉네임 **전체**가 글자로 나오는 자리는 축하 카드뿐이다. 궤도의 아바타는
  /// 첫 글자만 그리고, 부제는 머릿수만 말한다.
  Finder celebrates(String nickname) => find.text(nickname);

  group('합류 축하', () {
    testWidgets('파티원이 늘면 닉네임과 함께 뜬다', (tester) async {
      await tester.pumpWidget(appOf(meAlone));
      expect(celebrates('민수'), findsNothing);

      await tester.pumpWidget(appOf(withMinsu));
      await tester.pump(const Duration(milliseconds: 100));

      expect(celebrates('민수'), findsOneWidget);
      expect(find.text(AppStrings.homeMatchSuccessSuffix), findsOneWidget);
      // ⚠️ **사진도 함께 선다.** 닉네임만 띄우면 누가 왔는지 얼굴로는 알 수
      // 없다. 가운데 나 · 궤도의 민수 · 축하의 민수, 셋이다.
      expect(find.byType(RunnerAvatarV2), findsNWidgets(3));
    });

    testWidgets('⚠️ 들어오자마자는 뜨지 않는다', (tester) async {
      // 이미 둘인 방에 다시 들어왔다고 축하하면, 화면을 열 때마다 뜬다.
      // 축하는 **늘어난 순간**의 것이지 머릿수의 것이 아니다.
      await tester.pumpWidget(appOf(withMinsu));
      await tester.pump(const Duration(milliseconds: 100));

      expect(celebrates('민수'), findsNothing);
    });

    testWidgets('⚠️ 누가 나가도 뜨지 않는다', (tester) async {
      await tester.pumpWidget(appOf(withMinsu));
      await tester.pumpWidget(appOf(meAlone));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('매칭성공'), findsNothing);
    });

    testWidgets('1.92초가 지나면 사라진다', (tester) async {
      await tester.pumpWidget(appOf(meAlone));
      await tester.pumpWidget(appOf(withMinsu));
      await tester.pump(const Duration(milliseconds: 100));
      expect(celebrates('민수'), findsOneWidget);

      // ⚠️ **`pumpAndSettle`을 쓰지 못한다.** 궤도와 숨쉬기가 영원히
      // 반복하므로 화면이 잠잠해질 수 없다 — 그것이 맞는 동작이다.
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(celebrates('민수'), findsNothing);
    });

    testWidgets('⚠️ 긴 닉네임은 말줄임한다 — 문구는 끝까지 남는다', (tester) async {
      // 닉네임은 16자까지 받는다. 문장 전체를 줄이면 정작 알려야 할
      // `매칭성공!`이 먼저 잘린다.
      await tester.pumpWidget(appOf(meAlone));
      await tester.pumpWidget(
        appOf(roomOf([player('me', '지환'), player('u2', '열여섯글자까지받는닉네임')])),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final nickname = tester.widget<Text>(find.text('열여섯글자까지받는닉네임'));
      expect(nickname.overflow, TextOverflow.ellipsis);
      expect(nickname.maxLines, 1);
      // 뒷말은 따로 선다 — 잘리지 않는다.
      expect(find.text(AppStrings.homeMatchSuccessSuffix), findsOneWidget);
    });

    testWidgets('⚠️ 둘이 연달아 들어오면 나중 사람으로 바뀐다', (tester) async {
      // 앞 축하가 떠 있는 채로 다음이 오면, 1.92초를 기다렸다 뜨는 것이
      // 아니라 **지금 들어온 사람**으로 갈아탄다. 기다리면 이미 지난 일을
      // 뒤늦게 알리게 된다.
      await tester.pumpWidget(appOf(meAlone));
      await tester.pumpWidget(appOf(withMinsu));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        appOf(
          roomOf([player('me', '지환'), player('u2', '민수'), player('u3', '지현')]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(celebrates('지현'), findsOneWidget);
      expect(celebrates('민수'), findsNothing);
    });
  });

  group('맴도는 원', () {
    testWidgets('⚠️ 시간이 지나면 자리를 옮긴다', (tester) async {
      await tester.pumpWidget(appOf(withMinsu));
      final before = tester.getCenter(find.text('민'));

      await tester.pump(const Duration(seconds: 3));
      final after = tester.getCenter(find.text('민'));

      expect(
        (after - before).distance,
        greaterThan(8),
        reason: '3초면 눈에 띄게 움직인다',
      );
    });

    testWidgets('⚠️ 가운데 내 원은 자리를 지킨다', (tester) async {
      // 맴도는 것은 둘레다. 내가 같이 움직이면 중심이 사라진다.
      await tester.pumpWidget(appOf(withMinsu));
      final before = tester.getCenter(find.text('지'));

      await tester.pump(const Duration(seconds: 3));

      expect(tester.getCenter(find.text('지')), before);
    });
  });
}
