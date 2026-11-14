import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';
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

  group('⚠️ 앱을 끄지 않고 계정을 바꾸면', () {
    // 이 provider는 로그아웃해도 살아 있다. 앞 사람이 띄운 요청이 다음 사람
    // 로그인 뒤에 오면, 저장된 내 번호가 앞 사람으로 덮여 친구 목록과 파티원
    // 보드가 틀어진다.
    late InMemoryTokenStore store;
    late _HeldProfiles profiles;
    late ProviderContainer container;
    late _Auth auth;

    setUp(() async {
      store = InMemoryTokenStore();
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      await store.saveCurrentUser(
        userId: 'u-1',
        isOnboarded: true,
        nickname: '앞사람',
      );
      profiles = _HeldProfiles(nickname: '앞사람', introduction: '앞사람 소개');
      container = ProviderContainer.test(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          profileRepositoryProvider.overrideWithValue(profiles),
          bodyProfileStoreProvider.overrideWithValue(
            InMemoryBodyProfileStore(),
          ),
          authControllerProvider.overrideWith(
            () => _Auth(const AuthSignedIn('u-1', isOnboarded: true)),
          ),
        ],
      );
      auth = container.read(authControllerProvider.notifier) as _Auth;
    });

    ProfileSummaryController profile() =>
        container.read(profileSummaryControllerProvider.notifier);

    /// 로그아웃하고 u-2로 들어온다. 순서는 `forgetSession`과 `_authenticate`를
    /// 따른다 — 저장소를 비우고 나간 뒤, 세션을 남기고 들어와 `/me`를 저장한다.
    Future<void> switchToNext() async {
      await store.clear();
      await container.read(bodyProfileProvider.notifier).clear();
      auth.set(const AuthSignedOut(returning: true));
      await store.saveSession(
        userId: 'u-2',
        accessToken: 'a-2',
        refreshToken: 'r-2',
        isOnboarded: true,
      );
      auth.set(
        const AuthSignedIn(
          'u-2',
          isOnboarded: true,
          user: CurrentUser(userId: 'u-2', isOnboarded: true, nickname: '다음사람'),
        ),
      );
      await store.saveCurrentUser(
        userId: 'u-2',
        isOnboarded: true,
        nickname: '다음사람',
      );
    }

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 떠난 조회가 늦게 ${fails ? '실패해도' : '와도'} 다음 사람에게 남지 않는다',
        () async {
          // 앞 사람이 프로필 탭을 한 번 읽어 두었고, 다시 읽는 조회가 붙잡혀 있다.
          await profile().load();
          final held = profiles.hold = Completer<void>();
          final stale = profile().load();
          await pumpEventQueue();

          await switchToNext();
          profiles.fails = fails;
          held.complete();
          await stale;

          expect(
            container.read(profileSummaryControllerProvider).summary,
            isNull,
            reason: '앞 사람 요약이 남았다',
          );
          final stored = await store.read();
          expect(stored.userId, 'u-2', reason: '저장된 내 번호가 앞 사람으로 덮였다');
          expect(stored.nickname, '다음사람');
          expect(stored.introduction, isNull);
        },
      );
    }

    test('⚠️ 바꾸기 전에 보낸 닉네임 변경이 늦게 와도 다음 사람 이름을 덮지 않는다', () async {
      final held = profiles.hold = Completer<void>();
      final change = profile().changeNickname('앞사람새이름');
      await pumpEventQueue();

      await switchToNext();
      held.complete();

      expect(await change, isNull, reason: '서버는 받아 줬다');
      expect((await store.read()).nickname, '다음사람');
      expect(
        (container.read(authControllerProvider) as AuthSignedIn).user?.nickname,
        '다음사람',
        reason: '홈이 부르는 이름이 앞 사람 것으로 바뀌었다',
      );
      expect(container.read(profileSummaryControllerProvider).summary, isNull);
    });

    test('⚠️ 바꾸기 전에 보낸 프로필 저장이 늦게 와도 다음 사람 값으로 남지 않는다', () async {
      final held = profiles.hold = Completer<void>();
      final save = profile().saveProfile(
        introduction: '앞사람 새 소개',
        heightCm: 180,
        weightKg: 75,
      );
      await pumpEventQueue();

      await switchToNext();
      held.complete();

      expect(await save, isNull, reason: '서버는 받아 줬다');
      expect((await store.read()).introduction, isNull);
      expect(
        container.read(bodyProfileProvider).isEmpty,
        isTrue,
        reason: '앞 사람 몸무게로 다음 사람 칼로리를 낸다',
      );
      expect(
        (await container.read(bodyProfileStoreProvider).read()).isEmpty,
        isTrue,
      );
    });

    test('같은 계정의 프로필만 바뀌면 요약을 비우지 않는다', () async {
      // `/me`가 닉네임을 채워 오는 것처럼 같은 사람 안에서 상태만 바뀐다.
      await profile().load();
      final shown = container.read(profileSummaryControllerProvider);

      auth.set(
        const AuthSignedIn(
          'u-1',
          isOnboarded: true,
          user: CurrentUser(userId: 'u-1', isOnboarded: true, nickname: '앞사람'),
        ),
      );

      expect(container.read(profileSummaryControllerProvider), same(shown));
    });

    test('요약을 읽은 뒤에 로그인 상태가 들어와도 비우지 않는다', () async {
      // 스플래시를 건너뛴 화면 테스트가 이 순서다 — 탭이 먼저 읽고 `restore()`가
      // 뒤에 온다. 들어오는 것은 계정을 떠난 것이 아니다.
      auth.set(const AuthUnknown());
      await profile().load();
      final shown = container.read(profileSummaryControllerProvider);

      auth.set(const AuthSignedIn('u-1', isOnboarded: true));

      expect(container.read(profileSummaryControllerProvider), same(shown));
      expect(shown.summary?.nickname, '앞사람');
    });
  });
}

/// 테스트가 로그인 상태를 바꿔 끼우는 컨트롤러.
class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}

/// 요청을 붙잡아 둘 수 있는 프로필 저장소. [hold]가 있으면 그때 떠난 요청이
/// 그것을 기다린다.
class _HeldProfiles extends FakeProfileRepository {
  _HeldProfiles({super.nickname, super.introduction});

  Completer<void>? hold;

  /// 붙잡혔던 조회가 풀릴 때 실패로 끝내는가.
  var fails = false;

  @override
  Future<ProfileSummary> fetch(String userId) async {
    final gate = hold;
    if (gate != null) {
      await gate.future;
      if (fails) throw const ProfileException(ProfileFailure.network);
    }
    return super.fetch(userId);
  }

  @override
  Future<String> changeNickname(String nickname) async {
    await hold?.future;
    return super.changeNickname(nickname);
  }

  @override
  Future<void> updateProfile({
    String? introduction,
    DateTime? birthday,
    double? weightKg,
    double? heightCm,
  }) async {
    await hold?.future;
    return super.updateProfile(
      introduction: introduction,
      birthday: birthday,
      weightKg: weightKg,
      heightCm: heightCm,
    );
  }
}
