import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/chat/data/chat_dto.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 진짜 서버를 부르는 [ChatRepository]. **여기가 응답 형식을 아는 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
/// 갱신은 반드시 [TokenRefresher]를 거친다(`docs/implementation-notes.md` 9-6).
///
/// ## ⚠️ 주소가 `match-rooms`지만 초대 방도 이것을 쓴다
///
/// 방 종류로 갈리지 않는다. 매칭 방과 초대 방이 같은 API와 같은 이벤트를 쓴다.
class HttpChatRepository implements ChatRepository {
  HttpChatRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static String _chats(int roomId) => '/api/v1/match-rooms/$roomId/chats';

  @override
  Future<ChatHistory> history(
    int runningRoomId, {
    String? cursor,
    int limit = 50,
  }) async {
    try {
      return await _authorized((token) async {
        final response = await _dio.get<Map<String, dynamic>>(
          _chats(runningRoomId),
          // ⚠️ **커서는 있을 때만 싣는다.** 빈 값을 보내면 400이다. 생략하면
          // 서버가 첫 페이지로 읽는다.
          queryParameters: {'limit': limit, 'cursor': ?cursor},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return chatHistoryFromJson(response.data);
      });
    } on ChatException catch (error) {
      // ⚠️ **커서를 실어 보낸 400은 커서가 깨진 것이다.** 서버 응답만으로는
      // 내용 오류와 가를 수 없는데, 할 일이 다르다 — 입력을 확인하는 것이
      // 아니라 **커서를 버리고 첫 페이지부터 다시 받는다.**
      if (cursor != null && error.failure == ChatFailure.invalidRequest) {
        throw const ChatException(ChatFailure.invalidCursor);
      }
      rethrow;
    }
  }

  @override
  Future<Chat> send(int runningRoomId, String content) =>
      _authorized((token) async {
        final response = await _dio.post<Map<String, dynamic>>(
          _chats(runningRoomId),
          data: {'content': content},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return _chatOrThrow(response.data);
      });

  @override
  Future<Chat> edit(
    int runningRoomId, {
    required int chatId,
    required String content,
  }) => _authorized((token) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '${_chats(runningRoomId)}/$chatId',
      data: {'content': content},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return _chatOrThrow(response.data);
  });

  @override
  Future<void> delete(int runningRoomId, int chatId) =>
      _authorized((token) async {
        // ⚠️ **204라 본문이 없다.** 파싱하려 들면 빈 본문에서 던진다 — 지워진
        // 것은 부른 쪽이 표시한다.
        await _dio.delete<void>(
          '${_chats(runningRoomId)}/$chatId',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      });

  /// ⚠️ **읽지 못하면 던진다.** 보내기·수정은 **이 응답이 유일한 근거다** —
  /// 내가 한 일의 `ROOM_CHAT_*` 이벤트는 나에게 오지 않는다. 조용히 넘기면
  /// 보낸 말이 사라진 것처럼 보이고 다시 보내기도 뜨지 않는다.
  static Chat _chatOrThrow(Map<String, dynamic>? body) {
    final chat = chatFromJson(body);
    if (chat == null) throw const ChatException(ChatFailure.unknown);
    return chat;
  }

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  static ChatException exceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const ChatException(ChatFailure.network);
    }

    final response = error.response;
    final body = response?.data;
    final code = body is Map ? body['code'] : null;
    final status = response?.statusCode;

    if (status == 401) return const ChatException(ChatFailure.sessionExpired);
    // ⚠️ 방 없음·방 참가자 아님·메시지 없음·남의 메시지를 서버가 구분하지
    // 않는다. 그래서 수정·삭제의 404만으로 방에서 나가지 않는다.
    if (status == 404) return const ChatException(ChatFailure.notFound);
    if (status != null && status >= 500) {
      return const ChatException(ChatFailure.network);
    }

    return ChatException(switch (code) {
      'ROOM_CHAT_CLOSED' => ChatFailure.closed,
      'INVALID_REQUEST' ||
      'MALFORMED_REQUEST_BODY' => ChatFailure.invalidRequest,
      // 409는 코드가 없어도 닫힌 것으로 읽는다 — 그 상태에서 재시도를
      // 되풀이하면 러닝 중에 계속 서버를 때린다.
      _ when status == 409 => ChatFailure.closed,
      _ when status == 400 => ChatFailure.invalidRequest,
      _ => ChatFailure.unknown,
    });
  }

  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const ChatException(ChatFailure.sessionExpired);
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
      debugPrint('[chat] 토큰을 갱신하지 못했다');
      throw const ChatException(ChatFailure.sessionExpired);
    }
    return accessToken;
  }
}
