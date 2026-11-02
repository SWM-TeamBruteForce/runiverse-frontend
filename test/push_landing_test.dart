import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/notification/domain/push_landing.dart';

/// 눌린 푸시가 어디로 데려가는가.
///
/// 알림함의 랜딩 규칙과 어긋나면 같은 알림이 누른 곳에 따라 다른 화면을 연다.
void main() {
  test('친구 요청·수락은 상대 프로필이다', () {
    for (final type in ['FRIEND_REQUESTED', 'FRIEND_ACCEPTED']) {
      final landing = PushLanding.of({
        'type': type,
        'actorId': 'u-9',
        'notificationId': '31',
      });

      expect(landing, isA<PushLandingProfile>(), reason: type);
      expect((landing! as PushLandingProfile).userId, 'u-9', reason: type);
    }
  });

  test('친구 푸시에 상대가 없으면 앱만 연다', () {
    expect(PushLanding.of({'type': 'FRIEND_REQUESTED'}), isNull);
    expect(PushLanding.of({'type': 'FRIEND_ACCEPTED', 'actorId': ''}), isNull);
  });

  test('러닝 초대는 수락·거절 버튼이 있는 알림함이다', () {
    expect(
      PushLanding.of({
        'type': 'RUNNING_INVITED',
        'actorId': 'u-9',
        'runningRoomId': '130',
      }),
      isA<PushLandingNotifications>(),
    );
  });

  test('매칭 확정·출발 리마인더는 대기방이다', () {
    for (final type in ['MATCH_CONFIRMED', 'RUNNING_REMINDER']) {
      expect(
        PushLanding.of({'type': type, 'runningRoomId': '130'}),
        isA<PushLandingRoom>(),
        reason: type,
      );
    }
  });

  test('⚠️ 모르는 종류는 무시한다', () {
    // 서버가 종류를 늘려도 앱이 엉뚱한 화면을 열지 않는다.
    expect(PushLanding.of({'type': 'SOMETHING_NEW'}), isNull);
    expect(PushLanding.of({}), isNull);
  });
}
