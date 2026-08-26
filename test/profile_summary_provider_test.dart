import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 요약 — **저장해 둔 값과 서버 값 사이를 어떻게 오가는가.**
///
/// `GET /users/{userId}`는 명세상 아직 `개발중`이다. 서버가 답하지 못해도
/// 화면이 비지 않아야 하고, 그 안전망이 `/users/me`가 남긴 캐시다.
void main() {
  Future<TokenStore> signedInStore({String? nickname}) async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    if (nickname != null) {
      await store.saveCurrentUser(
        userId: 'u-1',
        isOnboarded: true,
        nickname: nickname,
      );
    }
    return store;
  }

  ProviderContainer makeContainer(
    TokenStore store,
    FakeProfileRepository repository,
  ) => ProviderContainer.test(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      signInMemoryStoreProvider.overrideWithValue(InMemorySignInMemoryStore()),
      profileRepositoryProvider.overrideWithValue(repository),
    ],
  );

  test('서버가 답하면 그 값을 쓴다', () async {
    final container = makeContainer(
      await signedInStore(nickname: '캐시된이름'),
      FakeProfileRepository(nickname: '서버이름', friendCount: 3),
    );

    await container.read(profileSummaryControllerProvider.notifier).load();

    final state = container.read(profileSummaryControllerProvider);
    expect(state.summary?.nickname, '서버이름');
    expect(state.summary?.friendCount, 3);
  });

  test('⚠️ 서버가 실패해도 저장해 둔 값이 화면을 채운다', () async {
    final container = makeContainer(
      await signedInStore(nickname: '캐시된이름'),
      FakeProfileRepository(failure: ProfileFailure.server),
    );

    await container.read(profileSummaryControllerProvider.notifier).load();

    // `/users/{userId}`가 아직 배포되지 않았을 때가 정확히 이 상황이다.
    // 여기서 비우면 어제까지 보이던 닉네임이 사라진다.
    final state = container.read(profileSummaryControllerProvider);
    expect(state.summary?.nickname, '캐시된이름');
  });

  test('캐시도 서버도 없으면 비어 있다', () async {
    final container = makeContainer(
      await signedInStore(),
      FakeProfileRepository(failure: ProfileFailure.network),
    );

    await container.read(profileSummaryControllerProvider.notifier).load();

    // 없는 값을 지어내지 않는다. 화면은 `null`을 다룰 줄 안다.
    expect(container.read(profileSummaryControllerProvider).summary, isNull);
  });

  test('로그인하지 않았으면 서버를 부르지 않는다', () async {
    final repository = FakeProfileRepository(nickname: '서버이름');
    final container = makeContainer(InMemoryTokenStore(), repository);

    await container.read(profileSummaryControllerProvider.notifier).load();

    // 누구를 물어볼지 모른다. 빈 userId로 부르면 서버가 404를 준다.
    expect(repository.calls, 0);
  });

  test('⚠️ 서버가 준 값을 기기에 남긴다', () async {
    // 편집 화면이 이 값으로 그리고, 앱을 껐다 켠 뒤에도 화면이 비지 않는다.
    final store = await signedInStore();
    final container = makeContainer(
      store,
      FakeProfileRepository(
        nickname: '서버이름',
        introduction: '아침에 달려요',
        profileImageUrl: 'https://cdn.test/a.png',
      ),
    );

    await container.read(profileSummaryControllerProvider.notifier).load();

    final stored = await store.read();
    expect(stored.nickname, '서버이름');
    expect(stored.introduction, '아침에 달려요');
    expect(stored.profileImageUrl, 'https://cdn.test/a.png');
  });

  test('⚠️ 서버가 실패하면 저장해 둔 값을 덮지 않는다', () async {
    // 500 한 번에 캐시가 지워지면, 다음에 앱을 켤 때 화면이 통째로 빈다.
    final store = await signedInStore(nickname: '캐시된이름');
    final container = makeContainer(
      store,
      FakeProfileRepository(failure: ProfileFailure.server),
    );

    await container.read(profileSummaryControllerProvider.notifier).load();

    expect((await store.read()).nickname, '캐시된이름');
  });
}
