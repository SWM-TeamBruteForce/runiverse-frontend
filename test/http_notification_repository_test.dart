import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/notification/data/http_notification_repository.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';

/// 알림 REST.
void main() {
  DioException badResponse(int status, {Object? body}) => DioException(
    requestOptions: RequestOptions(path: '/api/v1/users/me/notifications'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/api/v1/users/me/notifications'),
      statusCode: status,
      data: body,
    ),
  );

  group('실패를 가른다', () {
    test('401은 세션이 끝난 것이다', () {
      expect(
        HttpNotificationRepository.exceptionOf(badResponse(401)).failure,
        NotificationFailure.sessionExpired,
      );
    });

    test('5xx는 다시 열어 보는 것뿐이다', () {
      expect(
        HttpNotificationRepository.exceptionOf(badResponse(503)).failure,
        NotificationFailure.network,
      );
    });

    test('400은 알 수 없는 실패다', () {
      expect(
        HttpNotificationRepository.exceptionOf(
          badResponse(400, body: {'code': 'INVALID_REQUEST'}),
        ).failure,
        NotificationFailure.unknown,
      );
    });

    test('응답이 없으면 망 문제다', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );

      expect(
        HttpNotificationRepository.exceptionOf(error).failure,
        NotificationFailure.network,
      );
    });
  });

  group('요청', () {
    late Dio dio;
    late List<RequestOptions> sent;
    late HttpNotificationRepository repo;

    setUp(() async {
      sent = [];
      dio = Dio();
      dio.httpClientAdapter = _RecordingAdapter(sent);
      final store = InMemoryTokenStore();
      await store.saveTokens(accessToken: 'a', refreshToken: 'r');
      repo = HttpNotificationRepository(
        dio,
        store,
        TokenRefresher(FakeAuthRepository(), store),
      );
    });

    test('⚠️ 첫 페이지에는 cursor를 보내지 않는다', () async {
      // 빈 문자열을 보내면 형식이 틀렸다고 400을 자초한다.
      await repo.list();

      expect(sent.single.queryParameters.containsKey('cursor'), isFalse);
      expect(sent.single.queryParameters['limit'], 20);
    });

    test('커서가 있으면 실어 보낸다', () async {
      await repo.list(cursor: 'c2');

      expect(sent.single.queryParameters['cursor'], 'c2');
    });

    test('⚠️ limit은 서버 상한을 넘기지 않는다', () async {
      // 넘겨 보내면 400이다.
      await repo.list(limit: 500);

      expect(
        sent.single.queryParameters['limit'],
        HttpNotificationRepository.maxLimit,
      );
    });

    test('모두 읽음은 POST다', () async {
      await repo.readAll();

      expect(sent.single.method, 'POST');
      expect(sent.single.path, endsWith('/notifications/read'));
    });
  });
}

/// 보낸 요청만 적어 두고 빈 응답을 준다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.sent);

  final List<RequestOptions> sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      '{"items":[],"nextCursor":null,"unreadCount":0}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
