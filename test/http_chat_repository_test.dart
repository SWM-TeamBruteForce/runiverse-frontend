import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/chat/data/http_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';

/// 대기방 채팅 API — `/api/v1/match-rooms/{runningRoomId}/chats`.
///
/// ## ⚠️ 여기가 응답 형식을 아는 유일한 곳이다
///
/// 서버를 띄우지 않고 dio 어댑터만 갈아끼워 **실제로 나가는 요청**과 읽어 들인
/// 값을 본다. 주소나 쿼리가 틀리면 404·400으로 조용히 실패하는데, 화면에서는
/// "채팅을 불러오지 못했어요" 한 줄로만 보여서 원인을 가릴 수 없다.
void main() {
  late _CannedAdapter api;

  Future<HttpChatRepository> repositoryReturning(
    Object? payload, {
    int status = 200,
  }) async {
    api = _CannedAdapter(payload, status: status);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'me',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return HttpChatRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = api,
      store,
      TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
    );
  }

  /// 명세의 응답 예시를 그대로 옮긴 한 건.
  Map<String, Object?> chatJson({
    int chatId = 3022,
    String? content = '곧 출발해요',
    bool isDeleted = false,
    String? editedAt,
  }) => {
    'chatId': chatId,
    'runningRoomId': 125,
    'sender': {
      'userId': '01a0f2d4-6180-7000-8000-446655440013',
      'nickname': '철수',
      'profileImageUrl': 'https://cdn.test/a.png',
      'isDeleted': false,
    },
    'content': content,
    'isDeleted': isDeleted,
    'editedAt': editedAt,
    'createdAt': '2026-07-25T18:52:10',
  };

  group('목록 조회', () {
    test('방 번호가 경로에 들어간다', () async {
      final repo = await repositoryReturning({
        'items': [chatJson()],
        'nextCursor': null,
      });

      await repo.history(125, limit: 50);

      expect(api.path, '/api/v1/match-rooms/125/chats');
      expect(api.method, 'GET');
    });

    test('⚠️ 첫 페이지는 커서를 싣지 않는다', () async {
      // 빈 커서를 보내면 400이다. 생략해야 서버가 첫 페이지로 읽는다.
      final repo = await repositoryReturning({'items': [], 'nextCursor': null});

      await repo.history(125, limit: 50);

      expect(api.query.containsKey('cursor'), isFalse);
      expect(api.query['limit'], 50);
    });

    test('이전 페이지는 받은 커서를 그대로 싣는다', () async {
      final repo = await repositoryReturning({'items': [], 'nextCursor': null});

      await repo.history(125, cursor: 'MzAyMQ', limit: 50);

      expect(api.query['cursor'], 'MzAyMQ');
    });

    test('값을 그대로 옮긴다', () async {
      final repo = await repositoryReturning({
        'items': [chatJson()],
        'nextCursor': 'MzAyMQ',
      });

      final page = await repo.history(125, limit: 50);

      expect(page.nextCursor, 'MzAyMQ');
      final one = page.items.single;
      expect(one.chatId, 3022);
      expect(one.runningRoomId, 125);
      expect(one.content, '곧 출발해요');
      expect(one.isDeleted, isFalse);
      expect(one.editedAt, isNull);
      // 서버는 시간대 없는 한국 시각을 준다. 기대값은 순간으로 적는다.
      expect(one.createdAt, DateTime.utc(2026, 7, 25, 9, 52, 10).toLocal());
      expect(one.sender.nickname, '철수');
      expect(one.sender.profileImageUrl, 'https://cdn.test/a.png');
      expect(one.sender.isDeleted, isFalse);
    });

    test('⚠️ 지운 메시지도 목록에 남는다', () async {
      // 빼면 그 자리에서 대화가 끊겨 보인다. 자리를 지키고 표시만 바꾼다.
      final repo = await repositoryReturning({
        'items': [chatJson(content: null, isDeleted: true)],
        'nextCursor': null,
      });

      final page = await repo.history(125, limit: 50);

      expect(page.items.single.isDeleted, isTrue);
      expect(page.items.single.content, isNull);
    });

    test('고친 메시지는 editedAt이 채워져 온다', () async {
      final repo = await repositoryReturning({
        'items': [chatJson(editedAt: '2026-07-25T18:54:00')],
        'nextCursor': null,
      });

      final one = (await repo.history(125, limit: 50)).items.single;

      expect(one.editedAt, DateTime.utc(2026, 7, 25, 9, 54).toLocal());
      expect(one.isEdited, isTrue);
    });

    test('nextCursor가 null이면 더 받을 것이 없다', () async {
      final repo = await repositoryReturning({
        'items': [chatJson()],
        'nextCursor': null,
      });

      expect((await repo.history(125, limit: 50)).nextCursor, isNull);
    });

    test('⚠️ 못 읽는 항목만 건너뛴다', () async {
      // 한 줄이 깨져서 방 전체의 대화를 못 그리면 안 된다 — 방 스냅샷의
      // 참가자 목록과 같은 판단이다.
      final repo = await repositoryReturning({
        'items': [
          chatJson(chatId: 3022),
          {...chatJson(chatId: 3021), 'chatId': 'not-a-number'},
          {...chatJson(chatId: 3020), 'sender': 'not-a-map'},
          {...chatJson(chatId: 3019), 'createdAt': null},
          'not-a-map',
          chatJson(chatId: 3018),
        ],
        'nextCursor': null,
      });

      final page = await repo.history(125, limit: 50);

      expect(page.items.map((one) => one.chatId), [3022, 3018]);
    });

    test('본문이 비어 있어도 던지지 않는다', () async {
      final repo = await repositoryReturning(<String, Object?>{});

      final page = await repo.history(125, limit: 50);

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('보내기', () {
    test('내용만 담아 POST한다', () async {
      final repo = await repositoryReturning(chatJson(), status: 201);

      await repo.send(125, '곧 출발해요');

      expect(api.path, '/api/v1/match-rooms/125/chats');
      expect(api.method, 'POST');
      expect(api.requestBody, {'content': '곧 출발해요'});
    });

    test('201 응답의 Chat을 읽는다', () async {
      final repo = await repositoryReturning(
        chatJson(chatId: 3021, content: '곧 출발해요'),
        status: 201,
      );

      final sent = await repo.send(125, '곧 출발해요');

      expect(sent.chatId, 3021);
      expect(sent.content, '곧 출발해요');
    });

    test('⚠️ 응답을 못 읽으면 던진다', () async {
      // 보내지기는 했는데 화면에 그릴 것이 없다. 조용히 넘기면 **보낸 말이
      // 사라진 것처럼** 보이고, 다시 보내기도 뜨지 않는다.
      final repo = await repositoryReturning(<String, Object?>{}, status: 201);

      await expectLater(
        repo.send(125, '곧 출발해요'),
        throwsA(isA<ChatException>()),
      );
    });
  });

  group('수정', () {
    test('메시지 번호가 경로에 들어간다', () async {
      final repo = await repositoryReturning(
        chatJson(
          chatId: 3021,
          content: '조금 늦어요',
          editedAt: '2026-07-25T18:54:00',
        ),
      );

      await repo.edit(125, chatId: 3021, content: '조금 늦어요');

      expect(api.path, '/api/v1/match-rooms/125/chats/3021');
      expect(api.method, 'PATCH');
      expect(api.requestBody, {'content': '조금 늦어요'});
    });

    test('고친 뒤 Chat을 읽는다 — editedAt이 채워진다', () async {
      final repo = await repositoryReturning(
        chatJson(
          chatId: 3021,
          content: '조금 늦어요',
          editedAt: '2026-07-25T18:54:00',
        ),
      );

      final edited = await repo.edit(125, chatId: 3021, content: '조금 늦어요');

      expect(edited.content, '조금 늦어요');
      expect(edited.isEdited, isTrue);
    });
  });

  group('삭제', () {
    test('⚠️ 204라 본문을 읽지 않는다', () async {
      // 파싱하려 들면 빈 본문에서 던진다. 지워진 것은 부른 쪽이 표시한다.
      final repo = await repositoryReturning(null, status: 204);

      await repo.delete(125, 3021);

      expect(api.path, '/api/v1/match-rooms/125/chats/3021');
      expect(api.method, 'DELETE');
    });
  });

  group('⚠️ 실패를 갈라서 올린다', () {
    DioException httpError(int status, {Map<String, Object?>? body}) {
      final request = RequestOptions(path: '/api/v1/match-rooms/125/chats');
      return DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, Object?>>(
          requestOptions: request,
          statusCode: status,
          data: body,
        ),
      );
    }

    test('400은 입력이 잘못된 것이다', () {
      expect(
        HttpChatRepository.exceptionOf(
          httpError(400, body: {'code': 'INVALID_REQUEST'}),
        ).failure,
        ChatFailure.invalidRequest,
      );
    });

    test('404는 방이나 메시지를 못 찾은 것이다', () {
      // ⚠️ 서버가 방 밖·남의 메시지·이미 지운 것을 가르지 않는다.
      expect(
        HttpChatRepository.exceptionOf(httpError(404)).failure,
        ChatFailure.notFound,
      );
    });

    test('⚠️ 409는 채팅이 닫힌 것이다 — 재시도를 멈춘다', () {
      expect(
        HttpChatRepository.exceptionOf(
          httpError(409, body: {'code': 'ROOM_CHAT_CLOSED'}),
        ).failure,
        ChatFailure.closed,
      );
    });

    test('401은 다시 로그인해야 한다', () {
      expect(
        HttpChatRepository.exceptionOf(httpError(401)).failure,
        ChatFailure.sessionExpired,
      );
    });

    test('5xx와 못 닿은 것은 네트워크다', () {
      expect(
        HttpChatRepository.exceptionOf(httpError(500)).failure,
        ChatFailure.network,
      );
      expect(
        HttpChatRepository.exceptionOf(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        ).failure,
        ChatFailure.network,
      );
    });

    test('⚠️ 커서를 실어 보낸 400은 커서가 깨진 것이다', () async {
      // 할 일이 다르다 — "입력을 확인하라"가 아니라 **커서를 버리고 첫
      // 페이지부터 다시 받는 것**이다. 서버 응답만으로는 가를 수 없다.
      final repo = await repositoryReturning({
        'code': 'INVALID_REQUEST',
      }, status: 400);

      await expectLater(
        repo.history(125, cursor: '깨진커서', limit: 50),
        throwsA(
          isA<ChatException>().having(
            (error) => error.failure,
            'failure',
            ChatFailure.invalidCursor,
          ),
        ),
      );
    });

    test('커서 없는 400은 그대로 입력 오류다', () async {
      final repo = await repositoryReturning({
        'code': 'INVALID_REQUEST',
      }, status: 400);

      await expectLater(
        repo.history(125, limit: 50),
        throwsA(
          isA<ChatException>().having(
            (error) => error.failure,
            'failure',
            ChatFailure.invalidRequest,
          ),
        ),
      );
    });

    test('409는 목록 조회에서도 올라온다', () async {
      final repo = await repositoryReturning({
        'code': 'ROOM_CHAT_CLOSED',
      }, status: 409);

      await expectLater(
        repo.history(125, limit: 50),
        throwsA(
          isA<ChatException>().having(
            (error) => error.failure,
            'failure',
            ChatFailure.closed,
          ),
        ),
      );
    });
  });
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.payload, {this.status = 200});

  /// `null`이면 본문 없는 응답이다(204).
  final Object? payload;
  final int status;

  String? path;
  String? method;
  Object? requestBody;
  Map<String, dynamic> query = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    method = options.method;
    requestBody = options.data;
    query = options.queryParameters;
    final body = payload == null ? '' : jsonEncode(payload);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
