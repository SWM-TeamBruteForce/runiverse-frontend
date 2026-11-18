import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_publish_page.dart';
import 'package:runiverse/features/record_card/presentation/visibility_label.dart';

/// 기록카드 작성 3 — 공개범위 · 음악 (설계 6-4).
///
/// ## ⚠️ 경고가 공개범위에 매여 있다
///
/// `PUBLIC`·`FRIENDS`에서만 경로가 남에게 보인다. 경고를 늘 띄우면 나만 보기로
/// 바꾼 사람에게 거짓말이 되고, 아예 안 띄우면 집 근처가 드러나는 것을 모르고
/// 공개한다.
void main() {
  group('기본값', () {
    testWidgets('친구 공개와 음악 켜짐이다', (tester) async {
      await _pump(tester);

      expect(
        _selected(tester, RecordCardVisibility.friends),
        isTrue,
        reason: '설계 6-4가 친구 공개를 기본으로 정했다',
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('셋이 모두 이름과 설명을 보인다', (tester) async {
      await _pump(tester);

      for (final visibility in RecordCardVisibility.values) {
        expect(find.text(recordCardVisibilityLabel(visibility)), findsOne);
        expect(find.text(recordCardVisibilityBody(visibility)), findsOne);
      }
    });

    testWidgets('음악이 무엇을 만드는지 말한다', (tester) async {
      await _pump(tester);

      expect(find.text(AppStrings.recordCardPublishMusicTitle), findsOne);
      expect(find.text(AppStrings.recordCardPublishMusicBody), findsOne);
    });

    testWidgets('라이트에서도 그려진다', (tester) async {
      await _pump(tester, light: true);

      expect(tester.takeException(), isNull);
      expect(
        find.text(AppStrings.recordCardPublishVisibilitySection),
        findsOne,
      );
    });
  });

  group('경로 경고', () {
    testWidgets('⚠️ 친구 공개와 전체 공개에서만 뜬다', (tester) async {
      await _pump(tester);
      expect(find.text(AppStrings.recordCardPublishRouteWarning), findsOne);

      await _choose(tester, RecordCardVisibility.private);
      expect(
        find.text(AppStrings.recordCardPublishRouteWarning),
        findsNothing,
        reason: '나만 보기는 남에게 안 보인다 — 경고가 거짓말이 된다',
      );

      await _choose(tester, RecordCardVisibility.public);
      expect(find.text(AppStrings.recordCardPublishRouteWarning), findsOne);
    });

    testWidgets('⚠️ 지도가 아니라 선이라고 말한다', (tester) async {
      // 기록카드의 경로는 배경 없는 선 아트다(설계 3절). 설계 6-4의 문구는
      // "지도로"인데, 보이지도 않는 것을 경고하면 사실이 아니다.
      await _pump(tester);

      expect(find.textContaining('지도'), findsNothing);
      expect(find.textContaining('선으로'), findsOne);
    });
  });

  group('고른 것이 초안에 남는다', () {
    testWidgets('공개범위', (tester) async {
      final container = await _pump(tester);

      await _choose(tester, RecordCardVisibility.private);

      expect(
        container.read(cardDraftProvider(null)).visibility,
        RecordCardVisibility.private,
      );
      expect(_selected(tester, RecordCardVisibility.private), isTrue);
    });

    testWidgets('음악 토글', (tester) async {
      final container = await _pump(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).musicEnabled, isFalse);
    });
  });

  group('저장 버튼', () {
    testWidgets('기록·유형·회고가 차 있으면 열려 있다', (tester) async {
      await _pump(tester);

      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 초안이 비면 닫힌다', (tester) async {
      // 작성 1을 거치지 않고 떨어진 경우다.
      await _pump(tester, empty: true);

      expect(_saveEnabled(tester), isFalse);
    });
  });

  testWidgets('⚠️ 고른 것과 안 고른 것이 갈라 읽힌다', (tester) async {
    // 글자 라벨이 있어도 무엇이 켜졌는지는 테두리 색뿐이라, 이것 없이는
    // 스크린리더가 셋을 구별하지 못한다.
    await _pump(tester);

    expect(_selected(tester, RecordCardVisibility.friends), isTrue);
    expect(_selected(tester, RecordCardVisibility.public), isFalse);
    expect(_selected(tester, RecordCardVisibility.private), isFalse);
    // 누를 수 있는 것이라고도 읽혀야 한다.
    expect(
      _semanticsOf(
        tester,
        RecordCardVisibility.public,
      ).any((s) => s.properties.button == true),
      isTrue,
    );
  });
}

// ── 도움 ──────────────────────────────────────────────────────

RunRecord _record() => RunRecord(
  id: 11,
  runningRoomId: 911,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

/// 고른 것인가. **`Semantics` 위젯의 속성을 직접 본다.**
///
/// ⚠️ `tester.getSemantics`는 `ensureSemantics()` 핸들을 요구하는데, 그 핸들은
/// `addTearDown`으로 풀면 **테스트 끝 검사보다 늦어** "A SemanticsHandle was
/// active"로 전부 빨개진다. 위젯 속성은 같은 약속을 핸들 없이 본다.
bool _selected(WidgetTester tester, RecordCardVisibility visibility) =>
    _semanticsOf(tester, visibility).any((s) => s.properties.selected == true);

Iterable<Semantics> _semanticsOf(
  WidgetTester tester,
  RecordCardVisibility visibility,
) => tester.widgetList<Semantics>(
  find.ancestor(
    of: find.text(recordCardVisibilityLabel(visibility)),
    matching: find.byType(Semantics),
  ),
);

Future<void> _choose(
  WidgetTester tester,
  RecordCardVisibility visibility,
) async {
  await tester.tap(find.text(recordCardVisibilityLabel(visibility)));
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) {
  final button = tester.widget<TextButton>(
    find.ancestor(
      of: find.text(AppStrings.recordCardPublishSave),
      matching: find.byType(TextButton),
    ),
  );
  return button.onPressed != null;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool light = false,
  bool empty = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final handle = container.listen(
    cardDraftProvider(null),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(handle.close);

  if (!empty) {
    final controller = container.read(cardDraftProvider(null).notifier);
    controller.pickRecord(_record());
    controller.setActivity(RecordCardActivity.daily);
    controller.setReview('좋았다');
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: const CardPublishPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
