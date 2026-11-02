/// 눌린 푸시가 데려갈 자리.
///
/// 앱 안 알림함의 랜딩 규칙(와이어프레임 C7, `NotificationPage._open`)과 맞춘다 —
/// 같은 알림이 알림함과 푸시 둘로 오는데 누른 곳에 따라 다른 화면이 열리면 안 된다.
///
/// 라우트 이름은 모른다(`RunResume`과 같은 판단). 이 값은 "어디로"까지만 말하고,
/// 옮기는 일은 `AppShell`이 한다.
sealed class PushLanding {
  const PushLanding();

  /// FCM `data`를 읽는다. **갈 곳이 없으면 `null`이다** — 앱만 열린다.
  ///
  /// 서버 약속: `data` 값은 전부 문자열이고, `type`으로 종류를 가린다.
  /// 모르는 `type`은 무시한다 — 서버가 종류를 늘려도 앱이 깨지지 않는다.
  static PushLanding? of(Map<String, Object?> data) => switch (data['type']) {
    'FRIEND_REQUESTED' || 'FRIEND_ACCEPTED' => _profileOf(data['actorId']),
    // 수락·거절 버튼이 알림함에 있다.
    'RUNNING_INVITED' => const PushLandingNotifications(),
    'MATCH_CONFIRMED' || 'RUNNING_REMINDER' => const PushLandingRoom(),
    _ => null,
  };

  static PushLanding? _profileOf(Object? actorId) =>
      actorId is String && actorId.isNotEmpty
      ? PushLandingProfile(actorId)
      : null;
}

/// 상대 프로필.
final class PushLandingProfile extends PushLanding {
  const PushLandingProfile(this.userId);

  final String userId;
}

/// 알림함.
final class PushLandingNotifications extends PushLanding {
  const PushLandingNotifications();
}

/// 대기방. **아직 방에 있을 때만 연다** — 푸시가 온 뒤에 방을 나갔을 수 있다.
final class PushLandingRoom extends PushLanding {
  const PushLandingRoom();
}
