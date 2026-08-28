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
  ///
  /// 2 — `active_run` 추가 (2026-08-28).
  static const version = 2;

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

  /// 지금 진행 중인 러닝의 방 번호를 담는 곳. **행이 하나뿐이다.**
  ///
  /// ## 왜 필요한가
  ///
  /// 방 번호는 `POST /running-rooms/solo`가 201로 준다. 그걸 안 남기고 앱이
  /// 죽으면 **그 방을 끝낼 방법이 사라진다** — 서버에는 `STARTED` 방이 남고,
  /// 다음 러닝은 영원히 409를 맞는다.
  ///
  /// 되찾을 경로가 없기 때문이다. 409 응답에는 방 번호가 없고,
  /// `GET /users/me/running-match`는 **매칭** 조회라 `state`에 `STARTED`를
  /// 표현할 값조차 없다. 받은 순간 남겨 두는 것이 유일한 방법이다.
  ///
  /// ## 트랙과 같은 DB에 둔다
  ///
  /// **번호와 좌표는 정확히 같은 순간에 지워져야 한다**(`RUNNING_FINISHED` ack).
  /// 다른 저장소에 나누면 한쪽만 지워진 상태가 생긴다.
  ///
  /// ## ⚠️ 기기 안에서만 안다
  ///
  /// 앱을 지웠다 다시 깔거나 다른 기기에서 로그인하면 비어 있다. 그때는 서버가
  /// 409에 방 번호를 실어 주지 않는 한 앱이 풀 수 없다.
  static const activeRun = 'active_run';

  /// `id`를 1로 고정해 **행이 둘이 될 수 없게** 한다. `INSERT OR REPLACE`가
  /// 언제나 같은 행을 덮어쓴다.
  static const _createActiveRun =
      '''
    CREATE TABLE $activeRun (
      id               INTEGER PRIMARY KEY CHECK (id = 1),
      running_room_id  INTEGER NOT NULL,
      started_at       TEXT    NOT NULL
    )
  ''';

  /// DB를 연다. 없으면 만든다.
  ///
  /// [path]를 받는 이유는 **테스트가 메모리 DB를 쓰기 위해서**다.
  /// 기기에서는 `getDatabasesPath()`로 얻은 경로를 넘긴다.
  static Future<Database> open(String path) => openDatabase(
    path,
    version: version,
    onCreate: (db, version) async {
      await db.execute(_createTrackPoints);
      await db.execute(_createActiveRun);
    },
    onUpgrade: _upgrade,
    // ⚠️ sqflite는 외래 키를 **연결마다 켜야 한다.** 지금은 테이블이 하나라
    // 쓸 일이 없지만, 나중에 테이블이 늘 때 이 줄이 없으면 `ON DELETE CASCADE`가
    // 조용히 동작하지 않는다.
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  );

  /// 스키마를 올린다.
  ///
  /// **`version`을 올리면 여기에 `if (oldVersion < N)` 블록을 더한다.**
  ///
  /// ⚠️ **기존 테이블을 지우지 않는다.** 여기 있는 것은 아직 서버가 받았는지
  /// 모르는 좌표라, 앱을 올렸다고 버리면 그 구간이 통째로 사라진다.
  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 진행 중인 방 번호를 남기지 않아 409를 못 풀던 것을 고친다.
    if (oldVersion < 2) await db.execute(_createActiveRun);
  }
}
