import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_remote.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';

/// 신체 정보 — **기기에 남은 값과 서버 값 중 무엇이 이기나.**
///
/// 이 값이 틀리면 러닝 중 칼로리가 조용히 틀린다. 틀렸다는 것을 알 방법이
/// 없어서, 여기서 보는 것은 "값이 오는가"가 아니라 **"엉뚱한 값으로 덮지
/// 않는가"**다.
void main() {
  late InMemoryBodyProfileStore store;
  late _FakeRemote remote;

  setUp(() {
    store = InMemoryBodyProfileStore();
    remote = _FakeRemote();
  });

  /// 저장소와 서버를 끼운 컨테이너. `remote`를 빼면 **연결된 곳이 없는**
  /// 상태가 된다(테스트 기본값이자, `main.dart`의 override를 지웠을 때다).
  ProviderContainer containerWith({bool wired = true}) {
    final container = ProviderContainer(
      overrides: [
        bodyProfileStoreProvider.overrideWithValue(store),
        if (wired) bodyProfileRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('서버에서 읽어온다', () {
    test('서버 값이 기기 값을 덮는다', () async {
      // 다른 기기에서 몸무게를 바꿨다. 이 기기의 값은 낡았다.
      await store.save(heightCm: 170, weightKg: 60);
      remote.body = const StoredBody(heightCm: 175, weightKg: 71);
      final container = containerWith();

      expect(
        await container.read(bodyProfileProvider.notifier).refresh(),
        isTrue,
      );

      expect(container.read(bodyProfileProvider).weightKg, 71);
      expect(container.read(bodyProfileProvider).heightCm, 175);
    });

    test('받은 값을 기기에도 남긴다', () async {
      remote.body = const StoredBody(weightKg: 71);
      final container = containerWith();

      await container.read(bodyProfileProvider.notifier).refresh();

      // 다음 기동 때 서버를 기다리는 동안 이 값으로 그린다.
      expect((await store.read()).weightKg, 71);
    });

    test('기기가 비어 있어도 서버 값으로 채워진다', () async {
      // ⚠️ **이것이 칼로리가 `--`로 뜨던 자리다.** 다른 기기에서 로그인하면
      // 저장소가 비는데, 전에는 그 기기에서 프로필 편집을 한 번 거쳐야
      // 몸무게를 알 수 있었다.
      remote.body = const StoredBody(weightKg: 71);
      final container = containerWith();

      await container.read(bodyProfileProvider.notifier).refresh();

      expect(container.read(bodyProfileProvider).weightKg, 71);
    });
  });

  group('덮지 않는 경우', () {
    test('⚠️ 서버의 null은 기기 값을 지우지 않는다', () async {
      // 온보딩 직후가 그렇다. 입력한 값을 저장하는 것과 이 호출은 순서가
      // 보장되지 않아서, 서버가 아직 `null`을 줄 수 있다. 그걸로 덮으면
      // **방금 넣은 값이 사라진다.**
      await store.save(heightCm: 170, weightKg: 60);
      remote.body = StoredBody.empty;
      final container = containerWith();

      await container.read(bodyProfileProvider.notifier).refresh();

      expect(container.read(bodyProfileProvider).weightKg, 60);
      expect(container.read(bodyProfileProvider).heightCm, 170);
    });

    test('⚠️ 실패하면 거짓을 돌려주고 기기 값을 그대로 둔다', () async {
      // 거짓을 돌려주는 것이 중요하다. 프로필 편집이 이 값으로 *못 불러온
      // 것*과 *설정한 적 없는 것*을 가르고, 전자에서는 칸을 잠근다 —
      // 안 잠그면 선택기 기본값 172·63이 서버에 쓰인다.
      await store.save(weightKg: 60);
      remote.failure = StateError('서버가 죽었다');
      final container = containerWith();

      expect(
        await container.read(bodyProfileProvider.notifier).refresh(),
        isFalse,
      );

      expect(container.read(bodyProfileProvider).weightKg, 60);
    });

    test('연결된 곳이 없으면 묻지 않고 거짓이다', () async {
      final container = containerWith(wired: false);

      expect(
        await container.read(bodyProfileProvider.notifier).refresh(),
        isFalse,
      );
      expect(remote.calls, 0);
    });
  });

  group('처음 읽을 때', () {
    test('⚠️ 아무도 부르지 않아도 서버를 읽는다', () async {
      // 러닝으로 들어오는 길이 네 갈래라 화면마다 부르면 한 군데를 빠뜨린다.
      // **값을 가진 쪽이 스스로 채운다.**
      remote.body = const StoredBody(weightKg: 71);
      final container = containerWith();

      container.read(bodyProfileProvider);
      // 저장소 읽기 → 서버 읽기 두 단계가 비동기로 이어진다.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(remote.calls, 1);
      expect(container.read(bodyProfileProvider).weightKg, 71);
    });

    test('지우면 서버 값도 함께 사라진다', () async {
      remote.body = const StoredBody(weightKg: 71);
      final container = containerWith();
      await container.read(bodyProfileProvider.notifier).refresh();

      await container.read(bodyProfileProvider.notifier).clear();

      // 로그아웃·탈퇴 자리다. 남기면 다음 사람의 칼로리가 남의 몸무게로 나온다.
      expect(container.read(bodyProfileProvider).isEmpty, isTrue);
      expect((await store.read()).isEmpty, isTrue);
    });
  });
}

/// 서버가 무엇이라 답할지 정해 두는 가짜.
class _FakeRemote implements BodyProfileRemote {
  var body = StoredBody.empty;

  /// 주면 그것을 던진다. **`body`가 빈 것과 다르다.**
  Object? failure;

  var calls = 0;

  @override
  Future<StoredBody> fetchBody() async {
    calls++;
    final reason = failure;
    if (reason != null) throw reason;
    return body;
  }
}
