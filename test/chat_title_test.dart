import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/chat/domain/chat_title.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 채팅 화면의 제목. **두 줄로 나눠서** 그리므로 두 줄을 따로 만든다.
///
/// ## ⚠️ 자르는 것은 화면의 일이다
///
/// 여기서는 긴 닉네임도 통째로 내보낸다. 도메인이 자르면 화면이 쓸 수 있는
/// 폭을 도메인이 멋대로 정하는 셈이다.
void main() {
  // 한국 시각 19:30이 되는 순간. 기기 시간대가 어디든 같은 글자가 나와야 한다.
  final at = KstTime.toLocal(DateTime(2026, 11, 4, 19, 30));

  RoomPlayer player(String id, String nickname, {bool isDeleted = false}) =>
      RoomPlayer(userId: id, nickname: nickname, isDeleted: isDeleted);

  final me = player('me', '나');
  final younghee = player('u1', '영희');
  final cheolsu = player('u2', '철수');
  final minsu = player('u3', '민수');

  ChatTitle titleOf(List<RoomPlayer> players, {int? meters = 5000}) =>
      chatTitleOf(
        scheduledStartAt: at,
        targetDistanceMeters: meters,
        players: players,
        myUserId: 'me',
      );

  test('19:30 - 5 km 러닝 / 영희님 외 2명', () {
    final title = titleOf([me, younghee, cheolsu, minsu]);

    expect(title.top, '19:30 - 5 km 러닝');
    expect(title.bottom, '영희님 외 2명');
  });

  test('거리를 모르면 거리만 뺀다', () {
    // `19:30 - 러닝`처럼 하이픈이 떠 있는 것보다 낫다.
    expect(titleOf([me, younghee], meters: null).top, '19:30 러닝');
  });

  test('딱 떨어지지 않는 거리도 적는다', () {
    expect(titleOf([me, younghee], meters: 21098).top, '19:30 - 21.098 km 러닝');
  });

  test('둘뿐이면 영희님과 함께', () {
    // `외 1명`은 나를 가리키는 말이라 읽기 이상하다.
    expect(titleOf([me, younghee]).bottom, '영희님과 함께');
  });

  test('⚠️ 대표가 탈퇴했으면 다음 사람이 대표다', () {
    // 탈퇴한 사람을 방의 얼굴로 세우지 않는다. 대신 **인원 수에서는 빼지 않는다** —
    // 빼면 숫자가 방과 어긋난다.
    final title = titleOf([
      me,
      player('u1', '영희', isDeleted: true),
      cheolsu,
    ]);

    expect(title.bottom, '철수님 외 1명');
  });

  test('전원 탈퇴면 첫 사람을 그대로 쓴다', () {
    // 건너뛸 곳이 없으면 멈추지 않는다.
    final title = titleOf([
      me,
      player('u1', '영희', isDeleted: true),
      player('u2', '철수', isDeleted: true),
    ]);

    expect(title.bottom, '영희님 외 1명');
  });

  test('⚠️ 나 하나뿐이면 아랫줄이 빈다', () {
    expect(titleOf([me]).bottom, '');
  });

  test('⚠️ 아주 긴 닉네임도 잘라내지 않는다', () {
    final long = '가' * 30;

    expect(titleOf([me, player('u1', long), cheolsu]).bottom, '$long님 외 1명');
  });

  test('명단 순서를 그대로 쓴다', () {
    // 통지 순서나 이름 순으로 뽑으면 안 된다 — 명단이 정본이다.
    expect(titleOf([me, minsu, cheolsu, younghee]).bottom, '민수님 외 2명');
  });
}
