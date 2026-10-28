/// 나와 상대의 관계. **항상 조회하는 사람 기준**이다.
///
/// 같은 두 사람이라도 보는 쪽에 따라 값이 다르다 — 내가 보낸 요청은 나에게
/// [requestSent], 상대에게 [requestReceived]다.
library;

/// 관계 네 가지.
enum FriendRelation {
  /// 아무 사이도 아니다. 거절·취소·삭제로 되돌아온 경우도 여기다.
  none,

  /// 내가 요청을 보냈다. 기다리는 중이다.
  requestSent,

  /// 상대가 나에게 요청했다. **내가 답할 차례다.**
  requestReceived,

  /// 친구다.
  friend,
}

/// 서버가 준 값을 읽는다. **모르는 값이면 `null`이다.**
///
/// ## ⚠️ 어휘가 둘이다
///
/// 서버가 같은 뜻을 두 말로 준다.
///
/// | 뜻 | 친구 API `relationshipType` | 프로필 API `friendStatus` |
/// |---|---|---|
/// | 관계 없음 | `NONE` | `NONE` |
/// | 내가 보냄 | `FRIEND_REQUEST_SENT` | `PENDING_SENT` |
/// | 내가 받음 | `FRIEND_REQUEST_RECEIVED` | `PENDING_RECEIVED` |
/// | 친구 | `FRIEND` | `ACCEPTED` |
///
/// 둘 다 여기서 읽는다. **한쪽만 읽으면 친구인 사람에게 "친구 요청" 버튼이
/// 뜨고**, 눌러 봐야 `409`만 돌아온다.
///
/// ⚠️ **`null`을 아무 값으로 뭉개지 않는다.** 목록 항목이 나 자신이면 서버가
/// `null`을 준다. [FriendRelation.none]으로 읽으면 **내 줄에 "친구 요청"
/// 버튼이 선다.** 서버가 관계를 늘려도 마찬가지다 — 모르면 모른다고 둔다.
FriendRelation? friendRelationOf(Object? wire) => switch (wire) {
  'NONE' => FriendRelation.none,
  'FRIEND_REQUEST_SENT' || 'PENDING_SENT' => FriendRelation.requestSent,
  'FRIEND_REQUEST_RECEIVED' ||
  'PENDING_RECEIVED' => FriendRelation.requestReceived,
  'FRIEND' || 'ACCEPTED' => FriendRelation.friend,
  _ => null,
};
