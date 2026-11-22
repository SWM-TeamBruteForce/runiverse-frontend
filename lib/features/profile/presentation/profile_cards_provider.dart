import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 누구의 카드를, 몇 장까지.
///
/// ⚠️ **`limit`이 키에 들어간다.** 그리드는 7장만 묻고(6장 + "더 있나" 한 장)
/// 전체 보기는 전부 받는다 — 둘은 **다른 조회**다. 키에서 빼면 전체 보기가
/// 그리드의 7장을 그대로 쓴다.
typedef ProfileCardsQuery = ({String userId, int? limit});

/// 프로필에 세울 **그 사람의 공개된 카드**(설계 6-7).
///
/// ## ⚠️ `profile/`에 있고 `record_card`의 provider를 읽는다
///
/// CLAUDE.md는 다른 feature의 **화면·위젯** import를 막지만 **provider는
/// 예외**로 적어 두었다. 그리드가 `profile/`에 있는 이유는 설계 7절이다 —
/// 반대로 두면 `profile`이 `record_card`의 화면을 가져다 쓴다.
///
/// ## ⚠️ 자동 재시도를 끈다
///
/// Riverpod 3은 실패한 provider를 **10번까지 다시 부른다**(지수 백오프, 합쳐
/// 약 38초 — `ProviderContainer.defaultRetry`). 그동안 화면은 로딩만 돌고
/// **오류 분기에 닿지 못한다.** 403·404는 기다려도 답이 달라지지 않고, 망
/// 오류도 사용자가 `다시 시도`를 누르는 편이 38초보다 낫다
/// (`composeRecordsProvider`에 같은 주석이 있다).
///
/// ## ⚠️ 화면을 닫으면 버린다
///
/// 남의 프로필을 여럿 다녀오면 사람마다 목록이 하나씩 쌓인다. 다시 열 때
/// 새로 받는 편이 맞다 — 그 사이에 카드가 늘거나 줄었다.
final profileCardsProvider = FutureProvider.autoDispose
    .family<List<RecordCard>, ProfileCardsQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) {
      return ref
          .read(recordCardRepositoryProvider)
          .byUser(userId: query.userId, limit: query.limit);
    });
