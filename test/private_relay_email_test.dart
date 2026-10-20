import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/private_relay_email.dart';

/// 애플이 가린 주소를 가려내는 규칙.
void main() {
  test('릴레이 도메인이면 가린 주소다', () {
    expect(
      PrivateRelayEmail.hides('a1b2c3d4e5@privaterelay.appleid.com'),
      isTrue,
    );
  });

  test('⚠️ 대소문자를 가리지 않는다', () {
    // 도메인은 원래 대소문자를 구분하지 않고, 서버는 받은 값을 그대로 돌려준다.
    expect(PrivateRelayEmail.hides('A1B2C3@PrivateRelay.AppleID.com'), isTrue);
  });

  test('보통 주소는 아니다', () {
    expect(PrivateRelayEmail.hides('runner@runiverse.app'), isFalse);
    expect(PrivateRelayEmail.hides('runner@icloud.com'), isFalse);
  });

  test('⚠️ 도메인 자리에 있어야 한다', () {
    // 로컬 파트에 그 글자가 들어 있을 뿐인 주소를 가리면, 자기 주소를 가져다
    // 쓰는 사람이 **자기 이메일을 영영 못 본다.**
    expect(
      PrivateRelayEmail.hides('privaterelay.appleid.com@gmail.com'),
      isFalse,
    );
    // 남의 도메인이 릴레이 주소를 흉내 낸 경우.
    expect(
      PrivateRelayEmail.hides('runner@notprivaterelay.appleid.com.evil.com'),
      isFalse,
    );
  });

  test('앞뒤 공백은 무시한다', () {
    expect(PrivateRelayEmail.hides(' a1@privaterelay.appleid.com '), isTrue);
  });
}
