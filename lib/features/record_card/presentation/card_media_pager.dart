import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
import 'package:runiverse/features/record_card/presentation/route_art_view.dart';

/// 카드의 포토북 — **경로 한 장 + 사진 N장**이 9:16으로 선다.
///
/// ## ⚠️ 음악이 끝나면 다음 장이다
///
/// 사용자가 "사진별 음악이 끝나면 자동으로 다음 사진"으로 정했다. 그런데
/// **소리는 아직 없다** — 오디오 패키지가 `pubspec`에 없고 음악 엔드포인트도
/// 명세에 없다.
///
/// 그래서 넘기는 조건을 **"그 장의 길이만큼 지나면"**으로 둔다. 길이는 백엔드
/// AI 계약이 정한 값이다 — 기본 음악 [MusicGeneration.baseDuration], 사진
/// 음악 [MusicGeneration.photoDuration].
/// 음악이 붙으면 **길이의 출처만** 실제 재생 끝 신호로 바꾼다. 이 위젯의 구조는
/// 그대로다.
///
/// ## ⚠️ 마지막 장에서 멈춘다
///
/// 처음으로 되돌아가지 않는다. 포토북은 끝이 있는 것이고, 돌아가면 사용자가
/// 몇 바퀴째인지 알 수 없다.
class CardMediaPager extends StatefulWidget {
  const CardMediaPager({
    required this.card,
    required this.playing,
    required this.onPlayingChanged,
    required this.onPageChanged,
    super.key,
  });

  /// 양옆 이웃이 살짝 보이는 정도. 시안이 가운데 장을 크게 두고 좌우를
  /// 조금씩 드러낸다.
  static const _viewport = 0.82;

  /// 사진이 화면 높이의 몇 할까지 먹을 수 있나.
  ///
  /// ⚠️ **디자인 확인이 필요한 값이다.** 사진·캡션·회고가 한 화면에 들어오는
  /// 것이 기준이다.
  static const _maxHeightShare = 0.52;

  final RecordCard card;

  /// 지금 넘어가고 있나.
  ///
  /// ## ⚠️ 바깥이 든다
  ///
  /// 음악 줄도 같은 것을 가리켜야 한다(`MusicStrip`). 각자 들면 줄은 `재생`
  /// 인데 책은 넘어가거나, 사진을 탭해 멈췄는데 줄은 여전히 `멈춤`이다.
  final bool playing;

  /// 사진을 탭했다. **스스로 바꾸지 않는다** — 든 사람이 바꾼다.
  final ValueChanged<bool> onPlayingChanged;

  /// 몇 번째 장으로 갔나. 음악 줄이 **더 넘어갈 데가 있는지** 알아야 한다 —
  /// 마지막 장에서는 `멈춤`이 거짓이 된다.
  final ValueChanged<int> onPageChanged;

  @override
  State<CardMediaPager> createState() => _CardMediaPagerState();
}

class _CardMediaPagerState extends State<CardMediaPager> {
  late final PageController _controller = PageController(
    viewportFraction: CardMediaPager._viewport,
  );

  Timer? _advance;
  var _page = 0;

  /// 경로 한 장 + 사진들.
  int get _count => widget.card.photos.length + 1;

  /// 페이저 높이. 9:16으로 낸 값과 화면의 [CardMediaPager._maxHeightShare]
  /// 중 **작은 쪽**이다.
  double _pagerHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ideal = size.width * CardMediaPager._viewport * 16 / 9;
    return math.min(ideal, size.height * CardMediaPager._maxHeightShare);
  }

  /// 사진 아래 글자 자리에 설 말.
  ///
  /// ⚠️ **자리는 하나다.** 경로 장에서는 회고, 사진 장에서는 **회고 대신**
  /// 그 사진의 캡션이 선다. 둘을 같이 두면 사진을 넘기는 내내 회고가 아래에
  /// 따라다닌다.
  String? get _below => _page == 0
      ? widget.card.reviewText
      : widget.card.photos[_page - 1].caption;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// ⚠️ **바깥이 멈추면 타이머를 다시 건다.** 안 걸면 줄의 `멈춤`이 상태만
  /// 바꾸고 책은 그대로 넘어간다.
  @override
  void didUpdateWidget(CardMediaPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _schedule();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 지금 장의 길이만큼 뒤에 다음 장으로 넘어가게 건다.
  ///
  /// ⚠️ **남은 시간을 들고 있지 않는다.** 멈췄다 이어갈 때 그 장을 처음부터
  /// 다시 센다 — 남은 시간을 들고 있으면 막대가 가리키는 것과 어긋난다.
  void _schedule() {
    _advance?.cancel();
    if (!widget.playing) return;
    // 마지막 장이면 걸지 않는다. 사진이 없으면 첫 장이 곧 마지막이다.
    if (_page >= _count - 1) return;

    _advance = Timer(
      // ⚠️ **길이의 출처는 음악 계약이다.** 여기에 상수를 두면 계약이 바뀔 때
      // 화면과 도메인이 갈라진다.
      MusicGeneration.durationOfPage(_page),
      () {
        if (!mounted) return;
        _controller.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      },
    );
  }

  void _onPage(int page) {
    setState(() => _page = page);
    widget.onPageChanged(page);
    // 손으로 밀었든 타이머가 넘겼든, 새 장은 처음부터 센다.
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.card.photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          // ⚠️ **한 장이 9:16이지 페이저가 9:16이 아니다.** 한 장의 폭은
          // 뷰포트 폭의 [_viewport]배라 높이는 `폭 × _viewport × 16/9`다.
          // 그 값이 화면 높이의 [_maxHeightShare]를 넘으면 잘라 낸다 —
          // 사진은 `BoxFit.cover`라 잘려도 가운데가 남는다.
          height: _pagerHeight(context),
          child: Semantics(
            label: AppStrings.recordCardPageSemantics(
              index: _page + 1,
              count: _count,
            ),
            container: true,
            child: GestureDetector(
              // 탭하면 멈추고 다시 탭하면 이어간다.
              onTap: () => widget.onPlayingChanged(!widget.playing),
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPage,
                itemCount: _count,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space1,
                  ),
                  child: _Page(
                    card: widget.card,
                    photo: index == 0 ? null : photos[index - 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        // ⚠️ **사진과 글 사이다.** 장이 하나뿐이면 두지 않는다 — 점 하나는
        // 알려 주는 것이 없다.
        if (_count > 1) ...[
          CardPageDots(count: _count, current: _page),
          const SizedBox(height: AppSpacing.space3),
        ],
        if (_below != null && _below!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Text(
              _below!,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body12.copyWith(
                color: context.appColorsV2.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 한 장. 첫 장은 경로 선 아트, 나머지는 사진이다.
class _Page extends StatelessWidget {
  const _Page({required this.card, required this.photo});

  final RecordCard card;

  /// `null`이면 경로 장이다.
  final RecordCardPhoto? photo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: ColoredBox(
        color: colors.bgSurface,
        child: photo == null
            ? RouteArtView(
                art: card.route,
                color: colors.primary,
                strokeWidth: 3,
                padding: AppSpacing.space6,
              )
            : Image(
                image: cardThumbnail(context, photo!.url),
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => RouteArtView(
                  art: card.route,
                  color: colors.primary,
                  strokeWidth: 3,
                  padding: AppSpacing.space6,
                ),
              ),
      ),
    );
  }
}

/// 몇 번째 장인지 알리는 작은 흰 점들. **사진과 글 사이**에 선다.
class CardPageDots extends StatelessWidget {
  const CardPageDots({required this.count, required this.current, super.key});

  /// 점 지름.
  static const _size = 6.0;

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.space1),
          Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              // 지금 장만 또렷하고 나머지는 흐리다.
              color: index == current ? colors.textStrong : colors.textDisabled,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}
