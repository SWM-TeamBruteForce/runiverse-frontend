// `.characters`가 여기서 온다 — `widgets.dart`가 `characters`를 재수출한다.
// 그 패키지를 직접 적으면 `depend_on_referenced_packages`가 뜬다.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';

PickedImage _image(String path) =>
    PickedImage.validated(path: path, sizeBytes: 1024);

RecordCard _card({required int id}) => RecordCard(
  id: 'card-$id',
  runningRecordId: 11,
  startedAt: DateTime(2026, 11, 2, 7),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: '여행에서 뛰었다',
  photos: const [RecordCardPhoto(id: 'img-70', url: 'https://x/a.jpg')],
  route: _route,
  distanceMeters: 3050,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);

RunRecord _record({required int id}) => RunRecord(
  id: id,
  runningRoomId: id + 900,
  startedAt: DateTime(2026, 9, 2, 18),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

const _route = RouteArt(
  strokes: [
    [RoutePoint(0, 0), RoutePoint(1, 1)],
  ],
  aspect: 1,
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  CardDraftController notifier([String? cardId]) =>
      container.read(cardDraftProvider(cardId).notifier);

  CardDraft draft([String? cardId]) => container.read(cardDraftProvider(cardId));

  test('새 초안은 비어 있다', () {
    expect(draft().record, isNull);
    expect(draft().activity, isNull);
    expect(draft().reviewText, '');
  });

  test('⚠️ 기록을 바꾸면 앞 기록의 경로가 남지 않는다', () {
    // 남으면 11번 기록의 선 아트가 12번 카드에 그려진다.
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    expect(draft().route, isNotNull);

    notifier().pickRecord(_record(id: 12));

    expect(draft().record?.id, 12);
    expect(draft().route, isNull);
  });

  test('⚠️ 같은 기록을 다시 골라도 경로를 버리지 않는다', () {
    // 목록을 다시 눌렀다고 받아 온 경로를 버리면 조회가 또 나간다.
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    notifier().pickRecord(_record(id: 11));

    expect(draft().route, isNotNull);
  });

  test('⚠️ 회고가 1000자를 넘으면 잘라서 담는다', () {
    // 통째로 담으면 저장에서 거절당하고 쓴 글을 잃는다.
    notifier().setReview('가' * 1200);

    expect(draft().reviewText.length, CardDraft.reviewMaxLength);
  });

  test('⚠️ 보던 화면이 떠나도 초안은 남는다', () {
    // 작성이 세 화면이라 라우트를 넘나든다. autoDispose면 사진 화면으로 가는
    // 순간 작성 1의 구독이 끊겨 쓴 것이 사라진다(implementation-notes 5-1).
    final sub = container.listen(cardDraftProvider(null), (_, _) {});
    notifier().setReview('쓴 글');
    sub.close();

    expect(draft().reviewText, '쓴 글');
  });

  test('⚠️ 새 카드와 수정 중인 카드는 섞이지 않는다', () {
    // 작성 중에 남의 카드 수정으로 들어가도 안 섞여야 한다(설계 7절).
    notifier().setReview('새 카드');
    notifier('card-7').setReview('7번 수정');

    expect(draft().reviewText, '새 카드');
    expect(draft('card-7').reviewText, '7번 수정');
  });

  test('컨트롤러가 자기 카드 번호를 안다', () {
    expect(notifier().cardId, isNull);
    expect(notifier('card-7').cardId, 'card-7');
  });

  test('유형을 고른다', () {
    notifier().setActivity(RecordCardActivity.travel);

    expect(draft().activity, RecordCardActivity.travel);
  });

  test('clear가 비운다', () {
    notifier().pickRecord(_record(id: 11));
    notifier().setActivity(RecordCardActivity.race);
    notifier().setReview('대회');

    notifier().clear();

    expect(draft().record, isNull);
    expect(draft().activity, isNull);
    expect(draft().reviewText, '');
  });

  test('경로를 null로 되돌릴 수 있다 — 못 받았을 때다', () {
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    notifier().setRoute(null);

    expect(draft().route, isNull);
  });

  group('사진', () {
    test('고른 순서대로 쌓인다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));

      expect(draft().photos.map((p) => (p as PickedPhoto).image.path), [
        '/tmp/a.jpg',
        '/tmp/b.jpg',
      ]);
    });

    test('여섯 번째 사진은 들어가지 않는다', () {
      for (var i = 0; i < 6; i++) {
        notifier().addPhoto(_image('/tmp/$i.jpg'));
      }

      expect(draft().photos, hasLength(5));
      expect((draft().photos.last as PickedPhoto).image.path, '/tmp/4.jpg');
    });

    test('지우면 그 자리만 빠지고 순서가 남는다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));
      notifier().addPhoto(_image('/tmp/c.jpg'));

      notifier().removePhotoAt(1);

      expect(draft().photos.map((p) => (p as PickedPhoto).image.path), [
        '/tmp/a.jpg',
        '/tmp/c.jpg',
      ]);
    });

    test('캡션은 그 장에만 붙는다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));

      notifier().setCaption(1, '바람이 좋았다');

      expect(draft().photos[0].caption, '');
      expect(draft().photos[1].caption, '바람이 좋았다');
    });

    test('캡션은 100자에서 자른다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));

      notifier().setCaption(0, 'ㄱ' * 200);

      expect(draft().photos.first.caption.characters.length, 100);
    });

    test('⚠️ 이모지로 100자를 채워도 반쪽이 남지 않는다', () {
      // 입력 칸은 grapheme으로, 자르기를 code unit으로 세면 경계에서 서로게이트
      // 쌍이 갈라져 서버로 U+FFFD가 간다. 회고에서 미뤄 둔 결함이고
      // (`docs/notes/2026-11-18-record-card-compose-deferred.md` 1번) 여기서는
      // 되풀이하지 않는다.
      notifier().addPhoto(_image('/tmp/a.jpg'));

      notifier().setCaption(0, '🏃' * 200);

      final caption = draft().photos.first.caption;
      expect(caption.characters.length, 100);
      expect(caption.codeUnits.length, 200); // 서로게이트 쌍 100개
      expect(caption.runes, isNot(contains(0xFFFD)));
    });

    test('밀어 둔 위치는 그 장에만 남는다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));

      notifier().setPhotoAlign(1, alignX: -0.5);

      expect((draft().photos[0] as PickedPhoto).alignX, 0);
      expect((draft().photos[1] as PickedPhoto).alignX, -0.5);
      expect((draft().photos[1] as PickedPhoto).alignY, 0);
    });

    test('한 축만 주면 다른 축은 그대로다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().setPhotoAlign(0, alignX: -0.5, alignY: 0.3);

      notifier().setPhotoAlign(0, alignX: 0.8);

      expect((draft().photos.first as PickedPhoto).alignX, 0.8);
      expect((draft().photos.first as PickedPhoto).alignY, 0.3);
    });

    test('⚠️ 없는 자리를 건드려도 던지지 않는다', () {
      // 화면이 지운 뒤 늦게 온 콜백이다. 던지면 작성 중에 앱이 죽는다.
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().removePhotoAt(0);

      expect(() => notifier().setCaption(0, '가'), returnsNormally);
      expect(() => notifier().setPhotoAlign(3, alignX: 1), returnsNormally);
      expect(() => notifier().removePhotoAt(9), returnsNormally);
      expect(draft().photos, isEmpty);
    });

    test('대표로 고른 사진이 맨 앞으로 오고 나머지 순서는 그대로다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));
      notifier().addPhoto(_image('/tmp/c.jpg'));
      notifier().addPhoto(_image('/tmp/d.jpg'));

      notifier().makeCover(2);

      // 달력 칸과 프로필 그리드가 첫 사진을 얼굴로 쓴다.
      expect(draft().photos.map((p) => (p as PickedPhoto).image.path), [
        '/tmp/c.jpg',
        '/tmp/a.jpg',
        '/tmp/b.jpg',
        '/tmp/d.jpg',
      ]);
    });

    test('⚠️ 캡션과 밀어 둔 위치가 사진을 따라간다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));
      notifier().setCaption(1, '두 번째의 한마디');
      notifier().setPhotoAlign(1, alignX: 0.25);

      notifier().makeCover(1);

      // 사진만 옮기고 캡션을 두고 가면 **남의 한마디가 붙는다.**
      expect(draft().photos.first.caption, '두 번째의 한마디');
      expect((draft().photos.first as PickedPhoto).alignX, 0.25);
      expect(draft().photos.last.caption, '');
    });

    test('⚠️ 이미 맨 앞이면 상태를 다시 쓰지 않는다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().addPhoto(_image('/tmp/b.jpg'));
      final before = draft();

      notifier().makeCover(0);

      // 같은 값을 새로 쓰면 듣고 있는 화면이 헛 그려진다.
      expect(draft(), same(before));
    });

    test('⚠️ 없는 자리를 대표로 지정해도 던지지 않는다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));

      notifier().makeCover(-1);
      notifier().makeCover(5);

      expect(draft().photos, hasLength(1));
    });

    test('clear가 사진까지 비운다', () {
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier().setVisibility(RecordCardVisibility.public);

      notifier().clear();

      expect(draft().photos, isEmpty);
      expect(draft().visibility, RecordCardVisibility.friends);
    });
  });

  group('카드를 고치러 들어왔을 때', () {
    test('seed가 카드 값을 뿌린다', () {
      notifier('card-7').seed(_card(id: 7));

      expect(draft('card-7').reviewText, '여행에서 뛰었다');
      expect(draft('card-7').photos, hasLength(1));
      expect(draft('card-7').editing?.id, 'card-7');
    });

    // ⚠️ Review Focus 1
    test('⚠️ 수정 초안과 새 카드 초안이 섞이지 않는다', () {
      // 섞이면 남의 카드 글이 새 카드에 붙는다(설계 7절).
      notifier('card-7').seed(_card(id: 7));

      notifier().setReview('새로 쓰는 글');

      expect(draft('card-7').reviewText, '여행에서 뛰었다');
      expect(draft().reviewText, '새로 쓰는 글');
      expect(draft().photos, isEmpty);
      expect(draft().editing, isNull);
    });

    test('⚠️ 이미 고친 초안에는 다시 뿌리지 않는다', () {
      // 화면이 매번 부른다. 안 막으면 사진 화면에서 돌아올 때마다 **고친
      // 것이 되돌아간다.**
      notifier('card-7').seed(_card(id: 7));
      notifier('card-7').setReview('고친 글');

      notifier('card-7').seed(_card(id: 7));

      expect(draft('card-7').reviewText, '고친 글');
    });

    test('뜬 직후에는 버릴지 묻지 않는다', () {
      notifier('card-7').seed(_card(id: 7));

      expect(draft('card-7').isDirty, isFalse);
    });

    test('한 글자만 고쳐도 묻는다', () {
      notifier('card-7').seed(_card(id: 7));

      notifier('card-7').setReview('고친 글');

      expect(draft('card-7').isDirty, isTrue);
    });

    test('clear가 고치던 카드까지 비운다', () {
      notifier('card-7').seed(_card(id: 7));

      notifier('card-7').clear();

      expect(draft('card-7').editing, isNull);
      expect(draft('card-7').photos, isEmpty);
    });
  });

  group('공개범위와 음악', () {
    test('고른 공개범위가 남는다', () {
      notifier().setVisibility(RecordCardVisibility.private);

      expect(draft().visibility, RecordCardVisibility.private);
    });

    test('⚠️ 카드별로 따로 둔다', () {
      // 새 카드를 쓰던 중에 남의 카드 수정으로 들어가도 섞이지 않아야 한다.
      notifier().addPhoto(_image('/tmp/a.jpg'));
      notifier('card-7').setVisibility(RecordCardVisibility.public);

      expect(draft().visibility, RecordCardVisibility.friends);
      expect(draft('card-7').photos, isEmpty);
    });
  });
}
