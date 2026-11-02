import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/user_status.dart';

/// 종료 때 매칭 제한 안내를 띄울 방인가.
///
/// 서버는 매칭 방이면서 2명 이상일 때만 제한한다(`RunningFinisher`). 그 밖의
/// 방에서 안내를 띄우면 받지도 않을 제한으로 겁을 준다(노션 「1.1.2 운영 전
/// 앱 점검」 8번).
void main() {
  RunningRoom room({
    bool matched = true,
    RoomType? type = RoomType.match,
    int? playerCount,
  }) => RunningRoom(
    1,
    targetDistanceMeters: 5000,
    isMatched: matched,
    type: type,
    playerCount: playerCount,
  );

  test('매칭 방에 둘 이상이면 제한할 수 있다', () {
    expect(room(playerCount: 2).mayPenalize, isTrue);
    expect(room(playerCount: 4).mayPenalize, isTrue);
  });

  test('⚠️ 매칭이 혼자로 확정됐으면 제한하지 않는다', () {
    expect(room(playerCount: 1).mayPenalize, isFalse);
  });

  test('⚠️ 초대 방은 인원과 상관없이 제한하지 않는다', () {
    // 초대 방도 파티원 화면이 있어 `isMatched` 가 참이다 — 그것만 보면 안 된다.
    expect(room(type: RoomType.invite, playerCount: 3).mayPenalize, isFalse);
    expect(room(type: RoomType.invite).mayPenalize, isFalse);
  });

  test('솔로는 제한하지 않는다', () {
    expect(room(matched: false, type: RoomType.solo).mayPenalize, isFalse);
  });

  group('⚠️ 모르면 제한할 수 있다고 본다 — 안내를 걷으면 "제한 없다"는 약속이 된다', () {
    test('앱을 다시 켜고 붙으면 인원을 모른다', () {
      expect(room().mayPenalize, isTrue);
    });

    test('방 종류를 모른다', () {
      expect(room(type: null, playerCount: 2).mayPenalize, isTrue);
    });
  });
}
