import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';

/// 공개 범위를 서버와 주고받는 값.
///
/// ## ⚠️ 이름을 "친구"로 바꿔도 전송값은 그대로다
///
/// 2026-10-28에 앱 어휘를 팔로우에서 친구로 통일하면서 enum 이름이
/// `followers` → `friends` 가 됐다. **서버가 받는 값은 그 전에도 `FRIENDS`
/// 였고 지금도 `FRIENDS` 다.** 이름과 전송값을 한 덩이로 보고 고치면 설정이
/// 저장되지 않는다 — 서버는 `FRIENDS` 를 기다리는데 앱이 다른 말을 보낸다.
void main() {
  test('⚠️ 이름을 바꿔도 서버로 가는 값은 그대로다', () {
    expect(ProfileVisibility.friends.wireValue, 'FRIENDS');
    expect(ProfileVisibility.fromWire('FRIENDS'), ProfileVisibility.friends);
  });

  test('전체 공개는 PUBLIC 이다', () {
    expect(ProfileVisibility.public.wireValue, 'PUBLIC');
    expect(ProfileVisibility.fromWire('PUBLIC'), ProfileVisibility.public);
  });

  test('⚠️ 모르는 값은 null 이다', () {
    // 서버가 단계를 늘려도 앱이 죽지 않아야 한다.
    expect(ProfileVisibility.fromWire('FOLLOWERS'), isNull);
    expect(ProfileVisibility.fromWire(null), isNull);
  });
}
