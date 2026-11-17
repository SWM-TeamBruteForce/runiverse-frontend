import 'dart:math' as math;

import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 서버 없이 기록카드 탭을 세우기 위한 목.
///
/// ## ⚠️ 진짜 카드가 아니다
///
/// 3차 API 명세서의 `record-card` 엔드포인트 여섯 줄이 **본문이 비어 있어**
/// 붙일 서버가 없다. 화면이 갈라야 하는 경우가 전부 한 번씩 나오도록 **일부러**
/// 만든 값이다 — 사진 없는 카드, 다섯 장짜리, 하루에 둘인 날, 유형 셋,
/// 공개범위 셋.
///
/// 서버가 열리면 provider에서 `HttpRecordCardRepository`로 바꾼다. 이 파일은
/// 그때 테스트용으로 남는다.
///
/// ## ⚠️ 사진이 **번들 에셋 경로**다
///
/// 서버가 없어 열람 주소를 만들 수 없다. 그래서 `assets/images/...`를 그대로
/// 돌려주고, 그리는 쪽이 `assets/`로 시작하는 주소를 에셋으로 읽는다.
/// **HTTP 구현체가 붙으면 그 분기는 지운다.**
///
/// ## ⚠️ 러닝 기록 목을 건드리지 않는다
///
/// 카드가 지표·경로를 스스로 들고 있어 `FakeRunRecordRepository`에 매이지
/// 않는다. 그쪽 `_plan`을 손대면 **기록 탭의 주간·월 요약 눈검증 값이 같이
/// 바뀐다.**
class FakeRecordCardRepository implements RecordCardRepository {
  FakeRecordCardRepository({
    DateTime? today,
    this.delay = Duration.zero,
    this.failWith,
  }) : _today = today ?? DateTime.now();

  /// "오늘"을 어디로 볼 것인가. 목 데이터를 이 날 기준으로 만든다.
  final DateTime _today;

  /// 로딩 상태를 눈으로 보려고 두는 지연. 테스트에서는 0이다.
  final Duration delay;

  /// 주면 **언제나 이 실패로 던진다.** 오류 화면을 눈으로 보는 길이다.
  ///
  /// 도중에 바꿀 수 있다 — "잘 보다가 한 번 끊겼다"를 흉내내는 데 쓴다.
  RecordCardFailure? failWith;

  /// 몇 번 불렸나. 화면이 받은 달을 다시 받는지 본다.
  var calls = 0;

  /// 물어본 구간들. 무엇을 받아 왔는지 보는 데 쓴다.
  final queries = <({DateTime from, DateTime to})>[];

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;

    if (failWith != null) throw RecordCardException(failWith!);

    // ⚠️ **진짜와 같은 규칙으로 거절한다.** 가짜가 뭐든 받아 주면 화면이 구간을
    // 넓혀도 테스트가 다 통과하고, 기기에서만 400 이 난다.
    if (from.isAfter(to) ||
        to.difference(from).inDays >= RecordCardRepository.maxRangeDays) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    queries.add((from: start, to: end));

    return [
      for (final card in _all())
        if (!card.day.isBefore(start) && !card.day.isAfter(end)) card,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  /// 오늘로부터 며칠 전 · 몇 시 · 유형 · 사진 수 · 공개범위 · 거리(m) · 시간(초).
  ///
  /// ⚠️ **`daysAgo`가 46을 넘지 않게 둔다.** 두 달치를 보여 주려는 값이라, 더
  /// 멀어지면 세 번째 달이 한 장만 있는 채로 끼어든다.
  static const _plan =
      <
        ({
          int daysAgo,
          int hour,
          RecordCardActivity activity,
          int photos,
          RecordCardVisibility visibility,
          int meters,
          int seconds,
        })
      >[
        (
          daysAgo: 0,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.friends,
          meters: 5400,
          seconds: 1690,
        ),
        (
          daysAgo: 1,
          hour: 19,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 3100,
          seconds: 1120,
        ),
        (
          daysAgo: 3,
          hour: 6,
          activity: RecordCardActivity.travel,
          photos: 5,
          visibility: RecordCardVisibility.public,
          meters: 8200,
          seconds: 2640,
        ),
        (
          daysAgo: 5,
          hour: 8,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 4600,
          seconds: 1500,
        ),
        // ⚠️ 위와 같은 날이다. 하루에 두 번 뛰면 카드도 둘이다.
        (
          daysAgo: 5,
          hour: 21,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.private,
          meters: 2800,
          seconds: 960,
        ),
        (
          daysAgo: 8,
          hour: 9,
          activity: RecordCardActivity.race,
          photos: 4,
          visibility: RecordCardVisibility.public,
          meters: 10000,
          seconds: 2880,
        ),
        (
          daysAgo: 11,
          hour: 18,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.friends,
          meters: 5200,
          seconds: 1760,
        ),
        (
          daysAgo: 14,
          hour: 7,
          activity: RecordCardActivity.travel,
          photos: 3,
          visibility: RecordCardVisibility.public,
          meters: 6400,
          seconds: 2100,
        ),
        (
          daysAgo: 17,
          hour: 20,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.private,
          meters: 3700,
          seconds: 1290,
        ),
        (
          daysAgo: 19,
          hour: 6,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 5000,
          seconds: 1650,
        ),
        (
          daysAgo: 22,
          hour: 10,
          activity: RecordCardActivity.race,
          photos: 5,
          visibility: RecordCardVisibility.public,
          meters: 21097,
          seconds: 7020,
        ),
        (
          daysAgo: 25,
          hour: 19,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 4200,
          seconds: 1470,
        ),
        (
          daysAgo: 28,
          hour: 8,
          activity: RecordCardActivity.travel,
          photos: 3,
          visibility: RecordCardVisibility.friends,
          meters: 7300,
          seconds: 2460,
        ),
        (
          daysAgo: 31,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.friends,
          meters: 5600,
          seconds: 1840,
        ),
        (
          daysAgo: 34,
          hour: 21,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 3300,
          seconds: 1200,
        ),
        (
          daysAgo: 37,
          hour: 9,
          activity: RecordCardActivity.travel,
          photos: 4,
          visibility: RecordCardVisibility.public,
          meters: 9100,
          seconds: 3000,
        ),
        (
          daysAgo: 40,
          hour: 18,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 4800,
          seconds: 1620,
        ),
        (
          daysAgo: 43,
          hour: 6,
          activity: RecordCardActivity.race,
          photos: 1,
          visibility: RecordCardVisibility.public,
          meters: 10000,
          seconds: 2760,
        ),
        (
          daysAgo: 45,
          hour: 20,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 2600,
          seconds: 900,
        ),
        (
          daysAgo: 46,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 3,
          visibility: RecordCardVisibility.friends,
          meters: 6100,
          seconds: 2040,
        ),
      ];

  /// 돌려 쓰는 번들 사진. 서버가 없어 열람 주소를 만들 수 없다.
  ///
  /// ⚠️ **진짜 사진만 쓴다.** `home_*.webp`와 `onboarding_together.png`는 사진이
  /// 아니라 **앱 화면을 찍은 그림**이라, 카드 썸네일로 깔면 달력에 앱 스크린샷이
  /// 끼어 있는 것처럼 보인다. 기기에서 보고 알았다(2026-11-16).
  ///
  /// 둘뿐이라 같은 사진이 되풀이된다. 서버가 붙으면 없어질 목이라 그대로 둔다.
  static const _photoPool = [
    'assets/images/sign_in_hero.png',
    'assets/images/onboarding_record.jpg',
  ];

  static const _captions = [
    '여기서 한 번 쉬었다',
    '해 지는 게 아까워서 멈췄다',
    '바람이 딱 좋았다',
    '다리 건너기 직전',
    '끝나고 나니 다 좋았다',
  ];

  static const _reviews = [
    '오늘은 퇴근 후 성수동에서 달렸다. 처음에는 몸이 무거웠는데 어느새 발걸음이 가벼워졌다.',
    '선선한 바람 덕분에 생각보다 편안하게 달릴 수 있었다. 다음엔 조금 더 멀리 가 봐야지.',
    '중간에 힘든 구간이 있었지만 끝까지 페이스를 지켰다. 지난번보다 안정적이어서 뿌듯하다.',
    '비 온 뒤라 공기가 맑았다. 사진으로는 다 안 담기는 하늘이었다.',
    '오랜만에 먼 거리를 뛰었다. 다리는 무겁지만 기분은 가볍다.',
  ];

  static const _runners = [
    CardRunner(userId: 'u-1', nickname: '동완러너'),
    CardRunner(userId: 'u-2', nickname: '바람'),
    CardRunner(userId: 'u-3', nickname: '해질녘'),
  ];

  List<RecordCard> _all() => [
    for (var i = 0; i < _plan.length; i++) _cardAt(i, _plan[i]),
  ];

  RecordCard _cardAt(
    int index,
    ({
      int daysAgo,
      int hour,
      RecordCardActivity activity,
      int photos,
      RecordCardVisibility visibility,
      int meters,
      int seconds,
    })
    spec,
  ) {
    final day = DateTime(
      _today.year,
      _today.month,
      _today.day,
    ).subtract(Duration(days: spec.daysAgo));
    final startedAt = DateTime(day.year, day.month, day.day, spec.hour, 54);
    final duration = Duration(seconds: spec.seconds);

    return RecordCard(
      id: 1000 + index,
      runningRecordId: 2000 + index,
      startedAt: startedAt,
      activity: spec.activity,
      visibility: spec.visibility,
      reviewText: _reviews[index % _reviews.length],
      photos: [
        for (var p = 0; p < spec.photos; p++)
          RecordCardPhoto(
            id: index * 10 + p,
            url: _photoPool[(index + p) % _photoPool.length],
            // ⚠️ 사람이 쓴 말처럼 둔다. `그날의 한 장` 같은 꼬리표를 넣으면
            // 캡션이 아니라 화면이 붙인 글자로 읽힌다 — 기기에서 그렇게 보였다.
            caption: _captions[(index + p) % _captions.length],
          ),
      ],
      route: normalizeRoute(_shape(index, startedAt)),
      distanceMeters: spec.meters,
      duration: duration,
      // 1km당 평균 페이스.
      averagePace: Duration(
        seconds: (spec.seconds * 1000 / spec.meters).round(),
      ),
      runners: _runners.take(index % 4).toList(),
    );
  }

  /// 카드마다 다른 모양을 낸다. 전부 같은 선이면 달력 칸이 구별되지 않는다.
  ///
  /// ## ⚠️ 일부러 흔들어 놓는다
  ///
  /// 매끈한 원이나 8자를 그리면 **러닝 경로가 아니라 도형으로 보인다.** 길을
  /// 따라 달린 선은 꺾이고 삐뚤다. `seed`로 정해진 난수를 섞어 모양을 흐트러뜨린다
  /// — 같은 카드는 늘 같은 모양이어야 해서 시각을 섞지 않는다.
  ///
  /// 네 장에 한 번은 **두 조각**으로 끊어 일시정지를 흉내낸다.
  static List<List<GeoPoint>> _shape(int seed, DateTime at) {
    final random = math.Random(seed);
    final lobesX = 1 + seed % 3;
    final lobesY = 1 + (seed + 1) % 2;
    final points = [
      for (var i = 0; i <= 48; i++)
        GeoPoint(
          latitude:
              37.54 +
              0.008 * math.sin(i / 48 * 2 * math.pi * lobesY) +
              0.0018 * (random.nextDouble() - 0.5) +
              seed * 0.0002,
          longitude:
              127.05 +
              0.010 * math.cos(i / 48 * 2 * math.pi * lobesX) +
              0.0018 * (random.nextDouble() - 0.5),
          recordedAt: at.add(Duration(seconds: i * 30)),
        ),
    ];

    if (seed % 4 == 0) return [points.sublist(0, 20), points.sublist(26)];
    return [points];
  }
}
