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
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['recordedAt'], '2026-07-25T19:10:30');
    });

    test('한 자리 수는 0으로 채운다', () {
      final json = TrackPoint.from(
        geo(at: DateTime(2026, 1, 2, 3, 4, 5)),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['recordedAt'], '2026-01-02T03:04:05');
    });

    test('⚠️ UTC로 들어와도 로컬 시각으로 나간다', () {
      // `Position.timestamp`가 UTC로 온다. 그대로 자르면 9시간 어긋난 기록이
      // 쌓이는데 에러가 나지 않아 한참 뒤에 발견된다.
      final utc = DateTime.utc(2026, 7, 25, 10, 10, 30);
      final json = TrackPoint.from(
        geo(at: utc),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['recordedAt'], TrackPoint.formatServerTime(utc.toLocal()));
      expect(json['recordedAt'], isNot(contains('Z')));
    });
  });

  group('페이로드 모양', () {
    test('필드 열한 개가 그대로 담긴다', () {
      final json = TrackPoint.from(
        geo(),
        sequence: 15,
        pauseSegment: 0,
      ).toJson();

      expect(
        json.keys,
        containsAll([
          'sequence',
          'pauseSegment',
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
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json.containsKey('runningRoomId'), isFalse);
    });
  });

  group('값 다듬기', () {
    test('⚠️ 방향을 모르면 0으로 보낸다', () {
      // 명세가 0~360이고 nullable 표기가 없다.
      final json = TrackPoint.from(
        geo(heading: null),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['headingDegrees'], 0);
    });

    test('방향을 알면 그대로 보낸다', () {
      final json = TrackPoint.from(
        geo(heading: 85.3),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['headingDegrees'], 85.3);
    });

    test('⚠️ 속도가 음수면 0으로 보낸다', () {
      // 센서가 못 구하면 음수가 온다. 음수 속도를 서버에 보낼 이유가 없다.
      final json = TrackPoint.from(
        geo(speed: -1),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['speedMetersPerSecond'], 0);
    });

    test('고도는 모르면 null 그대로 간다', () {
      // 명세도 nullable이다. 0으로 채우면 "해수면"이라는 거짓이 된다.
      final json = TrackPoint.from(
        geo(altitude: null),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json['altitudeMeters'], isNull);
    });

    test('페이스는 초 단위 정수로 간다', () {
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 0,
        currentPace: const Duration(minutes: 5, seconds: 45),
      ).toJson();

      expect(json['currentPaceSecondsPerKm'], 345);
    });
  });

  /// 일시정지 구간 번호 — 1.1.1 2절.
  ///
  /// ## ⚠️ 틀리면 배치가 통째로 사라진다
  ///
  /// 빠지면 `INVALID_REQUEST`, 순번 순으로 줄어들면
  /// `PAUSE_SEGMENT_DECREASED`다. 어느 쪽이든 **그 배치의 좌표가 하나도
  /// 저장되지 않는다** — 뛴 구간이 기록에 안 남는다.
  group('일시정지 구간 번호', () {
    test('⚠️ 0이어도 키가 담긴다', () {
      // 0을 "없음"으로 보고 빼면 **모든 러닝의 첫 구간이 거부된다.**
      // 멈추기 전 좌표는 전부 0이라 그게 대부분이다.
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 0,
      ).toJson();

      expect(json.containsKey('pauseSegment'), isTrue);
      expect(json['pauseSegment'], 0);
    });

    test('올라간 번호가 그대로 간다', () {
      final json = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 3,
      ).toJson();

      expect(json['pauseSegment'], 3);
    });

    test('⚠️ 번호를 바꾼 사본은 둘 다 바뀐다', () {
      // 순번만 밀고 구간 번호를 두면, 되살린 번호보다 작은 값이 그대로 나가
      // 배치가 거부된다. 한쪽만 바꾸는 길을 아예 두지 않았다.
      final moved = TrackPoint.from(
        geo(),
        sequence: 1,
        pauseSegment: 0,
      ).withNumbers(sequence: 120, pauseSegment: 2);

      expect(moved.sequence, 120);
      expect(moved.pauseSegment, 2);
      // 나머지는 그대로다.
      expect(moved.latitude, 35.1795543);
      expect(moved.recordedAt, DateTime(2026, 7, 25, 19, 10, 30));
    });
  });
}
