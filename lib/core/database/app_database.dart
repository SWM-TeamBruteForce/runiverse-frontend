import 'package:sqflite/sqflite.dart';

/// 앱이 쓰는 SQLite 하나를 연다.
///
/// **스키마와 마이그레이션이 여기 한 곳에 있다.** 테이블마다 흩어 놓으면
/// 버전을 올릴 때 무엇을 고쳐야 하는지 찾아다니게 된다.
///
/// ## 왜 클래스가 아니라 함수인가
///
/// 전역에 `Database`를 들고 있으면 테스트끼리 오염된다. 누가 언제 하나만
/// 쓸지는 provider가 정하게 두고, 이 파일은 **여는 법만** 안다
/// (`dio_client.dart`와 같은 판단).
///
/// ## 여기 저장하는 것은 "기록"이 아니다
///
/// 러닝 기록의 원본은 서버다. 로컬에 남기는 것은 **아직 서버가 받았는지 모르는
/// 좌표 트랙**이고, `RUNNING_FINISHED` ack를 받으면 지운다
/// (`docs/specs/2026-08-26-running-websocket-design.md` 1·6절).
abstract final class AppDatabase {
  /// 파일 이름. 기기의 앱 전용 DB 폴더에 만들어진다.
  static const fileName = 'runiverse.db';

  /// 스키마 버전. **올릴 때는 [_upgrade]에 옮기는 법을 함께 적는다.**
  static const version = 1;

  /// 서버로 보낼 좌표를 담아 두는 곳.
  ///
  /// ## 컬럼이 페이로드와 1:1이다
  ///
  /// 재전송할 때 변환 없이 그대로 실어 보낸다. 중간 형식을 두면 저장할 때와
  /// 보낼 때 값이 갈릴 자리가 생긴다.
  ///
  /// ## 복합 PK가 서버의 중복 제거 키와 같다
  ///
  /// 서버가 `(runningRoomId, userId, sequence)`로 거른다. 로컬에서도 같은 조합을
  /// PK로 두면 **같은 좌표를 두 번 넣는 실수를 DB가 막고**, 순서대로 읽는
  /// 인덱스도 함께 얻는다.
  ///
  /// ## "보냈음" 플래그가 없다
  ///
  /// 어디까지 보냈는지는 메모리에만 든다. 컬럼을 두면 **"보냈다고 표시됐는데
  /// 서버는 못 받은"** 상태가 남는다.
  static const trackPoints = 'run_track_points';

  static const _createTrackPoints =
      '''
    CREATE TABLE $trackPoints (
      running_room_id  INTEGER NOT NULL,
      sequence         INTEGER NOT NULL,
      latitude         REAL    NOT NULL,
      longitude        REAL    NOT NULL,
      altitude_meters  REAL,
      accuracy_meters  REAL    NOT NULL,
      speed_mps        REAL    NOT NULL,
      heading_degrees  REAL,
      cadence_spm      INTEGER,
      pace_sec_per_km  INTEGER,
      recorded_at      TEXT    NOT NULL,
      PRIMARY KEY (running_room_id, sequence)
    )
  ''';

  /// DB를 연다. 없으면 만든다.
  ///
  /// [path]를 받는 이유는 **테스트가 메모리 DB를 쓰기 위해서**다.
  /// 기기에서는 `getDatabasesPath()`로 얻은 경로를 넘긴다.
  static Future<Database> open(String path) => openDatabase(
    path,
    version: version,
    onCreate: (db, version) async => db.execute(_createTrackPoints),
    onUpgrade: _upgrade,
    // ⚠️ sqflite는 외래 키를 **연결마다 켜야 한다.** 지금은 테이블이 하나라
    // 쓸 일이 없지만, 나중에 테이블이 늘 때 이 줄이 없으면 `ON DELETE CASCADE`가
    // 조용히 동작하지 않는다.
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  );

  /// 스키마를 올린다.
  ///
  /// **`version`을 올리면 여기에 `if (oldVersion < N)` 블록을 더한다.**
  /// 지금은 버전 1뿐이라 할 일이 없다.
  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 버전 2가 생기면 여기서 갈라진다.
  }
}
