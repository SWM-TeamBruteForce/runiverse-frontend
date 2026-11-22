import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/card_thumbnail_maker.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_save_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 저장 — 자르고, 썸네일을 만들고, 카드를 만든다 (설계 6-3 · 6-4).
void main() {
  group('자르기', () {
    test('⚠️ 사진마다 9:16으로 자른다', () async {
      // 설계 6-3: "서버에 올리는 원본은 크롭 결과다." 비율이 틀리면 AI가 보는
      // 그림과 사람이 본 그림이 달라진다.
      final world = _World();

      final card = await world.save(photos: 2);

      expect(card, isNotNull);
      expect(world.cropper.calls, hasLength(2));
      expect(
        world.cropper.calls.map((c) => c.aspectRatio),
        everyElement(closeTo(CardPhotoDraft.aspectRatio, 1e-9)),
      );
    });

    test('⚠️ 올리는 것은 자른 결과다 — 원본이 아니다', () async {
      final world = _World();

      final card = await world.save(photos: 1);

      expect(card!.photos.single.url, _Cropper.croppedPath);
      expect(card.photos.single.url, isNot('/tmp/p0.jpg'));
    });

    test('⚠️ 밀어 둔 위치가 자르기로 넘어간다', () async {
      // 여기가 끊기면 사용자가 맞춘 자리와 다른 데가 잘린다.
      final world = _World();

      await world.save(aligns: [(x: -0.4, y: 0.25)]);

      expect(world.cropper.calls.single.alignX, -0.4);
      expect(world.cropper.calls.single.alignY, 0.25);
    });

    test('캡션이 사진마다 따라간다', () async {
      final world = _World();

      final card = await world.save(captions: ['첫째', '']);

      expect(card!.photos[0].caption, '첫째');
      // 안 쓴 캡션은 빈 문자열이 아니라 `null`이다 — 서버도 nullable이다.
      expect(card.photos[1].caption, isNull);
    });

    test('⚠️ 대표로 올린 사진이 카드의 첫 사진으로 저장된다', () async {
      // 달력 칸과 프로필 그리드가 **첫 사진**을 얼굴로 쓴다. 순서가 저장까지
      // 가지 않으면 작성 2에서 고른 대표가 아무 뜻이 없다.
      final world = _World();
      world.fill(captions: ['첫째', '둘째', '셋째']);
      world.container.read(cardDraftProvider(null).notifier).makeCover(2);

      final card = await world.controller.save();

      expect(card!.photos.map((p) => p.caption), ['셋째', '첫째', '둘째']);
    });

    test('⚠️ 성공하면 자른 파일을 치우지 않는다', () async {
      // 올릴 엔드포인트가 없어 **그 경로가 유일한 사본**이다. 치우면 카드가
      // 가리키는 사진이 사라져, 상세에서 세 장이 전부 선 아트로 보인다.
      // 프로필 커버는 그 사이에 S3 업로드가 있어 치워도 됐다 — 카드는 없다.
      final world = _World();

      final card = await world.save(photos: 2);

      expect(world.cropper.discarded, isEmpty);
      expect(
        card!.photos.map((p) => p.url),
        everyElement(isNot(isIn(world.cropper.discarded))),
        reason: '카드가 가리키는 파일을 지우면 안 된다',
      );
    });

    test('⚠️ 실패하면 이미 자른 것을 치운다 — 아무도 가리키지 않는 파일이다', () async {
      // 둘째 장에서 자르기가 엎어진다. 첫째 장은 이미 잘려 임시 폴더에 있고,
      // 카드가 안 만들어졌으니 들고 있을 이유가 없다.
      final world = _World(cropper: _Cropper.failsAt(1));

      final card = await world.save(photos: 2);

      expect(card, isNull);
      expect(world.cropper.discarded, hasLength(1));
    });

    test('썸네일이 터져도 저장은 성공하고 파일을 지키다', () async {
      // 썸네일은 없어도 되는 것이다 — 실패 경로가 아니다.
      final world = _World(thumbnails: _Thumbnails.broken());

      final card = await world.save(photos: 2);

      expect(card, isNotNull);
      expect(world.cropper.discarded, isEmpty);
    });
  });

  group('썸네일', () {
    test('긴 변 320px로 만든다', () async {
      final world = _World();

      final card = await world.save(photos: 1);

      expect(card!.photos.single.thumbnailUrl, _Thumbnails.thumbPath);
      expect(CardThumbnailMaker.longEdge, 320);
      expect(CardThumbnailMaker.shortEdge, 180);
    });

    test('⚠️ 못 만들어도 카드는 산다', () async {
      // 썸네일이 없으면 달력이 원본을 쓴다 — 느리지만 보인다. 사진 한 장
      // 때문에 카드가 아예 안 만들어지면 그게 더 나쁘다.
      final world = _World(thumbnails: _Thumbnails.failing());

      final card = await world.save(photos: 2);

      expect(card, isNotNull);
      expect(card!.photos, hasLength(2));
      expect(card.photos.first.thumbnailUrl, isNull);
    });
  });

  group('만든 카드', () {
    test('초안의 값이 그대로 들어간다', () async {
      final world = _World();

      final card = await world.save(
        activity: RecordCardActivity.race,
        visibility: RecordCardVisibility.public,
        review: '대회였다',
      );

      expect(card!.activity, RecordCardActivity.race);
      expect(card.visibility, RecordCardVisibility.public);
      expect(card.reviewText, '대회였다');
      expect(card.runningRecordId, _record().id);
      expect(card.startedAt, _record().startedAt);
      expect(card.distanceMeters, _record().distanceMeters);
    });

    test('⚠️ 경로가 없는 러닝은 빈 선 아트로 저장된다', () async {
      // 트레드밀이다. `RecordCard.route`는 null을 받지 못한다.
      final world = _World();

      final card = await world.save(route: null);

      expect(card!.route.isEmpty, isTrue);
    });

    test('성공하면 초안을 비운다', () async {
      final world = _World();

      await world.save(photos: 1, review: '좋았다');

      expect(world.draft.reviewText, '');
      expect(world.draft.photos, isEmpty);
      expect(world.draft.record, isNull);
    });

    test('Fake의 그날 목록에 들어간다', () async {
      final repository = FakeRecordCardRepository(today: _today);

      final card = await repository.create(_newCard());
      final sameDay = await repository.byDateRange(
        from: card.day,
        to: card.day,
      );

      expect(sameDay.map((c) => c.id), contains(card.id));
    });

    test('⚠️ 만든 카드의 번호가 목 데이터와 겹치지 않는다', () async {
      // 겹치면 달력이 두 장을 한 장으로 보고, 상세가 엉뚱한 것을 연다.
      final repository = FakeRecordCardRepository(today: _today);
      final existing = await repository.byDateRange(
        from: _today.subtract(const Duration(days: 30)),
        to: _today,
      );

      final a = await repository.create(_newCard());
      final b = await repository.create(_newCard());

      expect(a.id, isNot(b.id));
      expect(existing.map((c) => c.id), isNot(contains(a.id)));
      expect(existing.map((c) => c.id), isNot(contains(b.id)));
    });
  });

  group('실패', () {
    test('⚠️ 고른 파일이 사라졌으면 실패하고 쓴 글을 지킨다', () async {
      // 백그라운드에 오래 두면 OS가 임시 폴더를 비운다. 초안을 비우면 사진이
      // 아니라 **회고까지** 잃는다 — 초안은 영속화하지 않아 되돌릴 길이 없다.
      final world = _World(cropper: _Cropper.missingFile());

      final card = await world.save(photos: 1, review: '꼭 남기고 싶었다');

      expect(card, isNull);
      expect(world.state, isA<CardSaveFailed>());
      expect(world.draft.reviewText, '꼭 남기고 싶었다');
      expect(world.draft.photos, hasLength(1));
    });

    test('저장이 거절되면 왜인지 들고 있는다', () async {
      final world = _World(failWith: RecordCardFailure.network);

      final card = await world.save(photos: 1);

      expect(card, isNull);
      expect(
        (world.state as CardSaveFailed).failure,
        RecordCardFailure.network,
      );
      expect(world.draft.reviewText, isNotEmpty);
    });

    test('실패한 뒤 다시 저장할 수 있다', () async {
      // 한 번 막히고 영원히 못 누르면 쓴 것이 갇힌다.
      final world = _World(failWith: RecordCardFailure.network);
      await world.save(photos: 1);

      world.repository.failWith = null;
      final card = await world.saveAgain();

      expect(card, isNotNull);
      expect(world.state, isA<CardSaveIdle>());
    });

    test('⚠️ 저장 중에 또 누르면 카드가 하나만 생긴다', () async {
      // 느린 망에서 두 번 누르면 러닝 하나에 카드가 둘 생기고, 서버의
      // unique(running_record_id)가 뒤늦게 터진다.
      final world = _World(delay: const Duration(milliseconds: 50));
      world.fill(photos: 1);

      final first = world.controller.save();
      final second = world.controller.save();
      final cards = await Future.wait([first, second]);

      expect(world.repository.creates, 1);
      expect(cards.where((c) => c != null), hasLength(1));
    });

    test('도는 동안 상태가 Saving이다', () async {
      final world = _World(delay: const Duration(milliseconds: 50));
      world.fill(photos: 1);

      final soon = world.controller.save();
      expect(world.state, isA<CardSaveSaving>());

      await soon;
      expect(world.state, isA<CardSaveIdle>());
    });

    test('초안이 덜 찼으면 아무것도 보내지 않는다', () async {
      final world = _World();

      final card = await world.controller.save();

      expect(card, isNull);
      expect(world.repository.creates, 0);
    });
  });

  /// 수정 저장 (설계 6-6).
  group('고친 카드를 저장할 때', () {
    test('create가 아니라 update를 부른다', () async {
      final world = _EditWorld();

      await world.save();

      expect(world.repository.creates, 0);
      expect(world.repository.updates, 1);
      expect(world.repository.lastEdit!.cardId, 7);
    });

    // ⚠️ Review Focus 2
    test('⚠️ 이미 올린 사진은 다시 자르지 않는다', () async {
      // 이미 9:16으로 잘린 것을 또 자르면 그림이 좁아진다.
      final world = _EditWorld(saved: 2);

      await world.save();

      expect(world.cropper.calls, isEmpty);
      expect(world.repository.lastEdit!.photos, hasLength(2));
    });

    test('새로 고른 것만 자른다', () async {
      final world = _EditWorld(saved: 1, picked: 2);

      await world.save();

      expect(world.cropper.calls, hasLength(2));
    });

    test('⚠️ 남길 사진 전체를 보낸다', () async {
      // 바뀐 것만 보내지 않는다(사용자 결정 2026-11-19) — 서버가 차집합으로
      // 지우고, 앱은 변경을 추적하지 않는다.
      final world = _EditWorld(saved: 1, picked: 1);

      await world.save();

      final sent = world.repository.lastEdit!.photos;
      expect(sent, hasLength(2));
      expect(sent.first.savedId, 70);
      expect(sent.first.path, isNull);
      expect(sent.last.savedId, isNull);
      expect(sent.last.path, isNotNull);
    });

    // ⚠️ Review Focus 5
    test('⚠️ 사진을 전부 지워도 저장된다', () async {
      // `photos: []`가 "안 바꿈"으로 읽히면 지운 사진이 되살아난다.
      final world = _EditWorld(saved: 2);
      world.removeAllPhotos();

      final card = await world.save();

      expect(card, isNotNull);
      expect(world.repository.lastEdit!.photos, isEmpty);
    });

    test('고친 값이 그대로 실린다', () async {
      final world = _EditWorld();
      world.edit(review: '고친 글', visibility: RecordCardVisibility.private);

      await world.save();

      final sent = world.repository.lastEdit!;
      expect(sent.reviewText, '고친 글');
      expect(sent.visibility, RecordCardVisibility.private);
    });

    test('성공하면 초안을 비운다', () async {
      final world = _EditWorld();

      await world.save();

      expect(world.draft.editing, isNull);
      expect(world.draft.reviewText, '');
    });

    test('⚠️ 실패하면 고친 글을 지킨다', () async {
      final world = _EditWorld(failWith: RecordCardFailure.network);
      world.edit(review: '고친 글');

      final card = await world.save();

      expect(card, isNull);
      expect(world.draft.reviewText, '고친 글');
      expect(world.state, isA<CardSaveFailed>());
    });

    test('자른 임시 파일은 성공해도 치우지 않는다', () async {
      // 새 카드와 같은 이유다 — 카드가 그 경로를 가리킨다.
      final world = _EditWorld(picked: 1);

      await world.save();

      expect(world.cropper.discarded, isEmpty);
    });
  });
}

// ── 도움 ──────────────────────────────────────────────────────

final _today = DateTime(2026, 11, 18);

RunRecord _record() => RunRecord(
  id: 11,
  runningRoomId: 911,
  startedAt: DateTime(2026, 11, 18, 18, 54),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

NewRecordCard _newCard() => NewRecordCard(
  record: _record(),
  route: RouteArt.empty,
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '좋았다',
  photos: const [],
  musicEnabled: true,
);

const _route = RouteArt(
  strokes: [
    [RoutePoint(0, 0), RoutePoint(1, 1)],
  ],
  aspect: 1,
);

/// 저장 한 번을 돌리는 데 필요한 것 전부.
class _World {
  _World({
    _Cropper? cropper,
    _Thumbnails? thumbnails,
    Duration delay = Duration.zero,
    RecordCardFailure? failWith,
  }) : cropper = cropper ?? _Cropper(),
       thumbnails = thumbnails ?? _Thumbnails(),
       repository = _Repository(delay: delay, failWith: failWith) {
    container = ProviderContainer(
      overrides: [
        imageCropperProvider.overrideWithValue(this.cropper),
        cardThumbnailMakerProvider.overrideWithValue(this.thumbnails),
        recordCardRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // ⚠️ **먼저 듣는다.** 안 들으면 autoDispose가 아니어도 테스트가 끝날 때
    // 상태를 못 읽는 경우가 생긴다.
    addTearDown(container.listen(cardSaveProvider(null), (_, _) {}).close);
  }

  final _Cropper cropper;
  final _Thumbnails thumbnails;
  final _Repository repository;
  late final ProviderContainer container;

  CardSaveController get controller =>
      container.read(cardSaveProvider(null).notifier);

  CardSaveState get state => container.read(cardSaveProvider(null));

  CardDraft get draft => container.read(cardDraftProvider(null));

  /// 초안을 작성 1·2·3을 거친 상태로 채운다.
  void fill({
    int photos = 0,
    List<String>? captions,
    List<({double x, double y})>? aligns,
    RecordCardActivity activity = RecordCardActivity.daily,
    RecordCardVisibility visibility = RecordCardVisibility.friends,
    String review = '좋았다',
    RouteArt? route = _route,
  }) {
    final count = aligns?.length ?? captions?.length ?? photos;
    final d = container.read(cardDraftProvider(null).notifier);
    d.pickRecord(_record());
    if (route != null) d.setRoute(route);
    d.setActivity(activity);
    d.setReview(review);
    d.setVisibility(visibility);
    for (var i = 0; i < count; i++) {
      d.addPhoto(PickedImage.validated(path: '/tmp/p$i.jpg', sizeBytes: 1024));
      if (captions != null) d.setCaption(i, captions[i]);
      if (aligns != null) {
        d.setPhotoAlign(i, alignX: aligns[i].x, alignY: aligns[i].y);
      }
    }
  }

  Future<RecordCard?> save({
    int photos = 0,
    List<String>? captions,
    List<({double x, double y})>? aligns,
    RecordCardActivity activity = RecordCardActivity.daily,
    RecordCardVisibility visibility = RecordCardVisibility.friends,
    String review = '좋았다',
    RouteArt? route = _route,
  }) {
    fill(
      photos: photos,
      captions: captions,
      aligns: aligns,
      activity: activity,
      visibility: visibility,
      review: review,
      route: route,
    );
    return controller.save();
  }

  /// 실패한 뒤 **초안을 다시 채우지 않고** 또 누른다.
  Future<RecordCard?> saveAgain() => controller.save();
}

/// 자르지 않고 받은 값만 적는다. 진짜는 `dart:ui`와 플랫폼 플러그인을 써서
/// 테스트 환경에 없다.
class _Cropper implements ImageCropper {
  _Cropper._({this.failure, this.failAt});

  factory _Cropper() => _Cropper._();

  /// [index]번째 장부터 엎어진다. 그 앞의 것은 이미 잘려 있다.
  factory _Cropper.failsAt(int index) =>
      _Cropper._(failure: ProfileImageFailure.upload, failAt: index);

  /// 고른 파일이 사라졌을 때 진짜가 던지는 것과 같은 실패다
  /// (`UiImageCropper`의 `FileSystemException` 가지).
  factory _Cropper.missingFile() =>
      _Cropper._(failure: ProfileImageFailure.upload);

  static const croppedPath = '/tmp/cropped.jpg';

  final ProfileImageFailure? failure;

  /// `null`이면 언제나 [failure]대로다.
  final int? failAt;

  final calls = <({double aspectRatio, double alignX, double alignY})>[];
  final discarded = <String>[];

  @override
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
    double alignX = 0,
  }) async {
    final index = calls.length;
    calls.add((aspectRatio: aspectRatio, alignX: alignX, alignY: alignY));
    final failure = this.failure;
    if (failure != null && (failAt == null || index >= failAt!)) {
      throw ProfileImageException(failure);
    }
    // 장마다 다른 경로여야 치운 것을 셀 수 있다.
    return PickedImage.validated(
      path: index == 0 ? croppedPath : '/tmp/cropped_$index.jpg',
      sizeBytes: 512,
    );
  }

  @override
  Future<void> discard(PickedImage cropped) async {
    discarded.add(cropped.path);
  }
}

class _Thumbnails implements CardThumbnailMaker {
  _Thumbnails._({this.gives = thumbPath, this.throws = false});

  factory _Thumbnails() => _Thumbnails._();

  /// 못 만들었다 — `null`을 준다.
  factory _Thumbnails.failing() => _Thumbnails._(gives: null);

  /// 약속을 깨고 던진다. **카드가 안 만들어져야 하는 것이 아니라,
  /// 저장이 거기서 멈추지 않는지 본다.**
  factory _Thumbnails.broken() => _Thumbnails._(throws: true);

  static const thumbPath = '/tmp/thumb.jpg';

  final String? gives;
  final bool throws;

  @override
  Future<String?> make(String croppedPath) async {
    if (throws) throw StateError('썸네일 플러그인이 터졌다');
    return gives;
  }
}

class _Repository implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _Repository({this.delay = Duration.zero, this.failWith});

  final Duration delay;
  RecordCardFailure? failWith;

  var creates = 0;

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  var updates = 0;
  EditRecordCard? lastEdit;

  @override
  Future<RecordCard> update(EditRecordCard card) async {
    updates++;
    lastEdit = card;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = failWith;
    if (failure != null) throw RecordCardException(failure);
    return _edited(card);
  }

  /// 이 테스트는 지우지 않는다.
  @override
  Future<void> delete(int cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  @override
  Future<RecordCard> create(NewRecordCard card) async {
    creates++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = failWith;
    if (failure != null) throw RecordCardException(failure);
    return _built(card, id: 7000 + creates);
  }

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> musicOf(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 보지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> requestMusic(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 만들지 않는다');
}

/// `_Repository`가 만드는 카드. Fake와 같은 모양이어야 화면이 같게 그린다.
RecordCard _built(NewRecordCard card, {required int id}) => RecordCard(
  id: id,
  runningRecordId: card.record.id,
  startedAt: card.record.startedAt,
  activity: card.activity,
  visibility: card.visibility,
  reviewText: card.reviewText,
  photos: [
    for (var i = 0; i < card.photos.length; i++)
      RecordCardPhoto(
        id: id * 10 + i,
        url: card.photos[i].path,
        thumbnailUrl: card.photos[i].thumbnailPath,
        caption: card.photos[i].caption,
      ),
  ],
  route: card.route,
  distanceMeters: card.record.distanceMeters,
  duration: card.record.duration,
  averagePace: card.record.averagePace,
  runners: const [],
);

/// `_Repository`가 고친 카드를 돌려주는 모양.
RecordCard _edited(EditRecordCard card) => RecordCard(
  id: card.cardId,
  runningRecordId: 11,
  startedAt: DateTime(2026, 11, 2, 7),
  activity: card.activity,
  visibility: card.visibility,
  reviewText: card.reviewText,
  photos: [
    for (var i = 0; i < card.photos.length; i++)
      RecordCardPhoto(
        id: card.photos[i].savedId ?? 9000 + i,
        url: card.photos[i].path ?? 'https://x/$i.jpg',
        caption: card.photos[i].caption,
      ),
  ],
  route: RouteArt.empty,
  distanceMeters: 3050,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);

/// 카드를 고치는 한 판.
///
/// ⚠️ [_World]는 새 카드만 본다 — 초안을 `addPhoto`로 채워 [SavedPhoto]를
/// 만들 수 없다. 수정은 **카드에서 뿌려야** 한다.
class _EditWorld {
  _EditWorld({int saved = 0, int picked = 0, RecordCardFailure? failWith})
    : repository = _Repository(failWith: failWith) {
    container = ProviderContainer(
      overrides: [
        imageCropperProvider.overrideWithValue(cropper),
        cardThumbnailMakerProvider.overrideWithValue(_Thumbnails()),
        recordCardRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(cardSaveProvider(cardId), (_, _) {}).close);

    final d = container.read(cardDraftProvider(cardId).notifier);
    d.seed(_savedCard(photos: saved));
    for (var i = 0; i < picked; i++) {
      d.addPhoto(
        PickedImage.validated(path: '/tmp/new$i.jpg', sizeBytes: 1024),
      );
    }
  }

  static const cardId = 7;

  final cropper = _Cropper();
  final _Repository repository;
  late final ProviderContainer container;

  CardSaveState get state => container.read(cardSaveProvider(cardId));

  CardDraft get draft => container.read(cardDraftProvider(cardId));

  void edit({String? review, RecordCardVisibility? visibility}) {
    final d = container.read(cardDraftProvider(cardId).notifier);
    if (review != null) d.setReview(review);
    if (visibility != null) d.setVisibility(visibility);
  }

  void removeAllPhotos() {
    final d = container.read(cardDraftProvider(cardId).notifier);
    while (draft.photos.isNotEmpty) {
      d.removePhotoAt(0);
    }
  }

  Future<RecordCard?> save() =>
      container.read(cardSaveProvider(cardId).notifier).save();
}

RecordCard _savedCard({int photos = 0}) => RecordCard(
  id: _EditWorld.cardId,
  runningRecordId: 11,
  startedAt: DateTime(2026, 11, 2, 7),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: '여행에서 뛰었다',
  photos: [
    for (var i = 0; i < photos; i++)
      RecordCardPhoto(id: 70 + i, url: 'https://x/$i.jpg'),
  ],
  route: RouteArt.empty,
  distanceMeters: 3050,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);
