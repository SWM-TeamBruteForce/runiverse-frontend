import 'package:runiverse/core/database/app_database.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite에 좌표를 쌓는 [TrackRepository].
///
/// SQL이 이 파일 밖으로 새지 않는다. 화면도 컨트롤러도 테이블 이름을 모른다.
class SqfliteTrackRepository implements TrackRepository {
  const SqfliteTrackRepository(this._open);

  /// DB를 주는 함수. **`Database`를 직접 받지 않는다** — 여는 것이 비동기라
  /// 그러면 저장소를 쓰는 쪽이 전부 `AsyncValue`를 다루게 된다.
  final Future<Database> Function() _open;

  @override
  Future<void> add(int runningRoomId, TrackPoint point) async {
    final db = await _open();
    await db.insert(
      AppDatabase.trackPoints,
      _toRow(runningRoomId, point),
      // ⚠️ 같은 `sequence`가 다시 들어오면 **덮어쓴다.** 재시도 경로에서
      // 중복 저장이 생겨도 죽지 않아야 한다. 값이 같으므로 덮어써도 무해하다.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<TrackPoint>> after(
    int runningRoomId, {
    int afterSequence = 0,
    int limit = 100,
  }) async {
    final db = await _open();
    final rows = await db.query(
      AppDatabase.trackPoints,
      where: 'running_room_id = ? AND sequence > ?',
      whereArgs: [runningRoomId, afterSequence],
      // 순서가 곧 경로다. 뒤섞이면 서버가 엉뚱한 선을 긋는다.
      orderBy: 'sequence ASC',
      limit: limit,
    );
    return rows.map(_toPoint).toList();
  }

  @override
  Future<void> clear(int runningRoomId) async {
    final db = await _open();
    // ⚠️ **번호도 같은 호출에서 지운다.** 트랜잭션으로 묶어 둬야 좌표만
    // 지워지고 번호가 남는 상태가 생기지 않는다 — 그 상태로 다음 러닝을
    // 시작하면 첫 좌표가 지난 러닝의 구간 번호를 달고 나간다.
    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.trackPoints,
        where: 'running_room_id = ?',
        whereArgs: [runningRoomId],
      );
      await txn.delete(
        AppDatabase.runNumbers,
        where: 'running_room_id = ?',
        whereArgs: [runningRoomId],
      );
    });
  }

  @override
  Future<RunNumbers?> numbers(int runningRoomId) async {
    final db = await _open();
    final rows = await db.query(
      AppDatabase.runNumbers,
      where: 'running_room_id = ?',
      whereArgs: [runningRoomId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return RunNumbers(
      nextSequence: row['next_sequence']! as int,
      pauseSegment: row['pause_segment']! as int,
    );
  }

  @override
  Future<void> saveNumbers(int runningRoomId, RunNumbers numbers) async {
    final db = await _open();
    await db.insert(AppDatabase.runNumbers, {
      'running_room_id': runningRoomId,
      'next_sequence': numbers.nextSequence,
      'pause_segment': numbers.pauseSegment,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> count(int runningRoomId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.trackPoints} '
      'WHERE running_room_id = ?',
      [runningRoomId],
    );
    final value = rows.first['c'];
    return value is int ? value : 0;
  }

  @override
  Future<int> lastSequence(int runningRoomId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT MAX(sequence) AS s FROM ${AppDatabase.trackPoints} '
      'WHERE running_room_id = ?',
      [runningRoomId],
    );
    // ⚠️ 행이 하나도 없으면 `MAX`가 `NULL`이다. 0으로 받아야 첫 좌표가 1이 된다.
    final value = rows.first['s'];
    return value is int ? value : 0;
  }

  @override
  Future<int?> activeRoom() async {
    final db = await _open();
    final rows = await db.query(AppDatabase.activeRun, limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['running_room_id'] as int?;
  }

  @override
  Future<void> markActiveRoom(int runningRoomId) async {
    final db = await _open();
    await db.insert(AppDatabase.activeRun, {
      // ⚠️ 1로 고정한다. 진행 중인 러닝은 언제나 하나뿐이고, 스키마의
      // `CHECK (id = 1)`이 그것을 강제한다.
      'id': 1,
      'running_room_id': runningRoomId,
      'started_at': TrackPoint.formatServerTime(DateTime.now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearActiveRoom() async {
    final db = await _open();
    await db.delete(AppDatabase.activeRun);
  }

  // ── 행 ↔ 값 ──────────────────────────────────────────────

  static Map<String, Object?> _toRow(int runningRoomId, TrackPoint p) => {
    'running_room_id': runningRoomId,
    'sequence': p.sequence,
    'pause_segment': p.pauseSegment,
    'latitude': p.latitude,
    'longitude': p.longitude,
    'altitude_meters': p.altitudeMeters,
    'accuracy_meters': p.accuracyMeters,
    'speed_mps': p.speedMetersPerSecond,
    'heading_degrees': p.headingDegrees,
    'cadence_spm': p.cadenceSpm,
    'pace_sec_per_km': p.currentPaceSecondsPerKm,
    // ⚠️ **서버 형식 그대로 저장한다.** 읽어서 보낼 때 변환하지 않으므로
    // 저장한 것과 보내는 것이 갈릴 자리가 없다.
    'recorded_at': TrackPoint.formatServerTime(p.recordedAt),
  };

  static TrackPoint _toPoint(Map<String, Object?> row) => TrackPoint(
    sequence: row['sequence']! as int,
    pauseSegment: row['pause_segment']! as int,
    latitude: row['latitude']! as double,
    longitude: row['longitude']! as double,
    altitudeMeters: row['altitude_meters'] as double?,
    accuracyMeters: row['accuracy_meters']! as double,
    speedMetersPerSecond: row['speed_mps']! as double,
    headingDegrees: row['heading_degrees'] as double?,
    cadenceSpm: row['cadence_spm'] as int?,
    currentPaceSecondsPerKm: row['pace_sec_per_km'] as int?,
    // 저장할 때 로컬 시각으로 잘랐으므로 읽을 때도 로컬로 되살린다.
    recordedAt: DateTime.parse(row['recorded_at']! as String),
  );
}
