/// 파티 색의 자리. **나는 늘 0번(파랑)이다.**
///
/// ## ⚠️ 규칙이 한 곳에 있어야 한다
///
/// 전에는 세 화면이 각자 정했다 — 러닝 중 화면은 명단 순서를 그대로 썼고
/// (그래서 **방마다 내 색이 바뀌었다**), 결과 화면은 나를 파랑으로 고정했고,
/// 카운트다운은 그리는 순서대로 줬다. 같은 러닝을 세 화면에서 보면 색이 세
/// 벌이었다.
///
/// ## 나를 0번으로 두는 이유
///
/// 0번은 브랜드 파랑(`#227DFF`)이고 테마의 `primary`와 같은 값이다. 어느 방에서
/// 몇 번째에 서든 내 것이 같은 색이라, 화면을 옮겨 다녀도 내 것을 찾는 눈이
/// 흔들리지 않는다.
///
/// 나머지는 **나를 뺀 순서**로 1번부터 받는다. 방 정원이 4명이라 나 하나와
/// 상대 셋이 팔레트 4색에 꼭 맞는다.
library;

/// [userId]의 색 자리.
///
/// [order]는 색을 나눠 가질 사람들의 순서다 — **서버가 준 명단 순서**를
/// 넘긴다. 통지가 온 순서로 주면 재시작할 때마다 색이 바뀐다.
///
/// ⚠️ [order]에 없는 사람은 팔레트 **끝 색**을 받는다. `0`으로 떨어뜨리면
/// 남이 나로 보인다.
int partyColorSlot({
  required String userId,
  required String? myUserId,
  required List<String> order,
}) {
  if (myUserId != null && userId == myUserId) return 0;

  final others = [
    for (final id in order)
      if (id != myUserId) id,
  ];
  final index = others.indexOf(userId);
  return index < 0 ? partyColorSlots - 1 : index + 1;
}

/// 팔레트가 가진 색 수. 방 정원과 같다.
const partyColorSlots = 4;
