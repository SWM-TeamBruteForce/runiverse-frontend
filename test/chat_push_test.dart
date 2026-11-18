import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/notification/domain/chat_push.dart';
import 'package:runiverse/features/notification/domain/push_landing.dart';

/// 대기방 채팅 푸시 data를 읽는다.
///
/// 안드로이드는 이것만 보고 알림을 그린다. 잘못 읽으면 알림이 안 뜨거나 엉뚱한
/// 줄이 뜬다 — 오류 화면은 없다.
void main() {
  // 서버 PR #131 본문의 예시 그대로다.
  const message = {
    'type': 'ROOM_CHAT_SENT',
    'runningRoomId': '125',
    'chatId': '3021',
    'chatType': 'MESSAGE',
    'actorId': '01a0',
    'actorNickname': '철수',
    'actorProfileImageUrl': 'https://example.com/a.jpg',
    'title': '19:30 - 5 km 러닝',
    'body': '곧 출발해요',
  };

  test('말을 읽는다', () {
    final push = ChatPush.of(message)!;

    expect(push.runningRoomId, '125');
    expect(push.chatId, '3021');
    expect(push.kind, ChatPushKind.message);
    expect(push.title, '19:30 - 5 km 러닝');
    expect(push.body, '곧 출발해요');
    expect(push.actorId, '01a0');
    expect(push.actorNickname, '철수');
    expect(push.actorProfileImageUrl, 'https://example.com/a.jpg');
  });

  test('들어온 줄은 서버 문장을 그대로 내용으로 쓴다', () {
    final push = ChatPush.of({
      ...message,
      'chatType': 'JOINED',
      'actorNickname': '영희',
      'body': '영희님이 들어왔어요',
    })!;

    expect(push.kind, ChatPushKind.joined);
    expect(push.body, '영희님이 들어왔어요');
  });

  test('사진이 없는 사람도 읽는다', () {
    // 사진 키는 사진이 있을 때만 온다.
    final push = ChatPush.of({...message}..remove('actorProfileImageUrl'))!;

    expect(push.actorProfileImageUrl, isNull);
  });

  test('채팅 푸시가 아니면 읽지 않는다', () {
    expect(ChatPush.of({...message, 'type': 'RUNNING_REMINDER'}), isNull);
  });

  test('⚠️ 모르는 chatType은 그리지 않는다', () {
    // 서버가 종류를 늘려도 앱이 뜻을 모르는 줄을 그리지 않는다.
    expect(ChatPush.of({...message, 'chatType': 'LEFT'}), isNull);
    expect(ChatPush.of({...message}..remove('chatType')), isNull);
  });

  test('그릴 값이 빠졌으면 읽지 않는다', () {
    for (final key in [
      'runningRoomId',
      'chatId',
      'title',
      'body',
      'actorId',
      'actorNickname',
    ]) {
      expect(ChatPush.of({...message}..remove(key)), isNull, reason: key);
      expect(ChatPush.of({...message, key: ''}), isNull, reason: key);
    }
  });

  test('눌렀을 때 넘기는 data는 대기방으로 간다', () {
    final landing = PushLanding.of(ChatPush.of(message)!.landingData);

    expect(landing, isA<PushLandingRoom>());
  });
}
