import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';

/// 갱신이 거절됐을 때 **누가 그 사실을 알게 되는가.**
///
/// 예전에는 아무도 몰랐다. `TokenRefresher`가 `null`만 돌려주고 끝나서, 러닝
/// 화면이 "서버에 연결하는 중"에서 영영 굳었다 — 끝낼 수도, 다시 로그인할
/// 수도 없었다(2026-09-18 23:47 실주행).
void main() {
  late InMemoryTokenStore store;

  Future<InMemoryTokenStore> signedIn() async {
    final s = InMemoryTokenStore();
    await s.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return s;
  }

  test('⚠️ 거절되면 알린다', () async {
    store = await signedIn();
    var expired = 0;
    final refresher = TokenRefresher(
      _FailingAuth(AuthFailure.sessionExpired),
      store,
      onExpired: () => expired++,
    );

    expect(await refresher.refresh(), isNull);
    expect(expired, 1);
  });

  test('⚠️ 네트워크 실패에는 알리지 않는다', () async {
    // 터널에 들어갔다고 로그아웃시키면 안 된다. 나오면 그대로 이어져야 한다.
    store = await signedIn();
    var expired = 0;
    final refresher = TokenRefresher(
      _FailingAuth(AuthFailure.network),
      store,
      onExpired: () => expired++,
    );

    expect(await refresher.refresh(), isNull);
    expect(expired, 0);
  });

  test('성공하면 알리지 않고 회전된 토큰을 저장한다', () async {
    store = await signedIn();
    var expired = 0;
    final refresher = TokenRefresher(
      _RotatingAuth(),
      store,
      onExpired: () => expired++,
    );

    expect(await refresher.refresh(), 'a-2');
    expect(expired, 0);
    // ⚠️ 회전된 리프레시 토큰을 덮어써야 다음 갱신이 산다.
    expect((await store.read()).refreshToken, 'r-2');
  });

  test('⚠️ 동시에 불러도 한 번만 나가고 한 번만 알린다', () async {
    // 러닝 시작에 방 생성과 WS 핸드셰이크가 같은 만료 토큰으로 겹친다.
    // 겹칠 때마다 알리면 화면이 로그인으로 몇 번씩 튕긴다.
    store = await signedIn();
    var expired = 0;
    final auth = _FailingAuth(AuthFailure.sessionExpired);
    final refresher = TokenRefresher(auth, store, onExpired: () => expired++);

    await Future.wait([refresher.refresh(), refresher.refresh()]);

    expect(auth.calls, 1, reason: '서버로는 한 번만 나가야 한다');
    expect(expired, 1);
  });

  test('리프레시 토큰이 없으면 부르지도 않는다', () async {
    var expired = 0;
    final auth = _FailingAuth(AuthFailure.sessionExpired);
    final refresher = TokenRefresher(
      auth,
      InMemoryTokenStore(),
      onExpired: () => expired++,
    );

    expect(await refresher.refresh(), isNull);
    expect(auth.calls, 0);
    // 애초에 세션이 없다. 끝낼 것도 없다.
    expect(expired, 0);
  });
}

class _FailingAuth implements AuthRepository {
  _FailingAuth(this.failure);

  final AuthFailure failure;
  var calls = 0;

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    calls++;
    throw AuthException(failure);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RotatingAuth implements AuthRepository {
  @override
  Future<AuthTokens> refresh(String refreshToken) async =>
      const AuthTokens(accessToken: 'a-2', refreshToken: 'r-2');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
