import 'package:dio/dio.dart';
import 'package:runiverse/core/network/dio_client.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/notification/domain/device_repository.dart';

/// 진짜 서버를 부르는 [DeviceRepository]. 명세 2-1.
///
/// 401이면 **한 번만** 갱신하고 다시 부른다. 갱신은 [TokenRefresher]를 거친다 —
/// 로그인 직후에 알림·상태 조회와 거의 동시에 나가서, 직접 갱신하면 겹칠 수
/// 있다(`docs/implementation-notes.md` 9-6).
class HttpDeviceRepository implements DeviceRepository {
  HttpDeviceRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static const _path = '/api/v1/users/me/devices';

  @override
  Future<void> register({
    required String deviceId,
    required String pushToken,
  }) async {
    final accessToken = (await _store.read()).accessToken;
    if (accessToken == null) {
      throw const DeviceException(DeviceFailure.sessionExpired);
    }

    final body = {'deviceId': deviceId, 'pushToken': pushToken};
    try {
      await _post(body, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw exceptionOf(error);
      final refreshed = await _refresher.refresh();
      if (refreshed == null) {
        throw const DeviceException(DeviceFailure.sessionExpired);
      }
      try {
        await _post(body, refreshed);
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  Future<void> _post(Map<String, String> body, String accessToken) =>
      _dio.post<void>(
        _path,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  static DeviceException exceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const DeviceException(DeviceFailure.network);
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401) {
      return const DeviceException(DeviceFailure.sessionExpired);
    }
    if (isUpdateRequired(status, error.response?.data)) {
      return const DeviceException(DeviceFailure.updateRequired);
    }
    if (status >= 500) return const DeviceException(DeviceFailure.network);
    return const DeviceException(DeviceFailure.unknown);
  }
}
