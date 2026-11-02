import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/friend/data/friend_dto.dart';
import 'package:runiverse/features/friend/domain/friend_list.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';

/// 진짜 서버를 부르는 [FriendRepository]. **여기가 경로와 응답 형식을 아는
/// 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
/// 갱신은 반드시 [TokenRefresher]를 거친다(`docs/implementation-notes.md` 9-6).
class HttpFriendRepository implements FriendRepository {
  HttpFriendRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static String _friendsPath(String userId) => '/api/v1/users/$userId/friends';
  static String _requestPath(String userId) =>
      '/api/v1/users/$userId/friend-request';
  static String _friendPath(String userId) => '/api/v1/users/$userId/friend';
  static const _recommendationsPath = '/api/v1/users/me/friend-recommendations';
  static const _searchPath = '/api/v1/users/search';

  @override
  Future<FriendList> friends({
    required String userId,
    String? cursor,
    int limit = 20,
  }) => _authorized((token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _friendsPath(userId),
      queryParameters: {'limit': limit, 'cursor': ?cursor},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return friendPageFromJson(response.data);
  });

  @override
  Future<List<FriendRecommendation>> recommendations() =>
      _authorized((token) async {
        final response = await _dio.get<Map<String, dynamic>>(
          _recommendationsPath,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return recommendationsFromJson(response.data);
      });

  @override
  Future<FriendList> search({required String query, int limit = 20}) =>
      _authorized((token) async {
        final response = await _dio.get<Map<String, dynamic>>(
          _searchPath,
          // ⚠️ `cursor` 를 보내지 않는다. 같은 `q` 로 `limit` 만 올려 통째로
          // 다시 받는다 — 페이지를 넘기는 사이 닉네임을 바꾼 사람이 빠지거나
          // 두 번 오는 구간이 아예 없다(설계 §5).
          queryParameters: {'q': query, 'limit': limit},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return friendPageFromJson(response.data);
      });

  @override
  Future<FriendRelation> request(String userId) => _authorized((token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _requestPath(userId),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return relationOf(response.data);
  });

  @override
  Future<FriendRelation> accept(String userId) => _authorized((token) async {
    final response = await _dio.put<Map<String, dynamic>>(
      _requestPath(userId),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return relationOf(response.data);
  });

  @override
  Future<void> cancel(String userId) => _authorized((token) async {
    await _dio.delete<void>(
      _requestPath(userId),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  @override
  Future<void> remove(String userId) => _authorized((token) async {
    await _dio.delete<void>(
      _friendPath(userId),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  /// 요청·수락 응답에서 관계를 읽는다. **테스트가 직접 부른다.**
  ///
  /// ## ⚠️ 상태 코드로 갈라서는 안 된다
  ///
  /// 상대가 먼저 요청해 뒀으면 `POST`가 `201`이 아니라 **`200` + `FRIEND`**로
  /// 온다. 서로 요청한 건 이미 합의된 것이라 서버가 한 번 더 수락을 요구하지
  /// 않는다. 코드로 "요청을 보냈다"로 읽으면 이미 친구인 사람에게 "요청 취소"
  /// 버튼이 선다.
  ///
  /// ⚠️ **못 읽으면 던진다.** 조용히 [FriendRelation.none]으로 두면 방금 요청한
  /// 사람에게 "친구 요청" 버튼이 다시 뜨고, 눌러 봐야 `409`만 돌아온다.
  static FriendRelation relationOf(Map<String, dynamic>? body) {
    final relation = friendRelationOf(body?['relationshipType']);
    if (relation == null) {
      throw const FriendException(FriendFailure.unknown);
    }
    return relation;
  }

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  static FriendException exceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const FriendException(FriendFailure.network);
    }

    final response = error.response;
    final status = response?.statusCode ?? 0;
    if (status == 401) {
      return const FriendException(FriendFailure.sessionExpired);
    }
    if (status == 404) return const FriendException(FriendFailure.notFound);
    // 5xx는 사용자가 할 일이 네트워크 실패와 같다 — 다시 눌러보는 것뿐이다.
    if (status >= 500) return const FriendException(FriendFailure.network);

    final body = response?.data;
    return switch (body is Map ? body['code'] : null) {
      'FRIEND_REQUEST_ALREADY_EXISTS' => const FriendException(
        FriendFailure.alreadyExists,
      ),
      'CANNOT_FRIEND_SELF' => const FriendException(
        FriendFailure.cannotFriendSelf,
      ),
      _ => const FriendException(FriendFailure.unknown),
    };
  }

  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const FriendException(FriendFailure.sessionExpired);
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
      throw const FriendException(FriendFailure.sessionExpired);
    }
    return accessToken;
  }
}
