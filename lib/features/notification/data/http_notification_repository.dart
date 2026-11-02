import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/notification/data/notification_dto.dart';
import 'package:runiverse/features/notification/domain/notification_page_result.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';

/// 진짜 서버를 부르는 [NotificationRepository].
///
/// 401 한 번 갱신은 다른 저장소와 같은 규칙이다. 갱신은 반드시
/// [TokenRefresher]를 거친다(`docs/implementation-notes.md` 9-6).
class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static const _path = '/api/v1/users/me/notifications';
  static const _readPath = '$_path/read';

  /// 서버 상한. 넘겨 보내면 400이다.
  static const maxLimit = 50;

  @override
  Future<NotificationPageResult> list({String? cursor, int limit = 20}) =>
      _authorized((token) async {
        final response = await _dio.get<Map<String, dynamic>>(
          _path,
          queryParameters: {
            // ⚠️ **빈 커서를 보내지 않는다.** 첫 페이지는 아예 생략한다 —
            // 빈 문자열을 보내면 형식이 틀렸다고 400을 자초한다.
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            'limit': limit > maxLimit ? maxLimit : limit,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return notificationPageFromJson(response.data);
      });

  @override
  Future<void> readAll() => _authorized((token) async {
    // 여러 번 불러도 204다. 눌렀는지 세어 가며 막을 필요가 없다.
    await _dio.post<void>(
      _readPath,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  static NotificationException exceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const NotificationException(NotificationFailure.network);
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401) {
      return const NotificationException(NotificationFailure.sessionExpired);
    }
    // 5xx는 사용자가 할 일이 네트워크 실패와 같다 — 다시 열어 보는 것뿐이다.
    if (status >= 500) {
      return const NotificationException(NotificationFailure.network);
    }
    return const NotificationException(NotificationFailure.unknown);
  }

  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const NotificationException(NotificationFailure.sessionExpired);
    }

    try {
      return await call(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw exceptionOf(error);
      try {
        return await call(await _refreshed());
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const NotificationException(NotificationFailure.sessionExpired);
    }
    return accessToken;
  }
}
