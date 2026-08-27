import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/track_point.dart';

/// 서버로 보낼 좌표 — **모양이 정확히 맞는가.**
///
/// 여기서 틀리면 서버가 400을 주거나, 더 나쁘게는 **말없이 잘못된 값을 받는다.**
/// 시각이 그렇다 — 9시간 어긋나도 에러가 나지 않는다.
void main() {
  GeoPoint geo({
    double speed = 2.8,
    double? altitude,
    double? heading,
    DateTime? at,
  }) => GeoPoint(
    latitude: 35.1795543,
    longitude: 129.0756416,
    recordedAt: at ?? DateTime(2026, 7, 25, 19, 10, 30),
    accuracy: 6.2,
    speed: speed,
    altitude: altitude,
    heading: heading,
  );

  group('시각 형식', () {
    test('오프셋도 마이크로초도 붙지 않는다', () {
      final json = TrackPoint.from(geo(), sequence: 1).toJson();

      expect(json['recordedAt'], '2026-07-25T19:10:30');
    });

    test('한 자리 수는 0으로 채운다', () {
      final json = TrackPoint.from(
        geo(at: DateTime(2026, 1, 2, 3, 4, 5)),
        sequence: 1,
      ).toJson();

      expect(json['recordedAt'], '2026-01-02T03:04:05');
    });

    test('⚠️ UTC로 들어와도 로컬 시각으로 나간다', () {
      // `Position.timestamp`가 UTC로 온다. 그대로 자르면 9시간 어긋난 기록이
      // 쌓이는데 에러가 나지 않아 한참 뒤에 발견된다.
      final utc = DateTime.utc(2026, 7, 25, 10, 10, 30);
      final json = TrackPoint.from(geo(at: utc), sequence: 1).toJson();

      expect(json['recordedAt'], TrackPoint.formatServerTime(utc.toLocal()));
      expect(json['recordedAt'], isNot(contains('Z')));
    });
  });

  group('페이로드 모양', () {
    test('필드 열 개가 그대로 담긴다', () {
      final json = TrackPoint.from(geo(), sequence: 15).toJson();

      expect(
        json.keys,
        containsAll([
          'sequence',
          'latitude',
          'longitude',
          'altitudeMeters',
          'accuracyMeters',
          'speedMetersPerSecond',
          'headingDegrees',
          'cadenceSpm',
          'currentPaceSecondsPerKm',
          'recordedAt',
        ]),
      );
    });

    test('⚠️ runningRoomId는 들어가지 않는다', () {
      // 방 번호는 RUNNING_START에서 한 번만 보낸다.
      final json = TrackPoint.from(geo(), sequence: 1).toJson();

      expect(json.containsKey('runningRoomId'), isFalse);
    });
  });

  group('값 다듬기', () {
    test('⚠️ 방향을 모르면 0으로 보낸다', () {
      // 명세가 0~360이고 nullable 표기가 없다.
      final json = TrackPoint.from(geo(heading: null), sequence: 1).toJson();

      expect(json['headingDegrees'], 0);
    });

    test('방향을 알면 그대로 보낸다', () {
      final json = TrackPoint.from(geo(heading: 85.3), sequence: 1).toJson();

      expect(json['headingDegrees'], 85.3);
    });

    test('⚠️ 속도가 음수면 0으로 보낸다', () {
      // 센서가 못 구하면 음수가 온다. 음수 속도를 서버에 보낼 이유가 없다.
      final json = TrackPoint.from(geo(speed: -1), sequence: 1).toJson();

      expect(json['speedMetersPerSecond'], 0);
    });

    test('고도는 모르면 null 그대로 간다', () {
      // 명세도 nullable이다. 0으로 채우면 "해수면"이라는 거짓이 된다.
      final json = TrackPoint.from(geo(altitude: null), sequence: 1).toJson();

      expect(json['altitudeMeters'], isNull);
    });

    test('페이스는 초 단위 정수로 간다', () {
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        currentPace: const Duration(minutes: 5, seconds: 45),
      ).toJson();

      expect(json['currentPaceSecondsPerKm'], 345);
    });
  });
}
