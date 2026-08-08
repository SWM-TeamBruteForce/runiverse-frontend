import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';

/// 토큰 저장소 — 무엇을 지우면 무엇이 남는가.
///
/// 이 파일이 지키는 것은 **`clearTokens()`가 `userId`를 남긴다**는 규칙이다.
/// 그것이 깨지면 만료된 사용자가 온보딩 소개를 처음부터 다시 보게 된다.
void main() {
  Future<void> signIn(TokenStore store) => store.saveSession(
    userId: 'u-1',
    accessToken: 'a-1',
    refreshToken: 'r-1',
    isOnboarded: true,
  );

  test('아무것도 저장하지 않으면 전부 비어 있다', () async {
    final store = InMemoryTokenStore();

    final stored = await store.read();

    expect(stored.userId, isNull);
    expect(stored.accessToken, isNull);
    expect(stored.refreshToken, isNull);
    // 모르는 상태는 '안 했다'로 본다. 프로필을 한 번 더 묻는 쪽이
    // 프로필 없는 사용자를 홈에 들이는 것보다 안전하다.
    expect(stored.isOnboarded, isFalse);
  });

  test('세션을 저장하면 네 값이 함께 읽힌다', () async {
    final store = InMemoryTokenStore();

    await signIn(store);
    final stored = await store.read();

    expect(stored.userId, 'u-1');
    expect(stored.accessToken, 'a-1');
    expect(stored.refreshToken, 'r-1');
    expect(stored.isOnboarded, isTrue);
  });

  test('갱신은 토큰 둘만 덮어쓴다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.saveTokens(accessToken: 'a-2', refreshToken: 'r-2');
    final stored = await store.read();

    // 회전된 refreshToken을 덮어쓰지 않으면 다음 갱신이 401로 죽는다.
    expect(stored.accessToken, 'a-2');
    expect(stored.refreshToken, 'r-2');
    expect(stored.userId, 'u-1');
    expect(stored.isOnboarded, isTrue);
  });

  test('온보딩 완료는 플래그만 켠다', () async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: false,
    );

    await store.markOnboarded();
    final stored = await store.read();

    expect(stored.isOnboarded, isTrue);
    expect(stored.accessToken, 'a-1');
  });

  test('clearTokens는 토큰만 지우고 userId를 남긴다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.clearTokens();
    final stored = await store.read();

    // 이 둘이 남아야 "이 기기는 로그인한 적이 있다"를 알 수 있고,
    // 그래야 만료된 사용자를 온보딩 소개가 아닌 로그인 화면으로 보낸다.
    expect(stored.userId, 'u-1');
    expect(stored.isOnboarded, isTrue);
    expect(stored.accessToken, isNull);
    expect(stored.refreshToken, isNull);
  });

  test('clear는 전부 지운다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.clear();
    final stored = await store.read();

    expect(stored.userId, isNull);
    expect(stored.isOnboarded, isFalse);
  });

  test('빈 문자열은 null로 읽힌다', () async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: '',
      accessToken: '',
      refreshToken: '',
      isOnboarded: false,
    );

    final stored = await store.read();

    // 빈 refreshToken을 서버에 보내면 400 VALIDATION_FAILED가 온다.
    // 보내기 전에 여기서 걸러야 원인이 가까운 곳에 남는다.
    expect(stored.userId, isNull);
    expect(stored.refreshToken, isNull);
  });
}
