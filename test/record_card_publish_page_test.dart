import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_publish_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
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

    testWidgets('누르면 카드를 만들어 넘긴다', (tester) async {
      RecordCard? saved;
      await _pump(tester, onSaved: (card) => saved = card);

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.reviewText, '좋았다');
    });

    testWidgets('⚠️ 도는 동안 버튼이 진행 표시로 바뀐다', (tester) async {
      // `onPressed: null`만 두면 눌리지 않는 이유가 안 보여 계속 누른다.
      await _pump(tester, delay: const Duration(milliseconds: 50));

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOne);
      expect(find.text(AppStrings.recordCardPublishSave), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text(AppStrings.recordCardPublishSave), findsOne);
    });

    testWidgets('⚠️ 두 번 눌러도 실패했다고 하지 않는다', (tester) async {
      // 자르기가 UI 스레드를 잡아 버튼이 진행 표시로 바뀌기 전에 두 번째 탭이
      // 옛 위젯 트리에 맞는다. 재진입 가드가 `null`을 주고 화면이 그것을
      // 실패로 읽으면, **저장은 됐는데 "저장하지 못했어요"를 본 직후 상세로**
      // 떨어진다 — 됐는지 안 됐는지 알 수 없다.
      RecordCard? saved;
      await _pump(
        tester,
        delay: const Duration(milliseconds: 300),
        onSaved: (card) => saved = card,
      );

      // pump 없이 연달아 — 한 프레임 안에서 두 번 맞는 것을 흉내낸다.
      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardPublishSaveFailed), findsNothing);
      expect(saved, isNotNull);
    });

    testWidgets('⚠️ 실패하면 화면에 머물고 왜인지 말한다', (tester) async {
      RecordCard? saved;
      final container = await _pump(
        tester,
        failWith: RecordCardFailure.network,
        onSaved: (card) => saved = card,
      );

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.text(AppStrings.recordCardPublishSaveFailed), findsOne);
      expect(find.byType(CardPublishPage), findsOne);
      // 쓴 글이 남아 있어야 다시 누를 수 있다.
      expect(container.read(cardDraftProvider(null)).reviewText, '좋았다');
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
  Duration delay = Duration.zero,
  RecordCardFailure? failWith,
  void Function(RecordCard card)? onSaved,
}) async {
  final container = ProviderContainer(
    overrides: [
      recordCardRepositoryProvider.overrideWithValue(
        FakeRecordCardRepository(
          today: DateTime(2026, 11, 18),
          delay: delay,
          failWith: failWith,
        ),
      ),
      // 진짜는 `dart:ui`와 플랫폼 플러그인을 써서 테스트 환경에 없다.
      imageCropperProvider.overrideWithValue(_Cropper()),
    ],
  );
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
        home: CardPublishPage(onSaved: onSaved),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 자르지 않고 받은 경로를 그대로 돌려준다.
class _Cropper implements ImageCropper {
  @override
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
    double alignX = 0,
  }) async => image;

  @override
  Future<void> discard(PickedImage cropped) async {}
}
