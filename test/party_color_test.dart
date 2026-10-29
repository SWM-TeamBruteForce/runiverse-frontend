import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/features/session/domain/party_color.dart';

/// 파티 색의 자리.
///
/// ## ⚠️ 전에는 세 화면이 각자 정했다
///
/// 러닝 중 화면은 명단 순서를 그대로 써서 **방마다 내 색이 바뀌었고**, 결과
/// 화면은 나를 파랑으로 고정했고, 카운트다운은 그리는 순서대로 줬다. 같은
/// 러닝을 세 화면에서 보면 색이 세 벌이었다(개발자 확인 2026-10-29).
void main() {
  group('나는 늘 0번이다', () {
    test('명단 첫째여도 0번', () {
      expect(
        partyColorSlot(userId: 'me', myUserId: 'me', order: ['me', 'a', 'b']),
        0,
      );
    });

    test('⚠️ 명단 둘째여도 0번', () {
      // 전에는 여기서 1번(주황)을 받았다.
      expect(
        partyColorSlot(userId: 'me', myUserId: 'me', order: ['a', 'me', 'b']),
        0,
      );
    });

    test('명단 꼴찌여도 0번', () {
      expect(
        partyColorSlot(userId: 'me', myUserId: 'me', order: ['a', 'b', 'me']),
        0,
      );
    });

    test('⚠️ 명단에 내가 없어도 0번', () {
      // 솔로·재시작에서 명단이 나를 빠뜨릴 수 있다.
      expect(
        partyColorSlot(userId: 'me', myUserId: 'me', order: ['a', 'b']),
        0,
      );
    });
  });

  group('나머지는 나를 뺀 순서로 1번부터', () {
    test('내가 가운데여도 상대 순서는 그대로다', () {
      const order = ['a', 'me', 'b', 'c'];
      expect(partyColorSlot(userId: 'a', myUserId: 'me', order: order), 1);
      expect(partyColorSlot(userId: 'b', myUserId: 'me', order: order), 2);
      expect(partyColorSlot(userId: 'c', myUserId: 'me', order: order), 3);
    });

    test('⚠️ 아무도 내 파랑을 가져가지 않는다', () {
      const order = ['a', 'me', 'b', 'c'];
      for (final id in ['a', 'b', 'c']) {
        expect(
          partyColorSlot(userId: id, myUserId: 'me', order: order),
          isNot(0),
          reason: id,
        );
      }
    });

    test('정원 4명이 팔레트 4색에 꼭 맞는다', () {
      const order = ['me', 'a', 'b', 'c'];
      final slots = [
        for (final id in order)
          partyColorSlot(userId: id, myUserId: 'me', order: order),
      ];

      expect(slots.toSet(), {0, 1, 2, 3});
      expect(partyColorSlots, 4);
    });

    test('⚠️ 모르는 사람은 끝 색이다 — 0으로 떨어뜨리지 않는다', () {
      // 0은 내 파랑이라, 거기로 떨어지면 남이 나로 보인다.
      expect(
        partyColorSlot(userId: 'nobody', myUserId: 'me', order: ['me', 'a']),
        partyColorSlots - 1,
      );
    });
  });

  group('내가 누구인지 모를 때', () {
    test('아무도 0번을 비워 두지 않는다 — 순서대로 받는다', () {
      // 로그인 상태를 못 읽은 화면이다. 파랑을 비워 두면 한 칸이 영영 빈다.
      const order = ['a', 'b'];
      expect(partyColorSlot(userId: 'a', myUserId: null, order: order), 1);
      expect(partyColorSlot(userId: 'b', myUserId: null, order: order), 2);
    });
  });

  group('0번은 브랜드 파랑이다', () {
    test('테마의 primary와 같은 값이다', () {
      // 어느 화면에서든 내 것을 찾는 눈이 흔들리지 않게 하는 근거다.
      expect(RunPaletteV2.lane(0), AppColorsV2.dark.primary);
    });

    test('네 색이 서로 다르다', () {
      final colors = [
        for (var i = 0; i < partyColorSlots; i++) RunPaletteV2.lane(i),
      ];

      expect(colors.toSet(), hasLength(partyColorSlots));
    });
  });
}
