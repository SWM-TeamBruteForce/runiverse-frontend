import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/record/presentation/split_line_chart.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 러닝 결과 (S16) — Figma `46:69`에 `47:65`(S16.5)를 이어 붙인 한 화면.
///
/// ## 두 곳에서 열린다
///
/// 러닝을 막 끝냈을 때(S15 → S16)와 기록 탭에서 지난 기록을 눌렀을 때다.
/// **화면은 어느 쪽인지 모른다** — [RunDetail] 하나만 받는다. 그래서 세션
/// provider를 읽지 않고, `record`가 `session/presentation`에 기대지도 않는다.
///
/// ## 정본과 다른 점: 두 화면을 합쳤다
///
/// 정본은 S16 안의 `구간별 상세 비교 ›` 카드로 별도 화면(S16.5)에 들어가게
/// 했다. 그 진입 카드를 없애고 **스크롤로 내려가면 나오도록** 합쳤다.
///
/// ## Figma에 있는데 여기 없는 것
///
/// - **획득 컬러 카드** — 색 생성 규칙이 아직 없다
/// - **팔로우 버튼** — API가 아직 없다
///
/// ## 파티원 비교
///
/// 매칭 러닝이면 지표 아래에 **파티원 비교 카드**가 붙고, 구간 표 위의 러너
/// 칩으로 **한 명**을 골라 겹쳐 본다(정본은 두 명 — 첫 버전은 한 명). 고르면
/// 표의 격차가 내 평균 대비에서 **그 사람 대비**로 바뀌고 두 페이스 그래프에
/// 그 사람의 선이 겹친다. 색은 러닝 화면의 레인과 같다 — 서버가 준 순서다.
/// - **구간별 경사** — `GeoPoint.altitude`가 "경사를 내는 데 쓰지 않는다"고
///   못 박고 있다. GPS 고도 오차가 ±10~20m다
class RunResultView extends StatefulWidget {
  const RunResultView({required this.detail, super.key});

  final RunDetail detail;

  @override
  State<RunResultView> createState() => _RunResultViewState();
}

class _RunResultViewState extends State<RunResultView> {
  /// 겹쳐 보는 파티원. `null`이면 나만 본다.
  String? _compareTo;

  RunDetail get detail => widget.detail;

  /// 내 색 — **파랑 고정이다.**
  ///
  /// `lane(0)`은 브랜드 파랑(`#227DFF`)이고 `colors.primary`와 **같은 값**이다.
  /// 어느 방에서 몇 번째에 서든 나는 늘 이 색이라, 화면을 옮겨 다녀도 내 것을
  /// 찾는 눈이 흔들리지 않는다.
  static final _myColor = RunPaletteV2.lane(0);

  /// 그 사람의 색. **나를 뺀 나머지가** 주황·분홍·초록을 명단 순서로 나눠 갖는다.
  ///
  /// 방은 최대 4명이라 나 하나와 상대 셋이 팔레트 4색에 꼭 맞는다.
  ///
  /// ⚠️ **명단 자리 번호를 그대로 쓰면 안 된다.** 명단에 내가 둘째로 들어 있으면
  /// 첫 자리의 상대가 `lane(0)`, 즉 **내 파랑을 가져간다.** 서버가 주는 명단
  /// 순서는 내가 몇 번째에 설지 정해 주지 않는다.
  Color _colorOf(String userId) {
    if (userId == _myUserId) return _myColor;

    final others = [
      for (final player in detail.players)
        if (!player.isMe) player.userId,
    ];
    final index = others.indexOf(userId);
    // ⚠️ 못 찾아도 **0으로 떨어뜨리지 않는다** — 0은 내 파랑이라 남이 나로
    // 보인다. 팔레트 끝 색을 준다. 명단에 없으면 그릴 이름도 없어 실제로는
    // 오지 않는 길이다.
    return RunPaletteV2.lane(index < 0 ? 3 : index + 1);
  }

  /// 명단 속의 나. 서버가 나를 빠뜨리면 `null`이고, 그래도 내 색은 파랑이다.
  String? get _myUserId =>
      detail.players.where((player) => player.isMe).firstOrNull?.userId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final compare = _compareTo;
    final compareSamples = compare == null
        ? null
        : detail.chartSamplesOf(compare);
    final compareColor = compare == null ? null : _colorOf(compare);
    // 색 칩에 적을 이름. 명단에 없으면 칩도 띄우지 않는다 — 이름 없는 색은
    // 설명이 되지 못한다.
    final compareName = compare == null
        ? null
        : detail.players
              .where((p) => p.userId == compare)
              .firstOrNull
              ?.nickname;
    // 칩과 같은 색이라야 겹쳐 그린 두 선에서 내 것이 갈린다.
    final myColor = _myColor;
    // 테이블은 1km, 그래프는 50m다. 같은 러닝을 두 배율로 본다 — 표는
    // "몇 번째 킬로를 몇 분에 뛰었나"를, 그래프는 "어디서 흔들렸나"를 답한다.
    final splits = detail.tableSplits;
    final samples = detail.chartSamples;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  AppSpacing.space5,
                  AppSpacing.space4,
                  AppSpacing.space8,
                ),
                children: [
                  _RouteCard(detail: detail),
                  const SizedBox(height: AppSpacing.space6),
                  _MetricGrid(detail: detail),
                  const SizedBox(height: AppSpacing.space6),

                  if (detail.party.isNotEmpty) ...[
                    _PartyCard(detail: detail, colorOf: _colorOf),
                    const SizedBox(height: AppSpacing.space6),
                  ],

                  if (splits.isEmpty)
                    const _NoSplits()
                  else ...[
                    if (detail.party.any((p) => p.hasRecord)) ...[
                      _RunnerChips(
                        detail: detail,
                        selected: compare,
                        myColor: myColor,
                        colorOf: _colorOf,
                        onSelect: (userId) =>
                            setState(() => _compareTo = userId),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                    ],
                    // 1km 그래프가 먼저다. **러닝 전체의 모양을 먼저 보여
                    // 준다** — 몇 번째 킬로가 무너졌는지는 이쪽이 답한다.
                    SplitLineChart(
                      title: AppStrings.runResultPaceChart,
                      unit: AppStrings.profilePacePerKm,
                      values: [
                        for (final s in splits)
                          (s.pace ?? Duration.zero).inSeconds.toDouble(),
                      ],
                      labels: _labels(splits, detail.distanceKm),
                      format: (v) =>
                          PaceCalculator.format(Duration(seconds: v.round())),
                      color: myColor,
                      hint: AppStrings.runResultChartHint,
                      secondary: compare == null
                          ? null
                          : [
                              for (final s in detail.tableSplitsOf(compare))
                                (s.pace ?? Duration.zero).inSeconds.toDouble(),
                            ],
                      secondaryColor: compareColor,
                      // ⚠️ 페이스는 작을수록 빠르므로 그대로 올리면 솟은
                      // 봉우리가 "느렸던 구간"이 되어 거꾸로 읽힌다. **두 페이스
                      // 그래프가 같은 방향이어야 한다** — 위아래로 붙어 있는데
                      // 축이 반대면 같은 러닝이 서로 다른 얘기를 한다.
                      inverted: true,
                      // 구간이 몇 개뿐이라 점을 찍어 **멈추는 자리**를 보인다.
                      // 아래 50m 상세는 점이 수십 개라 찍지 않는다.
                      showPoints: true,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    _SplitTable(
                      detail: detail,
                      compareTo: compare == null
                          ? null
                          : detail.tableSplitsOf(compare),
                    ),
                    const SizedBox(height: AppSpacing.space4),

                    // ⚠️ **1km 묶음을 다 보여 준 뒤에 50m로 내려간다.**
                    // 그래프-표-그래프 순서가 배율 순서이기도 하다: 1km
                    // 그래프와 1km 표가 같은 단위끼리 붙고, 그 아래부터
                    // 50m 상세가 시작된다.
                    SplitLineChart(
                      title: AppStrings.runResultPaceDetailChart,
                      unit: AppStrings.runResultPaceDetailUnit,
                      values: [
                        for (final s in samples)
                          (s.pace ?? Duration.zero).inSeconds.toDouble(),
                      ],
                      labels: _sampleLabels(samples),
                      axisTicks: _sampleTicks(samples),
                      format: (v) =>
                          PaceCalculator.format(Duration(seconds: v.round())),
                      color: myColor,
                      hint: AppStrings.runResultChartHint,
                      secondary: compareSamples == null
                          ? null
                          : [
                              for (final s in compareSamples)
                                (s.pace ?? Duration.zero).inSeconds.toDouble(),
                            ],
                      secondaryColor: compareColor,
                      inverted: true,
                      filled: true,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    // ⚠️ 값이 없으면 그래프 대신 **이유를 그 자리에 적는다.**
                    // 빈 그래프는 "0spm으로 뛰었다"로 읽히고, 카드를 통째로
                    // 감추면 케이던스가 원래 없는 화면인 줄 알게 된다.
                    if (detail.hasCadence) ...[
                      SplitLineChart(
                        // ⚠️ **50m 표본이다.** 제목이 배율을 밝혀야 위쪽
                        // 1km 그래프와 헷갈리지 않는다.
                        title: AppStrings.runResultCadenceDetailChart,
                        unit: AppStrings.runResultCadenceDetailUnit,
                        // ⚠️ **모르는 구간은 `null`로 넘긴다.** 0으로 바꾸면
                        // 선이 바닥까지 떨어져 "그때 멈췄다"로 읽힌다 —
                        // 걸음 표본이 모자란 것과 안 뛴 것은 다른 말이다.
                        values: [
                          for (final s in samples) s.cadenceSpm?.toDouble(),
                        ],
                        labels: _sampleLabels(samples),
                        axisTicks: _sampleTicks(samples),
                        format: (v) => v.round().toString(),
                        color: myColor,
                        hint: AppStrings.runResultChartHint,
                        // 페이스 그래프 둘과 **같은 사람**을 겹친다. 칩 하나가
                        // 세 그래프를 함께 바꾸지 않으면, 같은 화면에서 비교
                        // 기준이 그래프마다 달라진다.
                        secondary: compareSamples == null
                            ? null
                            : [
                                for (final s in compareSamples)
                                  s.cadenceSpm?.toDouble(),
                              ],
                        secondaryColor: compareColor,
                        legend: compareName == null
                            ? null
                            : ChartLegend(
                                mine: AppStrings.runPartyMe,
                                other: compareName,
                              ),
                        // 50m 상세라 페이스 상세와 같은 모양으로 둔다.
                        // ⚠️ 뒤집지 않는다 — 케이던스는 클수록 좋은 값이다.
                        filled: true,
                        // 서버 실측값이라 꼬리표를 달지 않는다.
                      ),
                    ] else ...[
                      const _NoCadence(),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1km 그래프의 x축 라벨. 마지막 자투리 구간만 실제로 닿은 지점을 적는다.
  static List<String> _labels(List<SplitBucket> splits, double totalKm) => [
    for (final split in splits)
      split.isPartialOf(SplitAggregator.tableMeters)
          ? AppStrings.runResultPartialLabel(totalKm)
          : AppStrings.runResultSplitLabel(split.index),
  ];

  /// 50m 표본의 x축·툴팁 라벨. **닿은 지점의 누적 거리**다.
  ///
  /// 구간 번호(`1km` `2km`)를 쓰지 않는다 — 50m면 5km에 100개가 되어 번호가
  /// 아무 뜻도 갖지 못한다. 어디쯤이었는지가 읽고 싶은 값이다.
  static List<String> _sampleLabels(List<SplitBucket> samples) => [
    for (final sample in samples)
      AppStrings.runResultSampleLabel(sample.endDistanceMeters / 1000),
  ];

  /// 50m 그래프의 x축에 **라벨을 찍을 자리.**
  ///
  /// ## ⚠️ 점 개수로 솎으면 어중간한 거리가 나온다
  ///
  /// 3km는 점이 60개다. 전체의 1/5마다 찍으면 첫 점부터 열둘씩 세어
  /// `0.05 · 0.65 · 1.25 · 1.85 · 2.45km`가 된다. 겹치지 않게 줄이려던
  /// 것이지만, **읽는 사람이 쓰는 자는 거리**지 점 번호가 아니다.
  ///
  /// ## 간격은 러닝 길이를 보고 고른다
  ///
  /// `5km 미만은 0.5km`처럼 하나로 못 박으면 4.9km 러닝에서 라벨이 아홉
  /// 개가 되어 12px 글자끼리 포갠다. 자리가 [_maxTicks]개를 넘지 않는
  /// **가장 촘촘한 간격**을 고른다.
  static List<int> _sampleTicks(List<SplitBucket> samples) {
    if (samples.isEmpty) return const [];

    final totalMeters = samples.last.endDistanceMeters;
    var step = _tickStepsMeters.last;
    for (final candidate in _tickStepsMeters) {
      if (totalMeters ~/ candidate <= _maxTicks) {
        step = candidate;
        break;
      }
    }

    return [
      for (var i = 0; i < samples.length; i++)
        // 서버 경계가 10m라 50m 표본의 끝은 늘 50의 배수다 — 딱 떨어지는
        // 거리에 닿은 점이 반드시 있다.
        if (samples[i].endDistanceMeters % step == 0) i,
    ];
  }

  /// 라벨 사이로 둘 수 있는 거리 — **촘촘한 것부터** 본다.
  ///
  /// ⚠️ **0.5km부터 시작하면 짧은 러닝에 찍을 자리가 없다.** 220m를 뛰면
  /// 0.5km에 닿은 점이 하나도 없어 총 거리 하나만 남는다(에뮬레이터에서
  /// 그렇게 나왔다). 50m 표본의 끝은 늘 50의 배수라 여기도 50부터 둔다.
  static const _tickStepsMeters = [50, 100, 200, 500, 1000, 2000, 5000, 10000];

  /// x축에 둘 거리 라벨의 최대 개수.
  ///
  /// 그림 영역이 270px 남짓이라 여섯 개부터는 `2.5km`가 옆 라벨에 닿는다.
  /// 마지막 점은 이 수에 들어가지 않는다 — 총 거리는 늘 따로 찍힌다.
  static const _maxTicks = 5;
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: AppStrings.runResultBack,
          constraints: const BoxConstraints(
            minWidth: AppSizes.touchDefault,
            minHeight: AppSizes.touchDefault,
          ),
          icon: AppIcon(
            AppIcons.left,
            size: AppSpacing.space6,
            color: colors.textPrimary,
          ),
        ),
        Text(
          AppStrings.runResultTitle,
          style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

/// 달린 길. Figma 프레임 이름이 `route (내 경로만)`인 그대로다 — 파티원 경로는
/// 어떤 화면으로도 내보내지 않는다.
class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.detail});

  final RunDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: SizedBox(
        height: 238,
        child: Stack(
          children: [
            Positioned.fill(child: RunMapView.route(track: detail.track)),
            Positioned(
              left: AppSpacing.space3,
              top: AppSpacing.space3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: AppRadius.full,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space3,
                    vertical: AppSpacing.space1,
                  ),
                  child: Text(
                    '${detail.distanceKm.toStringAsFixed(2)}'
                    '${AppStrings.runSummaryUnitKm} · '
                    '${_elapsedText(detail.duration)}',
                    style: AppTypographyV2.body15.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시간 · 거리 · 페이스 · 케이던스 2×2. Figma `46:96`.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.detail});

  final RunDetail detail;

  @override
  Widget build(BuildContext context) {
    final cadence = detail.cadenceSpm;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: AppStrings.runResultTime,
                value: _elapsedText(detail.duration),
              ),
            ),
            Expanded(
              child: _Metric(
                label: AppStrings.runResultDistance,
                value:
                    '${detail.distanceKm.toStringAsFixed(2)}'
                    '${AppStrings.runSummaryUnitKm}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space3),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: AppStrings.runResultPace,
                value: PaceCalculator.format(detail.averagePace),
              ),
            ),
            Expanded(
              child: _Metric(
                label: AppStrings.runResultCadence,
                // 케이던스는 못 낼 때가 흔하다. 0으로 때우지 않는다.
                value: cadence == null ? '--' : '$cadence',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypographyV2.heading03.copyWith(
            color: colors.textPrimary,
            // ⚠️ **v1 `metricMd` 가 품고 있던 것이다.** `heading03` 에는
            // 없어서 토큰을 갈아끼우며 조용히 빠졌다. 지금 화면은 멈춘
            // 수치라 티가 안 나지만, 러닝 수치에는 이것을 붙인다(CLAUDE.md).
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: AppTypographyV2.body15.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// 파티원 비교 카드(S16). 색 점 · 이름 · 시간 · 평균 페이스.
///
/// 정본의 `[팔로우]`는 API가 없어 뺐다. 순위 숫자는 두지 않는다 — 순서도
/// 서버가 준 순서 그대로다.
class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.detail, required this.colorOf});

  final RunDetail detail;
  final Color Function(String userId) colorOf;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.runResultPartyTitle,
              style: AppTypographyV2.body18.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            for (final player in detail.party)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: AppSpacing.space3,
                      height: AppSpacing.space3,
                      decoration: BoxDecoration(
                        color: colorOf(player.userId),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Text(
                        player.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypographyV2.body07.copyWith(
                          color: player.isDeleted
                              ? colors.textTertiary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                    if (player.hasRecord) ...[
                      Text(
                        _elapsedText(player.duration!),
                        style: AppTypographyV2.body07.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      Text(
                        PaceCalculator.format(player.averagePace),
                        style: AppTypographyV2.body07.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ] else
                      Text(
                        // ⚠️ 아직 뛰는 중인 것과 기록이 없는 것은 다르다.
                        // 앞쪽은 곧 생기고, 뒤쪽은 영영 없다.
                        player.isRunning
                            ? AppStrings.runResultStillRunning
                            : AppStrings.runResultNoRecord,
                        style: AppTypographyV2.body15.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 러너 칩(S16.5). 나는 고정, 파티원 중 **한 명**을 골라 겹쳐 본다.
class _RunnerChips extends StatelessWidget {
  const _RunnerChips({
    required this.detail,
    required this.selected,
    required this.myColor,
    required this.colorOf,
    required this.onSelect,
  });

  final RunDetail detail;
  final String? selected;

  /// 내 칩의 색. 명단에 내가 없어도 그려야 해서 따로 받는다.
  final Color myColor;

  final Color Function(String userId) colorOf;
  final void Function(String? userId) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    Widget chip({
      required String label,
      required Color dot,
      required bool active,
      VoidCallback? onTap,
    }) => InkWell(
      onTap: onTap,
      borderRadius: AppRadius.full,
      child: Container(
        height: AppSizes.touchDefault - AppSpacing.space2,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
        decoration: BoxDecoration(
          color: active ? colors.primaryMuted : colors.bgSurface,
          border: Border.all(
            color: active ? colors.primary : colors.borderDefault,
          ),
          borderRadius: AppRadius.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSpacing.space2,
              height: AppSpacing.space2,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              label,
              style: AppTypographyV2.body15.copyWith(
                color: onTap == null && !active
                    ? colors.textDisabled
                    : colors.textPrimary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            chip(label: AppStrings.runPartyMe, dot: myColor, active: true),
            for (final player in detail.party)
              chip(
                label: player.nickname,
                dot: colorOf(player.userId),
                active: player.userId == selected,
                // 기록 없는 사람은 겹칠 선이 없다. 누르지 못하게 둔다.
                onTap: player.hasRecord
                    ? () => onSelect(
                        player.userId == selected ? null : player.userId,
                      )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          AppStrings.runResultCompareHint,
          style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// 구간 리스트. 정본의 `경사`는 빼고 `구간 · 페이스(격차) · 소모`만 남았다.
class _SplitTable extends StatefulWidget {
  const _SplitTable({required this.detail, this.compareTo});

  final RunDetail detail;

  /// 겹쳐 보는 파티원의 1km 묶음. `null`이거나 비어 있으면 **차이를 그리지
  /// 않는다** — 고르기만 하고 상대 구간이 없는 경우가 뒤쪽이다.
  ///
  /// 내 것보다 짧을 수 있다. 먼저 끝난 사람은 뒤 구간이 없고, **그 줄도
  /// 비운다** — 잴 상대가 없는데 내 평균으로 바꿔 재면 한 표 안에서 자가
  /// 둘이 된다.
  final List<SplitBucket>? compareTo;

  /// 이만큼 넘어가면 접는다. 10km(10구간)에서도 차트 둘이 한 화면에 들어오게.
  static const collapsedCount = 5;

  @override
  State<_SplitTable> createState() => _SplitTableState();
}

class _SplitTableState extends State<_SplitTable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final all = widget.detail.tableSplits;
    final collapsed = !_expanded && all.length > _SplitTable.collapsedCount;
    final shown = collapsed ? all.take(_SplitTable.collapsedCount) : all;
    // 차이는 **파티원을 골랐을 때만** 적는다.
    //
    // 혼자 볼 때도 내 평균 대비로 적을 수 있지만, 구간 옆에 붙은 숫자를
    // 평균과의 거리로 읽는 사람이 없었다 — 첫 구간부터 값이 붙어 있어
    // **직전 구간과의 차이로 읽힌다.** 읽히는 뜻이 틀리면 없느니만 못하다.
    //
    // ⚠️ 빈 목록은 고르지 않은 것과 같다. 상대가 방에는 있는데 서버가 구간을
    // 하나도 안 준 경우가 있고, 그때는 잴 것이 하나도 없다.
    final comparing = widget.compareTo?.isNotEmpty ?? false;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        children: [
          _SplitHead(
            basis: comparing ? AppStrings.runResultGapBaseParty : null,
          ),
          for (final (i, split) in shown.indexed)
            _SplitRow(
              split: split,
              totalKm: widget.detail.distanceKm,
              // 같은 경계라 같은 자리가 같은 구간이다.
              //
              // ⚠️ **먼저 끝난 사람의 빈 구간은 비운다.** 내 평균으로
              // 돌아가면 머리줄은 `파티원 대비`인데 그 줄만 다른 자로 잰
              // 값이 된다. 색까지 뒤집힌다 — 상대보다 빨랐던 구간이 내
              // 평균보다는 느려 빨갛게 뜨는 일이 **같은 표 안에서** 일어난다.
              base: !comparing
                  ? null
                  : i >= widget.compareTo!.length
                  ? null
                  : widget.compareTo![i].pace,
            ),
          if (collapsed)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: SizedBox(
                height: AppSizes.touchDefault,
                child: Center(
                  child: Text(
                    AppStrings.runResultMoreSplits,
                    style: AppTypographyV2.body15.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitHead extends StatelessWidget {
  const _SplitHead({this.basis});

  /// 차이 값의 기준. `null`이면 그릴 차이가 없다는 뜻이라 적지 않는다.
  final String? basis;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final style = AppTypographyV2.body18.copyWith(color: colors.textTertiary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space3,
        AppSpacing.space4,
        AppSpacing.space2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(AppStrings.runResultSplitColumn, style: style),
          ),
          Expanded(
            child: Row(
              children: [
                Text(AppStrings.runResultPace, style: style),
                if (basis case final text?) ...[
                  // 아래 줄의 페이스와 차이도 이만큼 떨어져 있다.
                  const SizedBox(width: AppSpacing.space2),
                  Flexible(
                    child: Text(
                      text,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(AppStrings.runResultBurnedColumn, style: style),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.split, required this.totalKm, this.base});

  final SplitBucket split;
  final double totalKm;

  /// 차이를 재는 기준. `null`이면 **차이를 그리지 않는다** — 혼자 보는
  /// 중이거나 이 구간을 잴 것이 없다는 뜻이다.
  final Duration? base;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final burned = split.caloriesKcal;
    // 순위가 아니라 거리다 — 음수면 내가 빨랐다.
    final pace = split.pace;
    final gap = (base == null || pace == null) ? null : pace - base!;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              split.isPartialOf(SplitAggregator.tableMeters)
                  ? AppStrings.runResultPartialLabel(totalKm)
                  : AppStrings.runResultSplitLabel(split.index),
              style: AppTypographyV2.body07.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  PaceCalculator.format(split.pace),
                  style: AppTypographyV2.body07.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (gap != null) ...[
                  const SizedBox(width: AppSpacing.space2),
                  Text(
                    _gapText(gap),
                    // 기준보다 빨랐으면 success, 느렸으면 error.
                    //
                    // ⚠️ **0은 어느 쪽도 아니다.** `isNegative`만 보면 0이
                    // 느린 쪽으로 빨갛게 칠해진다 — 평균과 같은 구간을
                    // 나무라는 셈이다.
                    style: AppTypographyV2.body18.copyWith(
                      color: switch (gap.inSeconds) {
                        < 0 => colors.success,
                        > 0 => colors.error,
                        _ => colors.textTertiary,
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$burned${AppStrings.runResultUnitKcal}',
            style: AppTypographyV2.body15.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _gapText(Duration gap) {
    final seconds = gap.inSeconds;
    // 부호를 반드시 붙인다 — 색만으로 빠르고 느림을 알리지 않는다(색맹 대응,
    // `implementation-notes` 3-5). 0에는 부호가 없다.
    if (seconds == 0) return '0s';
    return seconds > 0 ? '+${seconds}s' : '${seconds}s';
  }
}

/// 케이던스를 하나도 못 구했을 때 그래프 자리를 지키는 카드.
///
/// 그래프와 같은 껍데기를 쓴다. 자리가 비면 화면이 위로 붙어 버려서
/// "케이던스라는 게 있었나" 싶어진다.
class _NoCadence extends StatelessWidget {
  const _NoCadence();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.runResultCadenceDetailChart,
                  style: AppTypographyV2.body18.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.space1),
                Text(
                  AppStrings.runResultCadenceDetailUnit,
                  style: AppTypographyV2.body18.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              AppStrings.runResultNoCadence,
              style: AppTypographyV2.body18.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSplits extends StatelessWidget {
  const _NoSplits();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
      child: Text(
        AppStrings.runResultNoSplits,
        textAlign: TextAlign.center,
        style: AppTypographyV2.body07.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

String _elapsedText(Duration elapsed) {
  final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
