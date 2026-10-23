import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';

/// 액세스 토큰을 갱신한다. **한 번에 하나만 나간다.**
///
/// ## ⚠️ 동시에 두 번 부르면 사용자가 로그아웃된다
///
/// 서버가 리프레시 토큰을 **회전**시킨다. 두 요청이 같은 토큰으로 동시에 들어가면
/// 두 번째는 이미 회전된 토큰을 보내게 되고, 백엔드 `ReissueHandler`가 그 해시
/// 불일치를 **탈취로 보고 리프레시 토큰을 지운다.** 잘못이 없는 사용자가
/// 로그아웃된다 (`docs/implementation-notes.md` 9-6).
///
/// 러닝을 시작할 때 이 상황이 실제로 만들어진다 — `POST /running-rooms/solo`와
/// WebSocket 핸드셰이크가 **같은 만료 토큰으로 거의 동시에** 나간다.
///
/// 그래서 진행 중인 갱신이 있으면 그것을 함께 기다린다.
///
/// ## 왜 `core`가 아니라 여기인가
///
/// [AuthRepository]를 알아야 한다. `core`가 그것을 import하면 `core → features`
/// 방향이 생겨 의존 방향이 뒤집힌다 (`TokenStore`와 같은 판단).
///
/// 쓰는 쪽은 대개 `core`에 있으므로 **함수 하나만 넘겨받는다** — `WsClient`는
/// 이 클래스를 모르고 `Future<String?> Function()`만 안다.
class TokenRefresher {
  TokenRefresher(this._auth, this._store, {this.onExpired});

  final AuthRepository _auth;
  final TokenStore _store;

  /// 갱신이 **거절**됐을 때 부른다. 네트워크 실패에는 부르지 않는다.
  ///
  /// ## 왜 여기서 로그아웃하지 않고 알리기만 하나
  ///
  /// 세션을 끝내는 것은 화면·인증 쪽의 판단이다. 이 클래스는 토큰만 다룬다 —
  /// 여기서 저장소를 비우면 `AuthController`가 모르는 채로 상태가 어긋난다.
  ///
  /// ⚠️ **이걸 아무도 안 들으면 달리는 사람이 갇힌다.** 리프레시가 죽었는데
  /// 알릴 곳이 없으면 앱은 "연결하는 중"만 되풀이하고, 러닝을 끝낼 수도
  /// 재로그인할 수도 없다(2026-09-18 23:47 실주행).
  final void Function()? onExpired;

  /// 지금 나가 있는 갱신. 없으면 `null`.
  Future<String?>? _inflight;

  /// 새 액세스 토큰. **못 받으면 `null`이고, 그때는 재로그인해야 한다.**
  ///
  /// 이미 나가 있는 갱신이 있으면 새로 부르지 않고 그것을 기다린다.
  /// 그래서 동시에 열 곳에서 불러도 서버로는 한 번만 나간다.
  Future<String?> refresh() {
    final running = _inflight;
    if (running != null) return running;

    final started = _run();
    _inflight = started;
    // ⚠️ **끝나면 비운다.** 안 비우면 다음에 만료됐을 때 지난 결과를 그대로
    // 돌려주고, 앱이 죽은 토큰으로 영원히 두드리게 된다.
    started.whenComplete(() {
      if (identical(_inflight, started)) _inflight = null;
    });
    return started;
  }

  Future<String?> _run() async {
    final refreshToken = (await _store.read()).refreshToken;
    if (refreshToken == null) return null;

    try {
      final tokens = await _auth.refresh(refreshToken);
      // ⚠️ 회전된 리프레시 토큰도 반드시 덮어쓴다. 안 하면 다음 갱신이 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      // 여기서 저장소를 비우지 않는다 — 로그아웃 시점을 정하는 것은 화면 쪽의
      // 판단이다.
      //
      // ⚠️ **거절과 실패를 가른다.** 네트워크·5xx는 지나가므로 다시 해보면
      // 되지만, `sessionExpired`는 몇 번을 해도 같은 답이다. 그것만 알린다 —
      // 터널에 들어갔다고 로그아웃시키면 안 된다.
      if (error.failure == AuthFailure.sessionExpired) onExpired?.call();
      return null;
    }
  }
}
