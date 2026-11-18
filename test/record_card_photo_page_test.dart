import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_page.dart';

/// 기록카드 작성 2 — 사진 (설계 6-3).
///
/// ## ⚠️ 사진은 선택이다
///
/// 한 장도 없이 `다음`을 누를 수 있다. 빈 상태가 권유가 아니라 **괜찮다는
/// 말**이어야 한다.
void main() {
  group('빈 상태', () {
    testWidgets('사진이 없으면 괜찮다고 말한다', (tester) async {
      await _pump(tester);

      expect(find.text(AppStrings.recordCardPhotoEmpty), findsOne);
      expect(find.text(AppStrings.recordCardPhotoTitle(0, 5)), findsOne);
    });

    testWidgets('⚠️ 사진이 없어도 다음이 열려 있다', (tester) async {
      await _pump(tester);

      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 기록·유형·회고가 비면 다음이 닫힌다', (tester) async {
      // 작성 1을 거치지 않고 떨어진 경우다. 라우터가 돌려보내지만, 화면도
      // 스스로 막는다 — 저장할 수 없는 것을 보낼 수 없다.
      await _pump(tester, draft: const CardDraft());

      expect(_nextEnabled(tester), isFalse);
    });

    testWidgets('사진이 없으면 캡션 칸도 지우기도 없다', (tester) async {
      await _pump(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.text(AppStrings.recordCardPhotoRemove), findsNothing);
    });

    testWidgets('빈 상태도 라이트에서 그려진다', (tester) async {
      await _pump(tester, light: true);

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.recordCardPhotoEmpty), findsOne);
    });
  });

  group('사진 고르기', () {
    testWidgets('고르면 초안에 쌓이고 제목이 센다', (tester) async {
      final container = await _pump(tester, picker: _Picker.ok('/tmp/a.jpg'));

      await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
      expect(find.text(AppStrings.recordCardPhotoTitle(1, 5)), findsOne);
    });

    testWidgets('⚠️ 취소는 실패가 아니다', (tester) async {
      // 올릴 생각을 접었을 뿐인 사람에게 "못 가져왔다"고 하면 거짓말이다.
      final container = await _pump(tester, picker: _Picker.cancelled());

      await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardPhotoPickFailed), findsNothing);
      expect(container.read(cardDraftProvider(null)).photos, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('형식이 안 맞으면 형식 탓이라고 말한다', (tester) async {
      await _pump(
        tester,
        picker: _Picker.fails(ProfileImageFailure.unsupportedFormat),
      );

      await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardPhotoUnsupported), findsOne);
    });

    testWidgets('너무 크면 크다고 말한다', (tester) async {
      await _pump(tester, picker: _Picker.fails(ProfileImageFailure.tooLarge));

      await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardPhotoTooLarge), findsOne);
    });

    testWidgets('⚠️ 다섯 장이 차면 거절을 말한다', (tester) async {
      // 조용히 아무 일도 안 하면 고장으로 읽힌다.
      final container = await _pump(
        tester,
        draft: _ready(photos: 5),
        picker: _Picker.ok('/tmp/f.jpg'),
      );

      await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardPhotoLimit(5)), findsOne);
      expect(container.read(cardDraftProvider(null)).photos, hasLength(5));
    });
  });

  group('캡션', () {
    testWidgets('쓰면 초안에 남고 글자 수가 보인다', (tester) async {
      final container = await _pump(tester, draft: _ready(photos: 1));

      await tester.enterText(find.byType(TextField), '바람이 좋았다');
      await tester.pump();

      expect(
        container.read(cardDraftProvider(null)).photos.first.caption,
        '바람이 좋았다',
      );
      expect(
        find.text(AppStrings.recordCardPhotoCaptionCounter(7, 100)),
        findsOne,
      );
    });

    testWidgets('AI가 읽는다고 알려 준다', (tester) async {
      await _pump(tester, draft: _ready(photos: 1));

      expect(find.text(AppStrings.recordCardPhotoCaptionNote), findsOne);
    });

    testWidgets('⚠️ 장을 넘기면 그 장의 캡션이 칸에 들어온다', (tester) async {
      // 장마다 컨트롤러를 새로 만들지 않고 하나를 갈아 끼운다. 안 갈면 2번째
      // 장에 1번째 캡션이 보이고, 고치면 엉뚱한 장에 붙는다.
      await _pump(tester, draft: _ready(photos: 2, captions: ['첫째', '둘째']));
      expect(_fieldText(tester), '첫째');

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(_fieldText(tester), '둘째');
    });
  });

  group('지우기', () {
    testWidgets('지우면 그 장이 빠진다', (tester) async {
      final container = await _pump(tester, draft: _ready(photos: 2));

      await _tapBelow(tester, find.text(AppStrings.recordCardPhotoRemove));

      expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
      expect(find.text(AppStrings.recordCardPhotoTitle(1, 5)), findsOne);
    });

    testWidgets('⚠️ 보고 있던 마지막 장을 지워도 깨지지 않는다', (tester) async {
      // 3장 중 3번째를 보다가 지우면 가리키는 곳이 없다. 컨트롤러를 맞춰 주지
      // 않으면 범위를 넘는 자리를 그리려다 죽는다.
      await _pump(tester, draft: _ready(photos: 3, captions: ['ㄱ', 'ㄴ', 'ㄷ']));
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'ㄷ');

      await _tapBelow(tester, find.text(AppStrings.recordCardPhotoRemove));

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.recordCardPhotoTitle(2, 5)), findsOne);
      // 뒤가 없으니 앞 장을 본다.
      expect(_fieldText(tester), 'ㄴ');
    });

    testWidgets('마지막 한 장을 지우면 빈 상태로 돌아간다', (tester) async {
      await _pump(tester, draft: _ready(photos: 1));

      await _tapBelow(tester, find.text(AppStrings.recordCardPhotoRemove));

      expect(find.text(AppStrings.recordCardPhotoEmpty), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('뒤로', () {
    testWidgets('⚠️ 묻지 않고 초안을 지킨 채 돌아간다', (tester) async {
      // 확인은 작성 1의 뒤로가기에서만 받는다(설계 7절). 여기서 또 물으면
      // 사진을 보러 들어왔다 나가는 사람이 세 번 막힌다.
      final container = await _pump(tester, draft: _ready(photos: 1));

      // `pageBack`은 Material·Cupertino 기본 뒤로만 찾는다. 이 화면의 뒤로는
      // Lucide 아이콘을 쓴 `IconButton`이다 (CLAUDE.md — 아이콘은 Lucide만).
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.byType(CardPhotoPage), findsNothing);
      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
      expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
    });
  });

  testWidgets('장이 둘 이상이면 몇 번째인지 읽힌다', (tester) async {
    await _pump(tester, draft: _ready(photos: 2));

    expect(
      find.bySemanticsLabel(AppStrings.recordCardPhotoSemantics(1, 2)),
      findsOne,
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

/// 작성 1을 통과한 초안. **사진만 비어 있다.**
CardDraft _ready({int photos = 0, List<String>? captions}) => CardDraft(
  record: _record(),
  activity: RecordCardActivity.daily,
  reviewText: '좋았다',
  photos: [
    for (var i = 0; i < photos; i++)
      CardPhotoDraft(
        image: PickedImage.validated(path: '/tmp/p$i.jpg', sizeBytes: 1024),
        caption: captions == null ? '' : captions[i],
      ),
  ],
);

bool _nextEnabled(WidgetTester tester) {
  final button = tester.widget<TextButton>(
    find.ancestor(
      of: find.text(AppStrings.recordCardComposeNext),
      matching: find.byType(TextButton),
    ),
  );
  return button.onPressed != null;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// 화면 밖에 있는 것을 끌어 올려 누른다.
///
/// ⚠️ **`ListView(children:)`는 화면 밖 자식을 아예 만들지 않는다.** 9:16
/// 미리보기(320dp)에 점·안내·캡션 칸이 쌓이면 지우기 버튼이 600dp 테스트
/// 화면 밑으로 내려간다 — 기기(915dp)에서는 보이는 자리다.
Future<void> _tapBelow(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView),
    const Offset(0, -80),
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CardDraft? draft,
  PhotoPicker? picker,
  bool light = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (picker != null) photoPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);

  final start = draft ?? _ready();
  final controller = container.read(cardDraftProvider(null).notifier);
  if (start.record != null) controller.pickRecord(start.record!);
  if (start.activity != null) controller.setActivity(start.activity!);
  controller.setReview(start.reviewText);
  for (final photo in start.photos) {
    controller.addPhoto(photo.image);
  }
  for (var i = 0; i < start.photos.length; i++) {
    controller.setCaption(i, start.photos[i].caption);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        // `pageBack`이 돌아갈 자리를 둔다 — 작성 1을 흉내낸다.
        home: const _Previous(),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return container;
}

/// 작성 2를 미는 앞 화면. 뒤로가 돌아갈 데가 있어야 `pageBack`이 돈다.
class _Previous extends StatelessWidget {
  const _Previous();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const CardPhotoPage())),
        child: const Text('열기'),
      ),
    ),
  );
}

class _Picker implements PhotoPicker {
  _Picker._({this.path, this.failure});

  factory _Picker.ok(String path) => _Picker._(path: path);
  factory _Picker.cancelled() => _Picker._();
  factory _Picker.fails(ProfileImageFailure failure) =>
      _Picker._(failure: failure);

  final String? path;
  final ProfileImageFailure? failure;

  @override
  Future<PickedImage?> pick() async {
    final failure = this.failure;
    if (failure != null) throw ProfileImageException(failure);
    final path = this.path;
    if (path == null) return null; // 취소
    return PickedImage.validated(path: path, sizeBytes: 1024);
  }
}
