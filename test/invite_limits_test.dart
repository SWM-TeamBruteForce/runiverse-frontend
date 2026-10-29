import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';

/// 초대 방의 운영값.
///
/// ## ⚠️ 서버가 내려주지 않아 앱이 적어 둔 값이다
///
/// 경계가 틀리면 **고를 수 없는 시각을 권하고** 서버가
/// `INVITE_START_AT_OUT_OF_RANGE`로 거절한다. 매칭은 `slots`가 선택지를
/// 내려줘서 이런 테스트가 필요 없었다.
void main() {
  group('고를 수 있는 시작 시각', () {
    test('바닥은 지금 +11분, 천장은 오늘 23:59다', () {
      final window = InviteLimits.window(nowKst: DateTime(2026, 10, 29, 19));

      expect(window!.from, DateTime(2026, 10, 29, 19, 11));
      expect(window.to, DateTime(2026, 10, 29, 23, 59));
    });

    test('⚠️ 바닥에 1분 여유가 있다', () {
      // 서버 규칙은 +10분이다. 기기 시계가 느리면 화면에서 합법이던 값이
      // 거절되므로 한 칸 민다.
      expect(InviteLimits.minLeadMinutes, 10);
      expect(InviteLimits.pickerLeadMinutes, 11);
    });

    test('23:48에는 아직 고를 수 있다', () {
      final window = InviteLimits.window(
        nowKst: DateTime(2026, 10, 29, 23, 48),
      );

      expect(window, isNotNull);
      expect(window!.from, DateTime(2026, 10, 29, 23, 59));
      expect(window.to, DateTime(2026, 10, 29, 23, 59));
    });

    test('⚠️ 23:49 이후에는 고를 수 있는 시각이 없다', () {
      // 바닥이 천장을 넘는다. 익일 예약은 안 된다 — 빈 피커를 두면 고장으로
      // 읽히므로 화면이 전용 문구로 갈린다.
      expect(
        InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 49)),
        isNull,
      );
      expect(
        InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 59)),
        isNull,
      );
    });

    test('자정 직후에는 하루가 다시 열린다', () {
      final window = InviteLimits.window(nowKst: DateTime(2026, 10, 30, 0, 5));

      expect(window!.from, DateTime(2026, 10, 30, 0, 16));
      expect(window.to, DateTime(2026, 10, 30, 23, 59));
    });

    test('⚠️ 초를 버린다', () {
      // 서버가 분 단위를 받는다. 초가 남으면 400이다.
      final window = InviteLimits.window(
        nowKst: DateTime(2026, 10, 29, 19, 0, 37, 500),
      );

      expect(window!.from.second, 0);
      expect(window.from.millisecond, 0);
      expect(window.from, DateTime(2026, 10, 29, 19, 11));
    });

    test('초가 있어도 경계는 버린 분으로 잰다', () {
      // 23:48:59는 아직 23:48이다. 올려 버리면 멀쩡한 1분을 잃는다.
      expect(
        InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 48, 59)),
        isNotNull,
      );
    });
  });

  group('거리', () {
    test('1,000m ~ 42,195m다', () {
      expect(InviteLimits.minMeters, 1000);
      expect(InviteLimits.maxMeters, 42195);
    });

    test('바로가기가 보내는 값은 5000 · 21098 · 42195다', () {
      expect(InviteLimits.shortcuts.map((s) => s.meters), [5000, 21098, 42195]);
      expect(InviteLimits.shortcuts.map((s) => s.label), ['5km', '하프', '풀']);
    });

    test('⚠️ 하프는 21,097.5를 올린 값이다', () {
      // 정수 미터만 보낼 수 있다. 내리면 공인 거리보다 짧다.
      expect(InviteLimits.halfMeters, 21098);
    });

    test('풀은 상한과 같다', () {
      expect(InviteLimits.fullMeters, InviteLimits.maxMeters);
    });

    test('바로가기는 모두 범위 안이다', () {
      for (final shortcut in InviteLimits.shortcuts) {
        expect(shortcut.meters, greaterThanOrEqualTo(InviteLimits.minMeters));
        expect(shortcut.meters, lessThanOrEqualTo(InviteLimits.maxMeters));
      }
    });

    test('범위를 벗어난 값을 가른다', () {
      expect(InviteLimits.allowsMeters(999), isFalse);
      expect(InviteLimits.allowsMeters(1000), isTrue);
      expect(InviteLimits.allowsMeters(42195), isTrue);
      expect(InviteLimits.allowsMeters(42196), isFalse);
    });
  });

  group('그 밖의 운영값', () {
    test('정원 4명 · 한 친구에게 5회 · 마감 1분 전', () {
      expect(InviteLimits.capacity, 4);
      expect(InviteLimits.maxInvitesPerFriend, 5);
      expect(InviteLimits.closeBeforeMinutes, 1);
    });
  });

  group('거리 표기', () {
    test('⚠️ 어떤 미터값이든 적는다', () {
      // `matchDistanceText`는 km 정수만 받는다. 자유 거리가 그 길로 가면
      // 칸이 그대로 빈다.
      expect(AppStrings.distanceKm(5000), '5km');
      expect(AppStrings.distanceKm(7000), '7km');
      expect(AppStrings.distanceKm(21098), '21.098km');
      expect(AppStrings.distanceKm(42195), '42.195km');
      expect(AppStrings.distanceKm(1000), '1km');
      expect(AppStrings.distanceKm(1500), '1.5km');
    });
  });
}
