import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

/// 앱이 쓰는 SQLite 하나.
///
/// `FutureProvider`가 **결과를 캐시한다.** 여러 번 읽어도 파일은 한 번만 열린다.
///
/// ## ⚠️ 쓰는 쪽에 `AsyncValue`를 물려주지 않는다
///
/// 저장소를 `FutureProvider`로 두면 좌표를 쌓을 때마다 로딩 상태를 갈라야 한다.
/// 대신 저장소가 **`Future<Database>`를 주는 함수**를 받아 필요할 때 기다린다
/// (`trackRepositoryProvider` 참조). 좌표를 쌓는 쪽은 DB가 언제 열렸는지 모른다.
final databaseProvider = FutureProvider<Database>((ref) async {
  // `path` 패키지를 쓰지 않는다. 안드로이드 경로는 `/`로 이어 붙이면 된다.
  final path = '${await getDatabasesPath()}/${AppDatabase.fileName}';
  final db = await AppDatabase.open(path);
  // provider가 버려지면 닫는다. 안 닫으면 파일 핸들이 남는다.
  ref.onDispose(db.close);
  return db;
});
