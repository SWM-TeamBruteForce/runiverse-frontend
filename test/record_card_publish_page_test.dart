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
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
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
    testWidgets('친구 공개다', (tester) async {
      await _pump(tester);

      expect(
        _selected(tester, RecordCardVisibility.friends),
        isTrue,
        reason: '설계 6-4가 친구 공개를 기본으로 정했다',
      );
    });

    testWidgets('저장하면 음악이 만들어진다고 알린다', (tester) async {
      // 고를 수 없는 것과 알리지 않는 것은 다르다. 글을 지우면 저장하는
      // 사람이 **모르는 사이에** AI가 회고와 사진을 읽어 곡을 만든다.
      await _pump(tester);

      expect(find.text(AppStrings.recordCardPublishMusicTitle), findsOne);
      expect(find.text(AppStrings.recordCardPublishMusicBody), findsOne);
    });

    testWidgets('셋이 모두 이름과 설명을 보인다', (tester) async {
      await _pump(tester);

      for (final visibility in RecordCardVisibility.values) {
        expect(find.text(recordCardVisibilityLabel(visibility)), findsOne);
        expect(find.text(recordCardVisibilityBody(visibility)), findsOne);
      }
    });

    testWidgets('⚠️ 음악 생성 토글이 없다', (tester) async {
      // 서버는 **저장하면 늘 음악을 만든다**(연동 가이드 3절: "현재 API는
      // 음악 생성을 항상 요청하므로"). 끌 수 없는 것을 스위치로 보여 주면,
      // 끄고 저장한 사람이 음악이 만들어지는 것을 보게 된다.
      await _pump(tester);

      // 이 화면의 스위치는 음악 토글 하나였다.
      expect(find.byType(Switch), findsNothing);
      // 화면을 잘못 찾은 것이 아니라는 확인.
      expect(find.text(AppStrings.recordCardPublishVisibilitySection), findsOne);
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

  group('카드를 고칠 때', () {
    testWidgets('⚠️ 음악 안내를 보여 주지 않는다', (tester) async {
      // 고치러 온 사람에게 "만들어집니다"는 낡은 말이다 — 음악은 이미
      // 있거나 만들어지는 중이고, 그 카드에 무슨 일이 생기는지는 위의
      // 음악 경고가 말한다.
      await _pump(tester, editing: true);

      expect(find.text(AppStrings.recordCardPublishMusicTitle), findsNothing);
      expect(find.text(AppStrings.recordCardPublishMusicBody), findsNothing);
    });

    testWidgets('⚠️ 새 카드에는 아무 음악 경고도 없다', (tester) async {
      await _pump(tester);

      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsNothing);
      expect(find.text(AppStrings.recordCardMusicRegenerate), findsNothing);
    });

    testWidgets('만드는 중인 카드를 고치면 버려진다고 알린다', (tester) async {
      final container = await _pump(
        tester,
        editing: true,
        music: MusicStatus.processing,
      );

      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsOne);

      await _closePolling(tester, container);
    });

    testWidgets('⚠️ 만드는 중이면 공개범위만 바꿔도 알린다 — 활성 요청이 무효화된다', (tester) async {
      final container = await _pump(
        tester,
        editing: true,
        music: MusicStatus.queued,
      );

      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsOne);

      await _closePolling(tester, container);
    });

    testWidgets('다 된 음악인데 회고를 고치면 다시 만든다고 알린다', (tester) async {
      await _pump(
        tester,
        editing: true,
        music: MusicStatus.succeeded,
        changed: true,
      );

      expect(find.text(AppStrings.recordCardMusicRegenerate), findsOne);
    });

    testWidgets('⚠️ 다 된 음악인데 공개범위만 바꾸면 아무 말도 하지 않는다', (tester) async {
      await _pump(tester, editing: true, music: MusicStatus.succeeded);

      await tester.tap(
        find.text(recordCardVisibilityLabel(RecordCardVisibility.private)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardMusicRegenerate), findsNothing);
      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsNothing);
    });

    testWidgets('음악이 없는 카드를 고치면 아무 말도 하지 않는다', (tester) async {
      await _pump(
        tester,
        editing: true,
        music: MusicStatus.none,
        changed: true,
      );

      expect(find.text(AppStrings.recordCardMusicRegenerate), findsNothing);
      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsNothing);
    });

    testWidgets('⚠️ 실패한 음악을 고치면 아무 말도 하지 않는다 — 잃을 것이 없다', (tester) async {
      await _pump(
        tester,
        editing: true,
        music: MusicStatus.failed,
        changed: true,
      );

      expect(find.text(AppStrings.recordCardMusicRegenerate), findsNothing);
      expect(find.text(AppStrings.recordCardMusicWorkingEdit), findsNothing);
    });

    testWidgets('공개범위는 그대로 고칠 수 있다', (tester) async {
      await _pump(tester, editing: true);

      expect(
        find.text(AppStrings.recordCardPublishVisibilitySection),
        findsOne,
      );
      expect(find.text(AppStrings.recordCardPublishSave), findsOne);
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
  bool editing = false,
  MusicStatus music = MusicStatus.none,
  bool changed = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      recordCardRepositoryProvider.overrideWithValue(
        _MusicOverride(
          FakeRecordCardRepository(
            today: DateTime(2026, 11, 18),
            delay: delay,
            failWith: failWith,
          ),
          music,
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

  final cardId = editing ? _editCard.id : null;
  if (editing) {
    container.read(cardDraftProvider(cardId).notifier).seed(_editCard);
    // AI가 읽는 값을 하나 고친다 — 전곡 재생성을 부르는 입력이다.
    if (changed) {
      container.read(cardDraftProvider(cardId).notifier).setReview('다른 글');
    }
  } else if (!empty) {
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
        home: CardPublishPage(cardId: cardId, onSaved: onSaved),
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

/// 고치는 카드. ⚠️ **음악 상태가 없다** — `RecordCard`에 그 필드가 없다.
final _editCard = RecordCard(
  id: 'card-7',
  runningRecordId: 11,
  startedAt: DateTime(2026, 11, 2, 7),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: '여행에서 뛰었다',
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: 3050,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);

/// ⚠️ **폴링 타이머를 남기고 끝내면 테스트가 실패한다**(`!timersPending`).
///
/// 만드는 중인 음악에는 끝이 없다 — 가짜가 아니라 **진짜가 그렇다**(큐에서
/// 6시간, 설계 3절). 화면을 걷어 provider를 버린다.
Future<void> _closePolling(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // 다 된 것으로 바꾸고 한 번 더 묻게 한다 — 끝 상태에서는 폴링이 멈춘다.
  (container.read(recordCardRepositoryProvider) as _MusicOverride).status =
      MusicStatus.succeeded;
  await tester.pump(CardMusicController.pollInterval);
  await tester.pump();
}

/// 음악 상태만 갈아 끼운 저장소. **나머지는 가짜에 그대로 넘긴다.**
///
/// 고치는 카드([_editCard])는 가짜의 목에 없어서, 안 끼우면 음악 조회가
/// `notFound`로 떨어진다.
class _MusicOverride implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _MusicOverride(this._inner, this.status);

  final FakeRecordCardRepository _inner;

  /// 도중에 바꿀 수 있다 — 테스트가 폴링을 끝내는 데 쓴다.
  MusicStatus status;

  @override
  Future<MusicGeneration> musicOf(String cardId) async =>
      status == MusicStatus.none
      ? MusicGeneration.none(cardId)
      : MusicGeneration(cardId: cardId, status: status, trackCount: 1);

  @override
  Future<MusicGeneration> requestMusic(String cardId) =>
      _inner.requestMusic(cardId);

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) => _inner.byDateRange(from: from, to: to);

  @override
  Future<RecordCard> create(NewRecordCard card) => _inner.create(card);

  @override
  Future<RecordCard> update(EditRecordCard card) => _inner.update(card);

  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) => _inner.delete(cardId);
}
