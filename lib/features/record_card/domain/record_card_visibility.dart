/// 이 카드를 누가 볼 수 있나.
///
/// ## ⚠️ 서버 값 이름이 아직 협의 중이다
///
/// 백엔드 DB 초안은 `('PUBLIC', 'FOLLOWERS', 'PRIVATE')`인데, 앱은 팔로우가
/// 아니라 **요청→수락 상호 친구 모델**이다(`features/friend/`). 값을
/// `FRIENDS`로 맞춰 달라고 요청해 두었다
/// (`docs/notes/2026-11-16-record-card-backend-questions.md` 2번).
///
/// 그동안 **보낼 때는 `FRIENDS`, 받을 때는 둘 다** 받는다.
enum RecordCardVisibility {
  public('PUBLIC'),
  friends('FRIENDS'),
  private('PRIVATE');

  const RecordCardVisibility(this.wire);

  /// 서버로 보낼 코드.
  final String wire;

  /// 서버 값을 읽는다. **모르는 값이면 [private]이다.**
  ///
  /// ## ⚠️ 여기만 `RecordCardActivity.of`와 다르다
  ///
  /// 유형은 모르면 `null`로 두지만 공개범위는 그럴 수 없다. 모르는 값을
  /// `public`으로 읽으면 **나만 보려던 카드가 남에게 보인다.** 모르면 가장
  /// 좁게 잡는 쪽이 안전하다 — 덜 보이는 것은 고칠 수 있고, 더 보인 것은
  /// 되돌릴 수 없다.
  static RecordCardVisibility of(Object? wire) => switch (wire) {
    'PUBLIC' => RecordCardVisibility.public,
    // 서버가 아직 쓰는 옛 이름. 뜻은 같다.
    'FRIENDS' || 'FOLLOWERS' => RecordCardVisibility.friends,
    _ => RecordCardVisibility.private,
  };
}
