import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 그날 기록카드를 쓸 수 있는 러닝 기록들. **인자는 날짜다.**
///
/// ## ⚠️ 두 조회를 겹쳐 부른다
///
/// 러닝 기록과 그날 카드를 둘 다 받아야 "이 기록에는 이미 카드가 있다"를
/// 말할 수 있다(설계 10절 질문 3이 아직 답을 못 받았다 —
/// [joinCards] 참고). 줄 세우면 왕복이 두 배라 둘을 먼저 띄우고 나중에
/// 기다린다.
///
/// ## ⚠️ 날짜만 본다
///
/// 시·분이 붙어 와도 잘라서 조회한다. 그러지 않으면 **같은 날이 provider
/// 여러 개로 갈려** 화면을 다시 그릴 때마다 조회가 새로 나간다.
///
/// 날짜를 옮겨 다니는 조회라 화면을 닫으면 버린다(`autoDispose`).
///
/// ## ⚠️ 자동 재시도를 끈다
///
/// Riverpod 3은 실패한 provider를 **10번까지 다시 부른다**(지수 백오프,
/// 200ms→6.4s, 합쳐 약 38초 — `ProviderContainer.defaultRetry`). 그동안
/// 화면은 로딩만 돌고 **오류 분기에 닿지 않는다.** 세션 만료·403·404는
/// 기다린다고 답이 달라지지 않고(`RunRecordFailure.notFound`가 같은 말을
/// 적어 뒀다), 망 오류도 사용자가 `다시 시도`를 누르는 편이 38초보다 낫다.
final composeRecordsProvider = FutureProvider.autoDispose
    .family<List<ComposableRecord>, DateTime>(retry: (_, _) => null, (
      ref,
      when,
    ) async {
      final day = DateTime(when.year, when.month, when.day);

      final recordsSoon = ref
          .read(runRecordRepositoryProvider)
          .byDateRange(from: day, to: day);
      final cardsSoon = ref
          .read(recordCardRepositoryProvider)
          .byDateRange(from: day, to: day);

      // ⚠️ **`Future.wait`로 묶는다.** `await`를 한 줄씩 쓰면, 먼저 기다리는
      // 쪽이 끝나기 전에 다른 쪽이 깨질 때 그 오류를 **아무도 받지 않는다** —
      // 핸들러 없는 비동기 오류가 되어 터진다. `Future.wait`는 양쪽에 손을
      // 얹고 첫 오류만 올려 준다.
      //
      // ⚠️ 레코드 문법 `(a, b).wait`를 쓰지 않는다 — 오류를
      // `ParallelWaitError`로 싸서 화면의 실패 분기에 안 걸린다.
      //
      // ⚠️ **카드 조회 실패를 삼키지 않는다.** 카드가 있는 기록을 "없음"으로
      // 보여 주면 중복 작성으로 끌고 가고, 저장에서 거절당해 쓴 글을 잃는다.
      // 한 줄 오류와 다시 시도가 낫다.
      final both = await Future.wait<Object>([recordsSoon, cardsSoon]);

      return joinCards(
        records: both[0] as List<RunRecord>,
        cards: both[1] as List<RecordCard>,
      );
    });
