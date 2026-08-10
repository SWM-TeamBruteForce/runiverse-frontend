import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';

/// 이메일 인증 3단계 — 가짜 저장소가 서버 규칙을 흉내 내는가.
///
/// 여기서 보는 것은 **티켓의 수명**과 **거절의 순서**다. 서버에서 티켓은 1회용이고,
/// 중복 이메일은 인증번호를 보내기 전에 막힌다. 가짜가 그것을 흉내 내지 않으면
/// 실제 서버에서만 깨지는 화면을 만들게 된다.
void main() {
  FakeAuthRepository make() => FakeAuthRepository(latency: Duration.zero);

  /// 실패 이유를 집는 matcher. `throwsA(isA<...>().having(...))`가 길어서 묶었다.
  Matcher failsWith(AuthFailure failure) => throwsA(
    isA<AuthException>().having((e) => e.failure, 'failure', failure),
  );

  group('인증번호 확인', () {
    test('맞는 번호를 내면 티켓이 나온다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      final ticket = await repo.verifyCode(
        email: 'new@example.com',
        code: repo.lastCode!,
      );

      expect(ticket, isNotEmpty);
    });

    test('틀린 번호는 invalidCode다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      await expectLater(
        repo.verifyCode(email: 'new@example.com', code: '000000'),
        failsWith(AuthFailure.invalidCode),
      );
    });

    test('보낸 적 없는 이메일은 codeExpired다', () async {
      final repo = make();

      // 서버는 "보낸 적 없다"와 "만료됐다"를 같은 코드로 답한다. 여기도 같다.
      await expectLater(
        repo.verifyCode(email: 'nobody@example.com', code: '123456'),
        failsWith(AuthFailure.codeExpired),
      );
    });

    test('맞은 번호는 두 번 쓸 수 없다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');
      final code = repo.lastCode!;
      await repo.verifyCode(email: 'new@example.com', code: code);

      // 서버는 맞은 코드를 지운다. 같은 번호로 티켓을 여러 장 받으면
      // 한 번의 인증으로 계정을 여러 개 만들 수 있다.
      await expectLater(
        repo.verifyCode(email: 'new@example.com', code: code),
        failsWith(AuthFailure.codeExpired),
      );
    });

    test('이메일이 다르면 남의 번호로 통과할 수 없다', () async {
      final repo = make();
      await repo.sendVerificationCode('a@example.com');

      await expectLater(
        repo.verifyCode(email: 'b@example.com', code: repo.lastCode!),
        failsWith(AuthFailure.codeExpired),
      );
    });
  });

  group('발송 제한', () {
    test('연달아 보내면 sendCooldown이다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      await expectLater(
        repo.sendVerificationCode('new@example.com'),
        failsWith(AuthFailure.sendCooldown),
      );
    });

    test('이미 가입된 이메일은 보내기 전에 막힌다', () async {
      final repo = make();
      repo.seedAccount(email: 'taken@example.com', password: 'runi123!');

      // 인증번호를 치기도 전에 알려주는 것이 이 검사의 존재 이유다.
      await expectLater(
        repo.sendVerificationCode('taken@example.com'),
        failsWith(AuthFailure.emailAlreadyExists),
      );
    });

    test('가입된 이메일로 두 번 눌러도 이유가 바뀌지 않는다', () async {
      final repo = make();
      repo.seedAccount(email: 'taken@example.com', password: 'runi123!');

      // 중복을 쿨다운보다 먼저 보지 않으면 두 번째가 sendCooldown이 된다.
      // 같은 조작에 다른 이유가 나오면 무엇이 문제인지 알 수 없다.
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.sendVerificationCode('taken@example.com'),
          failsWith(AuthFailure.emailAlreadyExists),
        );
      }
    });

    test('인증을 마치면 쿨다운이 풀린다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');
      await repo.verifyCode(email: 'new@example.com', code: repo.lastCode!);

      // 가입에 실패해 인증부터 다시 해야 하는 경우가 있다. 그때 쿨다운에
      // 걸려 있으면 사용자는 아무것도 할 수 없다.
      await repo.sendVerificationCode('new@example.com');
      expect(repo.lastCode, isNotNull);
    });
  });

  group('티켓', () {
    test('한 번 쓰면 사라진다', () {
      final repo = make();
      final ticket = repo.issueTicket('new@example.com');

      expect(repo.consumeTicket(ticket), 'new@example.com');
      // 서버 SignUpHandler는 티켓을 먼저 소비하고 계정을 만든다.
      // 가입이 실패해도 티켓은 돌아오지 않는다.
      expect(repo.consumeTicket(ticket), isNull);
    });

    test('모르는 티켓은 null이다', () {
      expect(make().consumeTicket('made-up'), isNull);
    });
  });
}
