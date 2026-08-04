import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/verification_code_rule.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 이메일 인증의 상태 전이 — 화면 없이 규칙만 본다.
///
/// 시계를 주입해 **5분을 실제로 기다리지 않고** 만료를 확인한다.
void main() {
  const email = 'new@example.com';

  /// [clock]이 가리키는 시각을 테스트가 직접 옮긴다.
  ({ProviderContainer container, AuthController auth}) makeContainer({
    DateTime Function()? now,
  }) {
    final container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(latency: Duration.zero, now: now),
        ),
      ],
    );
    return (
      container: container,
      auth: container.read(authControllerProvider.notifier),
    );
  }

  test('인증번호를 받고 맞게 치면 통과한다', () async {
    final (:container, :auth) = makeContainer();

    expect(await auth.sendVerificationCode(email), isNull);
    expect(
      await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode),
      isNull,
    );
  });

  test('번호가 틀리면 막힌다', () async {
    final (:container, :auth) = makeContainer();
    await auth.sendVerificationCode(email);

    expect(
      await auth.verifyCode(email: email, code: '000000'),
      AuthFailure.invalidCode,
    );
  });

  test('받은 적 없는 이메일은 "틀림"으로 답한다', () async {
    final (:container, :auth) = makeContainer();

    // "발급된 적 없다"를 따로 알리면 어떤 이메일에 번호가 갔는지 떠볼 수 있다.
    expect(
      await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode),
      AuthFailure.invalidCode,
    );
  });

  test('5분이 지나면 만료된다', () async {
    var clock = DateTime(2026, 8, 4, 10);
    final (:container, :auth) = makeContainer(now: () => clock);

    await auth.sendVerificationCode(email);

    // 경계 바로 안쪽 — 아직 살아 있다.
    clock = clock.add(VerificationCodeRule.ttl);
    expect(
      await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode),
      isNull,
    );

    // 다시 받고, 이번엔 경계를 넘긴다.
    await auth.sendVerificationCode(email);
    clock = clock.add(VerificationCodeRule.ttl + const Duration(seconds: 1));
    expect(
      await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode),
      AuthFailure.codeExpired,
    );
  });

  test('이미 가입한 이메일은 번호를 보내기 전에 막는다', () async {
    final (:container, :auth) = makeContainer();

    // 번호를 다 치고 나서 "이미 가입됐다"고 하면 한 일이 통째로 버려진다.
    expect(
      await auth.sendVerificationCode(FakeAuthRepository.seedEmail),
      AuthFailure.emailAlreadyExists,
    );
  });

  test('인증하지 않은 이메일로는 가입할 수 없다', () async {
    final (:container, :auth) = makeContainer();

    // 앱은 인증 전에 가입 버튼을 열지 않는다. **서버가 막아야 하는 것**이라
    // 가짜 저장소도 같은 계약을 지킨다.
    expect(
      await auth.signUp(email: email, password: 'runi123!'),
      AuthFailure.emailNotVerified,
    );
    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
  });

  test('인증한 뒤에는 가입되고 곧바로 로그인 상태가 된다', () async {
    final (:container, :auth) = makeContainer();

    await auth.sendVerificationCode(email);
    await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode);

    expect(await auth.signUp(email: email, password: 'runi123!'), isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('번호를 다시 받으면 이전 인증이 무효가 된다', () async {
    final (:container, :auth) = makeContainer();

    await auth.sendVerificationCode(email);
    await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode);

    // 다시 받았다면 아직 못 받았거나 못 봤다는 뜻이다. 이전 인증을 남겨두면
    // 새 번호를 치지 않고도 가입할 수 있다.
    await auth.sendVerificationCode(email);

    expect(
      await auth.signUp(email: email, password: 'runi123!'),
      AuthFailure.emailNotVerified,
    );
  });

  test('가입에 쓴 인증은 재사용되지 않는다', () async {
    final (:container, :auth) = makeContainer();

    await auth.sendVerificationCode(email);
    await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode);
    await auth.signUp(email: email, password: 'runi123!');

    // 같은 이메일로 또 가입하려 하면 이미 가입됐다고 막힌다 —
    // 인증 상태가 남아 있는지와 무관하게 계정 중복이 먼저 걸린다.
    expect(
      await auth.signUp(email: email, password: 'other12!'),
      AuthFailure.emailAlreadyExists,
    );
  });

  test('대소문자가 달라도 같은 이메일로 본다', () async {
    final (:container, :auth) = makeContainer();

    await auth.sendVerificationCode('New@Example.com');

    // 인증은 대문자로, 가입은 소문자로 하는 경우다. 다른 이메일로 보면
    // 방금 인증한 사람이 인증하지 않은 것으로 취급된다.
    expect(
      await auth.verifyCode(email: email, code: FakeAuthRepository.mockCode),
      isNull,
    );
    expect(await auth.signUp(email: email, password: 'runi123!'), isNull);
  });
}
