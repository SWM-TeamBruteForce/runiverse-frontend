import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';

/// 토큰 갱신 — **동시에 두 번 나가지 않는가.**
///
/// 이 테스트가 이 클래스의 존재 이유다. 서버가 리프레시 토큰을 회전시키므로
/// 두 요청이 같은 토큰으로 동시에 들어가면 두 번째가 이미 회전된 토큰을 보내고,
/// 백엔드가 그것을 **탈취로 보고 리프레시 토큰을 지운다**
/// (`docs/implementation-notes.md` 9-6).
///
/// 러닝을 시작하면 실제로 그 상황이 만들어진다 — `POST /running-rooms/solo`와
/// WebSocket 핸드셰이크가 같은 만료 토큰으로 거의 동시에 나간다.
void main() {
  late _CountingAuth auth;
  late InMemoryTokenStore store;
  late TokenRefresher refresher;

  setUp(() async {
    auth = _CountingAuth();
    store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      isOnboarded: true,
    );
    refresher = TokenRefresher(auth, store);
  });

  test('갱신하면 새 액세스 토큰을 준다', () async {
    expect(await refresher.refresh(), 'access-1');
    expect(auth.calls, 1);
  });

  test('⚠️ 회전된 리프레시 토큰까지 저장한다', () async {
    // 안 하면 다음 갱신이 옛 토큰을 보내고, 서버가 탈취로 본다.
    await refresher.refresh();

    final stored = await store.read();
    expect(stored.accessToken, 'access-1');
    expect(stored.refreshToken, 'refresh-1');
  });

  test('⚠️ 동시에 열 번 불러도 서버로는 한 번만 나간다', () async {
    // 이것이 막히지 않으면 잘못 없는 사용자가 로그아웃된다.
    final results = await Future.wait([
      for (var i = 0; i < 10; i++) refresher.refresh(),
    ]);

    expect(auth.calls, 1);
    expect(results, everyElement('access-1'));
  });

  test('⚠️ 앞선 갱신이 끝난 뒤에는 새로 부른다', () async {
    // 진행 중인 것을 계속 물려주면 다음에 만료됐을 때 죽은 토큰을 돌려준다.
    expect(await refresher.refresh(), 'access-1');
    expect(await refresher.refresh(), 'access-2');

    expect(auth.calls, 2);
  });

  test('갱신이 거절되면 null이다', () async {
    auth.failure = AuthFailure.sessionExpired;

    expect(await refresher.refresh(), isNull);
  });

  test('⚠️ 거절돼도 저장소를 비우지 않는다', () async {
    // 네트워크 오류일 수도 있다. 로그아웃 시점은 화면이 정한다.
    auth.failure = AuthFailure.network;

    await refresher.refresh();

    expect((await store.read()).refreshToken, 'old-refresh');
  });

  test('리프레시 토큰이 없으면 부르지도 않는다', () async {
    await store.clear();

    expect(await refresher.refresh(), isNull);
    expect(auth.calls, 0);
  });
}

/// 몇 번 불렸는지 세는 가짜.
///
/// 매번 **다른 토큰**을 돌려준다 — 같은 값을 주면 "한 번만 불렀다"와
/// "여러 번 불렀는데 답이 같다"를 구분할 수 없다.
class _CountingAuth extends FakeAuthRepository {
  int calls = 0;

  /// 주면 갱신이 이 이유로 실패한다.
  AuthFailure? failure;

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    calls++;
    // 진짜 서버처럼 왕복 시간을 흉내 낸다. 즉시 답하면 동시 호출이
    // 겹칠 틈이 없어 테스트가 무의미해진다.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final reason = failure;
    if (reason != null) throw AuthException(reason);

    return AuthTokens(
      accessToken: 'access-$calls',
      refreshToken: 'refresh-$calls',
    );
  }
}
