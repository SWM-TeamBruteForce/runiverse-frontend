import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/database/app_database.dart';
import 'package:runiverse/features/session/data/sqflite_track_repository.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 로컬 트랙 저장 — **서버로 보낼 좌표를 잠시 맡아 두는 곳.**
///
/// 기록 저장소가 아니다. `RUNNING_FINISHED` ack를 받으면 지운다.
///
/// ## 진짜 SQLite로 돌린다
///
/// `sqflite_common_ffi`가 Dart VM에서 SQLite를 띄운다. 가짜로 흉내 내면
/// **스키마 오타와 복합 PK 동작을 못 잡는다** — 정작 확인하고 싶은 것들이다.
void main() {
  // 기기가 아니라 Dart VM에서 돌리기 위한 준비. 파일 맨 앞에서 한 번만 한다.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteTrackRepository repository;

  const roomA = 100;
  const roomB = 200;

  /// 좌표 하나. 값 자체는 중요하지 않고 **순번이 중요하다.**
  TrackPoint point(int sequence, {double? heading, int? pace}) => TrackPoint(
    sequence: sequence,
    latitude: 37.5 + sequence * 0.0001,
    longitude: 127.0,
    accuracyMeters: 5,
    speedMetersPerSecond: 2.8,
    headingDegrees: heading,
    currentPaceSecondsPerKm: pace,
    recordedAt: DateTime(2026, 8, 26, 19, 10, sequence),
  );

  setUp(() async {
    // `:memory:` — 파일을 만들지 않아 테스트끼리 오염되지 않는다.
    db = await AppDatabase.open(inMemoryDatabasePath);
    repository = SqfliteTrackRepository(() async => db);
  });

  tearDown(() => db.close());

  group('쌓기', () {
    test('넣은 만큼 쌓인다', () async {
      await repository.add(roomA, point(1));
      await repository.add(roomA, point(2));

      expect(await repository.count(roomA), 2);
    });

    test('⚠️ 같은 순번을 두 번 넣어도 죽지 않는다', () async {
      // 재시도 경로에서 중복 저장이 생겨도 러닝이 멈추면 안 된다.
      await repository.add(roomA, point(1));
      await repository.add(roomA, point(1));

      expect(await repository.count(roomA), 1);
    });

    test('⚠️ 다른 러닝의 좌표는 섞이지 않는다', () async {
      // 이전 러닝이 남아 있는데 새 러닝 좌표와 섞이면 경로가 엉킨다.
      await repository.add(roomA, point(1));
      await repository.add(roomB, point(1));

      expect(await repository.count(roomA), 1);
      expect(await repository.count(roomB), 1);
    });
  });

  group('읽기', () {
    test('순번 순서대로 나온다', () async {
      // 순서가 곧 경로다. 뒤섞이면 서버가 엉뚱한 선을 긋는다.
      await repository.add(roomA, point(3));
      await repository.add(roomA, point(1));
      await repository.add(roomA, point(2));

      final points = await repository.after(roomA);

      expect(points.map((p) => p.sequence), [1, 2, 3]);
    });

    test('지정한 순번 이후만 나온다', () async {
      for (var i = 1; i <= 5; i++) {
        await repository.add(roomA, point(i));
      }

      final points = await repository.after(roomA, afterSequence: 3);

      expect(points.map((p) => p.sequence), [4, 5]);
    });

    test('⚠️ limit으로 나눠 읽는다', () async {
      // 30분 러닝이면 1,800점이다. 한 프레임에 다 실으면 200KB가 넘는다.
      for (var i = 1; i <= 10; i++) {
        await repository.add(roomA, point(i));
      }

      final first = await repository.after(roomA, limit: 4);

      expect(first.map((p) => p.sequence), [1, 2, 3, 4]);
    });

    test('빈 러닝은 빈 목록이다', () async {
      expect(await repository.after(roomA), isEmpty);
      expect(await repository.count(roomA), 0);
    });
  });

  group('값 보존', () {
    test('넣은 값이 그대로 나온다', () async {
      await repository.add(roomA, point(1, heading: 85.3, pace: 345));

      final read = (await repository.after(roomA)).single;

      expect(read.sequence, 1);
      expect(read.headingDegrees, 85.3);
      expect(read.currentPaceSecondsPerKm, 345);
      expect(read.accuracyMeters, 5);
    });

    test('⚠️ 모르는 값은 null로 남는다', () async {
      // 0으로 채우면 "정북"이나 "페이스 0초"라는 거짓이 된다.
      await repository.add(roomA, point(1));

      final read = (await repository.after(roomA)).single;

      expect(read.headingDegrees, isNull);
      expect(read.currentPaceSecondsPerKm, isNull);
      expect(read.cadenceSpm, isNull);
      expect(read.altitudeMeters, isNull);
    });

    test('시각이 초 단위로 되살아난다', () async {
      await repository.add(roomA, point(7));

      final read = (await repository.after(roomA)).single;

      expect(read.recordedAt, DateTime(2026, 8, 26, 19, 10, 7));
    });
  });

  group('지우기', () {
    test('그 러닝만 지운다', () async {
      await repository.add(roomA, point(1));
      await repository.add(roomB, point(1));

      await repository.clear(roomA);

      expect(await repository.count(roomA), 0);
      expect(await repository.count(roomB), 1);
    });
  });
}
