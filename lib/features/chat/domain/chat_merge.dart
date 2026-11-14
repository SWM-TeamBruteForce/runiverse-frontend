import 'package:runiverse/features/chat/domain/chat.dart';

/// 같은 `chatId`를 두 번 받았을 때 어느 쪽을 남길지 고른다.
///
/// ## ⚠️ 나중에 받은 것으로 덮으면 안 된다
///
/// 목록 응답·이전 페이지·실시간 이벤트·전송·수정 API 응답이 **겹쳐서** 같은
/// 메시지를 싣고 온다. 받은 순서로 덮으면 둘 다 터진다.
///
/// - 수정을 반영한 뒤 오래된 목록 응답이 오면 **수정 전 내용이 되살아난다**
/// - 먼저 도착한 전송 이벤트가 **이미 지운 메시지를 되살린다**
///
/// 그래서 순서가 아니라 규칙으로 고른다(연동 가이드 2-2). 이 규칙을 쓰면
/// 이벤트를 모아 두고 재생할 필요가 없다 — **받는 즉시 합치면 된다.**
///
/// 1. 삭제 상태가 이긴다 — 한 번 지워진 메시지는 되살아나지 않는다
/// 2. 둘 다 안 지워졌으면 `editedAt`이 늦은 쪽. `null`은 **가장 이른 것**이다
/// 3. `editedAt`이 같으면 나중에 받은 쪽 — 초 단위라 같은 값이 온다
///
/// ⚠️ **순서가 중요하다.** `editedAt`을 먼저 보면 지운 뒤에 온 수정이 삭제를
/// 덮는다.
///
/// 3번은 수신 순서에 의존한다. 같은 초에 여러 번 고친 메시지까지 순서와
/// 무관한 결과를 보장하지는 않는다 — 현재 계약이 그렇다.
Chat mergeChat(Chat kept, Chat arrived) {
  final winner = _winnerOf(kept, arrived);

  // ⚠️ **읽음은 서버가 모르는 값이다.** 고른 쪽의 `isRead`를 그대로 쓰면 이미
  // 읽은 말이 수정 이벤트 하나로 다시 배지에 세어진다 — 보고 있는 화면에서
  // 숫자가 늘어난다. 한쪽이라도 읽었으면 읽은 것이다.
  final isRead = kept.isRead || arrived.isRead;
  return winner.isRead == isRead ? winner : winner.copyWith(isRead: isRead);
}

Chat _winnerOf(Chat kept, Chat arrived) {
  // 1. 삭제가 이긴다. **가장 먼저 본다.**
  if (kept.isDeleted) return kept;
  if (arrived.isDeleted) return arrived;

  // 2. `editedAt`이 늦은 쪽. `null`은 가장 이른 것이라, 들고 있는 쪽만 값이
  //    있으면 그쪽이 이긴다.
  final keptAt = kept.editedAt;
  final arrivedAt = arrived.editedAt;
  if (keptAt != null && (arrivedAt == null || keptAt.isAfter(arrivedAt))) {
    return kept;
  }

  // 3. 같거나(둘 다 `null`인 경우 포함) 들어온 쪽이 늦다 — 나중에 받은 쪽.
  return arrived;
}

/// [arrivals]를 [current]에 합친다. **`chatId` 오름차순으로 돌려준다.**
///
/// 없는 `chatId`는 새로 넣고, 있는 것은 [mergeChat]으로 합친다. 한 묶음 안에
/// 같은 `chatId`가 두 번 있어도 같은 규칙으로 합쳐진다 — 목록과 이벤트를 한
/// 번에 넘기는 경우가 있다.
///
/// ⚠️ **아직 불러오지 않은 과거 메시지도 들인다.** 수정·삭제 이벤트가 그
/// 메시지보다 먼저 올 수 있는데, 버리면 이전 페이지를 받을 때 지운 메시지가
/// 되살아난다. 들여 두면 같은 규칙이 그것을 막는다.
List<Chat> mergeChats(List<Chat> current, Iterable<Chat> arrivals) {
  if (arrivals.isEmpty) return current;

  final byId = <int, Chat>{for (final one in current) one.chatId: one};
  for (final arrived in arrivals) {
    final kept = byId[arrived.chatId];
    byId[arrived.chatId] = kept == null ? arrived : mergeChat(kept, arrived);
  }

  final merged = byId.values.toList()
    ..sort((a, b) => a.chatId.compareTo(b.chatId));
  return merged;
}
