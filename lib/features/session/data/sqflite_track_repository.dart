import 'package:runiverse/core/database/app_database.dart';
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
    await db.delete(
      AppDatabase.trackPoints,
      where: 'running_room_id = ?',
      whereArgs: [runningRoomId],
    );
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

  // ── 행 ↔ 값 ──────────────────────────────────────────────

  static Map<String, Object?> _toRow(int runningRoomId, TrackPoint p) => {
    'running_room_id': runningRoomId,
    'sequence': p.sequence,
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
