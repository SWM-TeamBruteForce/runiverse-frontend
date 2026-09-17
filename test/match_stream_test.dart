import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/matching/data/sse_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭 스트림 — **서버가 미는 것을 앱이 어떻게 읽는가.**
///
/// 여기서 잘못 읽으면 취소된 방의 대기실에 사람을 묶어두거나, 확정 통지를
/// 놓쳐 출발 시각을 지나친다. 되물을 방법이 없는 단방향 채널이라 파싱이 전부다.
void main() {
  const room = {
    'runningRoomId': 125,
    'status': 'MATCHED',
    'scheduledStartAt': '2026-09-15T19:00:00',
    'closeAt': '2026-09-15T18:50:00',
    'targetDistanceMeters': 5000,
    'teamAveragePaceSecondsPerKm': 375,
    'players': [
      {
        'userId': 'u-1',
        'nickname': '동완러너',
        'profileImageUrl': 'https://example.test/a.png',
        'introduction': '즐겁게 같이 달려요!',
        'averagePaceSecondsPerKm': 360,
        'isDeleted': false,
      },
      {
        'userId': 'u-2',
        'nickname': '철수',
        'averagePaceSecondsPerKm': 390,
        'isDeleted': false,
      },
    ],
  };

  /// SSE 프레임 하나를 바이트로 만든다. 빈 줄이 이벤트를 닫는다.
  List<int> frame(String event, Object data) =>
      utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n');

  Future<List<MatchEvent>> decode(List<List<int>> chunks) =>
      SseMatchStream.decode(Stream.fromIterable(chunks)).toList();

  group('프레임을 읽는다', () {
    test('event와 data 한 쌍이 이벤트가 된다', () async {
      final events = await decode([frame('MATCH_ROOM_UPDATED', room)]);

      expect(events, hasLength(1));
      expect(events.single, isA<MatchRoomUpdated>());
    });

    test('⚠️ keep-alive 주석은 버린다', () async {
      // 프록시 유휴 타임아웃을 막는 줄이다. 이벤트로 읽으면 화면이 헛돈다.
      final events = await decode([
        utf8.encode(': ping\n\n'),
        frame('MATCH_ROOM_UPDATED', room),
        utf8.encode(': ping\n\n'),
      ]);

      expect(events, hasLength(1));
    });

    test('⚠️ 한 프레임이 여러 조각으로 나뉘어 와도 읽는다', () async {
      // 네트워크는 줄 단위로 끊어주지 않는다. 조각마다 파싱하면 다 버린다.
      final whole = frame('MATCH_STARTED', room);
      final cut = whole.length ~/ 3;

      final events = await decode([
        whole.sublist(0, cut),
        whole.sublist(cut, cut * 2),
        whole.sublist(cut * 2),
      ]);

      expect(events, hasLength(1));
      expect(events.single, isA<MatchStarted>());
    });

    test('프레임이 연달아 와도 각각 읽는다', () async {
      final events = await decode([
        Uint8List.fromList([
          ...frame('MATCH_ROOM_UPDATED', room),
          ...frame('MATCH_STARTED', room),
        ]),
      ]);

      expect(events, hasLength(2));
      expect(events.first, isA<MatchRoomUpdated>());
      expect(events.last, isA<MatchStarted>());
    });

    test('⚠️ 모르는 이벤트는 버리고 스트림을 이어간다', () async {
      // 하나가 이상하다고 끊으면 그 뒤에 올 확정 통지까지 놓친다.
      final events = await decode([
        utf8.encode('event: SOMETHING_NEW\ndata: {}\n\n'),
        frame('MATCH_STARTED', room),
      ]);

      expect(events, hasLength(1));
      expect(events.single, isA<MatchStarted>());
    });

    test('깨진 JSON도 버리고 이어간다', () async {
      final events = await decode([
        utf8.encode('event: MATCH_STARTED\ndata: {망가진\n\n'),
        frame('MATCH_STARTED', room),
      ]);

      expect(events, hasLength(1));
    });

    test('닫히지 않은 프레임은 이벤트가 되지 않는다', () async {
      // 빈 줄이 오기 전에 끊긴 것이다. 반쪽짜리를 올리면 안 된다.
      final events = await decode([
        utf8.encode('event: MATCH_STARTED\ndata: ${jsonEncode(room)}\n'),
      ]);

      expect(events, isEmpty);
    });
  });

  group('방 정보를 읽는다', () {
    test('값을 그대로 옮긴다', () {
      final parsed = SseMatchStream.roomOf(room)!;

      expect(parsed.runningRoomId, 125);
      expect(parsed.status, RoomStatus.matched);
      expect(parsed.scheduledStartAt, DateTime(2026, 9, 15, 19));
      expect(parsed.closeAt, DateTime(2026, 9, 15, 18, 50));
      expect(parsed.targetDistanceMeters, 5000);
      expect(parsed.players, hasLength(2));
      expect(parsed.players.first.nickname, '동완러너');
      expect(parsed.players.last.profileImageUrl, isNull);
    });

    test('⚠️ 모르는 status면 방을 통째로 버린다', () {
      // 아무 값으로 뭉개면 취소된 방에 사람을 묶어두거나 멀쩡한 방에서 쫓아낸다.
      expect(
        SseMatchStream.roomOf({...room, 'status': 'SOMETHING_NEW'}),
        isNull,
      );
    });

    test('방 번호나 시작 시각이 없으면 버린다', () {
      expect(SseMatchStream.roomOf({...room, 'runningRoomId': null}), isNull);
      expect(
        SseMatchStream.roomOf({...room, 'scheduledStartAt': null}),
        isNull,
      );
    });

    test('⚠️ 탈퇴한 참가자도 목록에 남는다', () {
      // 빼면 인원 수가 방과 어긋난다. 서버가 이미 익명 처리해서 준다.
      final parsed = SseMatchStream.roomOf({
        ...room,
        'players': [
          {'userId': 'u-9', 'nickname': '알 수 없음', 'isDeleted': true},
        ],
      })!;

      expect(parsed.players, hasLength(1));
      expect(parsed.players.single.isDeleted, isTrue);
    });

    test('읽을 수 없는 참가자만 건너뛴다', () {
      final parsed = SseMatchStream.roomOf({
        ...room,
        'players': [
          {'userId': null, 'nickname': '이름'},
          {'userId': 'u-1', 'nickname': '동완러너'},
        ],
      })!;

      expect(parsed.players, hasLength(1));
    });

    test('혼자 확정된 방을 가려낸다', () {
      // 혼자 남은 방에서 나가는 것은 제재 대상이 아니다.
      final alone = SseMatchStream.roomOf({
        ...room,
        'players': [
          {'userId': 'u-1', 'nickname': '동완러너'},
        ],
      })!;

      expect(alone.isAlone, isTrue);
      expect(SseMatchStream.roomOf(room)!.isAlone, isFalse);
    });
  });

  group('시작 통지', () {
    RunningReady ready(int startsInMs) => SseMatchStream.readyOf({
      'runningRoomId': 125,
      'scheduledStartAt': '2026-09-15T19:00:00',
      'startsInMs': startsInMs,
    })!;

    test('간격을 그대로 읽는다', () {
      expect(ready(10000).startsInMs, 10000);
    });

    test('3초보다 여유가 있으면 3-2-1을 다 보여준다', () {
      expect(ready(10000).countdown, const Duration(seconds: 3));
    });

    test('⚠️ 남은 시간이 짧으면 연출만 줄인다', () {
      // 발사 시각을 당기면 시작 시각보다 일러서 서버가 거절한다.
      expect(ready(1200).countdown, const Duration(milliseconds: 1200));
    });

    test('0이면 이미 지난 것이라 연출이 없다', () {
      expect(ready(0).countdown, Duration.zero);
    });

    test('⚠️ 음수는 0으로 누른다', () {
      // 새면 발사 시각이 시작 시각보다 앞선다.
      expect(ready(-500).startsInMs, 0);
    });

    test('서버 시각을 되짚을 수 있다', () {
      // 기기 시계가 어긋나 있어도 이 값으로 보정한다.
      expect(ready(10000).serverNow, DateTime(2026, 9, 15, 18, 59, 50));
    });

    test('값이 빠지면 읽지 않는다', () {
      expect(
        SseMatchStream.readyOf({
          'runningRoomId': 125,
          'scheduledStartAt': '2026-09-15T19:00:00',
        }),
        isNull,
      );
    });
  });

  group('뒷정리', () {
    // 진짜 소켓으로 잰다. 여기서 새는 오류는 `Unhandled Exception`으로 남아
    // 화면은 멀쩡한데 크래시 리포터에 잡힌다 — 에뮬레이터 로그에서 확인했다.
    late HttpServer server;
    late SseMatchStream stream;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final store = InMemoryTokenStore();
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'access',
        refreshToken: 'refresh',
        isOnboarded: true,
      );
      stream = SseMatchStream(
        store,
        FakeAuthRepository(latency: Duration.zero),
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
    });

    tearDown(() => server.close(force: true));

    /// 서버가 실제로 하는 것 — 스냅샷 하나를 보내고 연결을 붙잡는다.
    Future<void> holdOpen(HttpRequest request) async {
      // ⚠️ 끄지 않으면 flush해도 청크가 버퍼에 남아 클라이언트에 닿지 않는다.
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.add(frame('MATCH_ROOM_UPDATED', room));
      await request.response.flush();
    }

    test('⚠️ 이벤트를 받은 뒤 닫아도 늦은 오류가 새지 않는다', () async {
      // 해지가 내려가기 전에 소켓을 강제로 끊으면 dart:io가 아직 살아 있는
      // 내부 구독으로 "Connection closed while receiving data"를 던진다.
      server.listen(holdOpen);
      final first = Completer<MatchEvent>();
      stream.connect().listen((event) {
        if (!first.isCompleted) first.complete(event);
      }, onError: (_) {});
      await first.future;

      await stream.close();
      // 늦은 오류는 다음 틱에 온다. 새면 테스트 존이 잡아 실패한다.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('⚠️ 연결하는 동안 닫히면 늦게 끝난 요청을 버린다', () async {
      // 응답을 기다리는 사이 사용자가 나갔다. 그 요청이 뒤늦게 실패하거나
      // 성공해도 이미 닫힌 스트림에 넣을 것은 없다.
      final released = Completer<void>();
      server.listen((request) async {
        await released.future;
        try {
          await holdOpen(request);
        } on IOException {
          // 클라이언트가 먼저 끊었다. 그것이 기대하는 일이다.
        }
      });
      stream.connect().listen((_) {}, onError: (_) {});
      // 요청이 서버에 닿을 때까지
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await stream.close();
      released.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
