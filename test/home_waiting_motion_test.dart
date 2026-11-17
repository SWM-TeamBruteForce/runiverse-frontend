import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
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
  Widget appOf(RoomInfo room, {double width = 412}) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: HomeWaiting(room: room, onLobby: () {}, myUserId: 'me'),
      ),
    ),
  );

  final meAlone = roomOf([player('me', '지환')]);
  final withMinsu = roomOf([player('me', '지환'), player('u2', '민수')]);

  /// 그 사람의 축하가 떠 있는가.
  ///
  /// ⚠️ **문장을 한 덩이로 찾지 않는다.** 화면은 닉네임과 `님이 합류했어요`를
  /// 따로 세운다 — 긴 닉네임만 줄이려면 그래야 한다.
  ///
  /// 닉네임 **전체**가 글자로 나오는 자리는 축하 카드뿐이다. 궤도의 아바타는
  /// 첫 글자만 그리고, 안내 줄에는 이름이 없다.
  Finder celebrates(String nickname) => find.text(nickname);

  /// 아직 사람이 안 들어온 빈 자리.
  Finder emptySlots() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('home-waiting-empty'),
  );

  group('합류 축하', () {
    testWidgets('파티원이 늘면 닉네임과 함께 뜬다', (tester) async {
      await tester.pumpWidget(appOf(meAlone));
      expect(celebrates('민수'), findsNothing);

      await tester.pumpWidget(appOf(withMinsu));
      await tester.pump(const Duration(milliseconds: 100));

      expect(celebrates('민수'), findsOneWidget);
      expect(find.text(AppStrings.homePlayerJoinedSuffix), findsOneWidget);
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

      expect(find.text(AppStrings.homePlayerJoinedSuffix), findsNothing);
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
      // `합류했어요`가 먼저 잘린다.
      await tester.pumpWidget(appOf(meAlone));
      await tester.pumpWidget(
        appOf(roomOf([player('me', '지환'), player('u2', '열여섯글자까지받는닉네임')])),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final nickname = tester.widget<Text>(find.text('열여섯글자까지받는닉네임'));
      expect(nickname.overflow, TextOverflow.ellipsis);
      expect(nickname.maxLines, 1);
      // 뒷말은 따로 선다 — 잘리지 않는다.
      expect(find.text(AppStrings.homePlayerJoinedSuffix), findsOneWidget);
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

  group('찾는 중인 빈 자리', () {
    testWidgets('⚠️ 혼자 기다리는 동안에도 빈 원이 돈다', (tester) async {
      // 아무도 없을 때 둘레가 텅 비면 **찾고 있는 것인지 멈춘 것인지** 알 수
      // 없다. 신청 직후가 가장 오래 보는 화면인데 거기가 정지 화면이었다.
      await tester.pumpWidget(appOf(meAlone));
      expect(emptySlots(), findsNWidgets(3));

      final before = tester.getCenter(emptySlots().first);
      await tester.pump(const Duration(seconds: 1));

      expect(
        (tester.getCenter(emptySlots().first) - before).distance,
        greaterThan(8),
        reason: '빈 원도 사람 원과 같이 움직인다',
      );
    });

    testWidgets('사람이 들어온 자리는 빈 원이 비켜준다', (tester) async {
      // 빈 원이 그대로 남으면 들어온 사람 위에 겹친다.
      await tester.pumpWidget(appOf(withMinsu));

      expect(emptySlots(), findsNWidgets(2));
    });
  });

  group('맴도는 원', () {
    testWidgets('⚠️ 시간이 지나면 자리를 옮긴다', (tester) async {
      await tester.pumpWidget(appOf(withMinsu));
      final before = tester.getCenter(find.text('민'));

      await tester.pump(const Duration(seconds: 1));
      final after = tester.getCenter(find.text('민'));

      expect(
        (after - before).distance,
        greaterThan(8),
        reason: '1초만 봐도 움직이는 것이 보여야 한다',
      );
    });

    testWidgets('⚠️ 원마다 따로 움직인다', (tester) async {
      // 같은 위상으로 흔들면 셋이 한 몸처럼 기울어진다 — 움직임이 아니라
      // 화면이 흔들리는 것으로 보인다.
      await tester.pumpWidget(
        appOf(
          roomOf([player('me', '지환'), player('u2', '민수'), player('u3', '하늘')]),
        ),
      );
      final minsu = tester.getCenter(find.text('민'));
      final haneul = tester.getCenter(find.text('하'));

      await tester.pump(const Duration(milliseconds: 900));

      final movedMinsu = (tester.getCenter(find.text('민')) - minsu).distance;
      final movedHaneul = (tester.getCenter(find.text('하')) - haneul).distance;
      expect(
        (movedMinsu - movedHaneul).abs(),
        greaterThan(4),
        reason: '위상이 같으면 둘이 똑같이 움직인다',
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

  group('⚠️ 폭마다 둘레 원이 제자리에 머문다', () {
    // 궤도 값(반지름·흔들림·드나듦·원 크기)은 카드 폭 352에서 카드 끝·버튼·
    // 안내 줄·내 사진·서로와 닿지 않게 맞췄고, 다른 폭에서는 가로만 늘이고
    // 줄인다(`home_waiting.dart` `_stretchOf`). 원 크기는 그대로라 카드 끝과의
    // 틈이 폭을 따라 준다 — 352에서 7, 320dp 폰(288)에서 0.3이다.
    //
    // 카드 폭은 320·360·384·412·440dp 폰에서 양옆 16씩 뺀 값이다.
    bool apart(Rect a, Rect b) =>
        (a.center - b.center).distance >= a.width / 2 + b.width / 2;

    final full = roomOf([
      player('me', '지환'),
      player('u2', '민수'),
      player('u3', '하늘'),
      player('u4', '서연'),
    ]);

    for (final width in [288.0, 328.0, 352.0, 380.0, 408.0]) {
      for (final (label, room) in [('빈 자리 셋', meAlone), ('셋이 들어옴', full)]) {
        testWidgets('폭 $width · $label', (tester) async {
          await tester.pumpWidget(appOf(room, width: width));
          final card = tester.getRect(find.byType(HomeWaiting));
          final button = tester.getRect(find.byType(AppButtonV2));
          final hint = tester.getRect(
            find.text(AppStrings.homeMatchWaitingHint),
          );

          // 각도(6.2초)와 반지름(4.1초) 주기를 둘 다 한 바퀴 넘게 훑는다. 두
          // 끝이 같은 순간까지는 못 봐 1px 안쪽 넘침은 놓친다. 주기를 늘리면
          // 이 창도 늘린다.
          for (var step = 1; step <= 70; step++) {
            await tester.pump(const Duration(milliseconds: 100));
            final at = '폭 $width · ${step * 100}ms';

            final avatars = [
              for (final e in find.byType(RunnerAvatarV2).evaluate())
                tester.getRect(find.byWidget(e.widget)),
            ]..sort((a, b) => b.width.compareTo(a.width));
            // 가장 큰 것이 가운데 나다.
            final me = avatars.first;
            final circles = [
              ...avatars.skip(1),
              for (final e in emptySlots().evaluate())
                tester.getRect(find.byWidget(e.widget)),
            ];
            expect(circles, hasLength(3));

            for (final (i, r) in circles.indexed) {
              expect(
                r.left >= card.left - .01 && r.right <= card.right + .01,
                isTrue,
                reason: '$at: $i번 원이 카드 밖으로 나갔다',
              );
              expect(r.top >= hint.bottom, isTrue, reason: '$at: 안내 줄을 덮는다');
              expect(r.bottom <= button.top, isTrue, reason: '$at: 버튼을 덮는다');
              expect(apart(r, me), isTrue, reason: '$at: 내 사진과 닿는다');
              for (final other in circles.skip(i + 1)) {
                expect(apart(r, other), isTrue, reason: '$at: 원끼리 닿는다');
              }
            }
          }
        });
      }
    }
  });
}
