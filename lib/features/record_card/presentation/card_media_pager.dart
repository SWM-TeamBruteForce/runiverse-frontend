import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
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
/// AI 계약이 정한 값이다 — 기본 음악 [baseDuration], 사진 음악 [photoDuration].
/// 음악이 붙으면 **길이의 출처만** 실제 재생 끝 신호로 바꾼다. 이 위젯의 구조는
/// 그대로다.
///
/// ## ⚠️ 마지막 장에서 멈춘다
///
/// 처음으로 되돌아가지 않는다. 포토북은 끝이 있는 것이고, 돌아가면 사용자가
/// 몇 바퀴째인지 알 수 없다.
class CardMediaPager extends StatefulWidget {
  const CardMediaPager({required this.card, super.key});

  /// 기본 음악 길이. 경로 장이 이만큼 선다.
  static const baseDuration = Duration(seconds: 30);

  /// 사진 음악 길이. 사진 장이 이만큼 선다.
  static const photoDuration = Duration(seconds: 10);

  /// 양옆 이웃이 살짝 보이는 정도. 시안이 가운데 장을 크게 두고 좌우를
  /// 조금씩 드러낸다.
  static const _viewport = 0.82;

  final RecordCard card;

  @override
  State<CardMediaPager> createState() => _CardMediaPagerState();
}

class _CardMediaPagerState extends State<CardMediaPager> {
  late final PageController _controller = PageController(
    viewportFraction: CardMediaPager._viewport,
  );

  Timer? _advance;
  var _page = 0;
  var _playing = true;

  /// 경로 한 장 + 사진들.
  int get _count => widget.card.photos.length + 1;

  @override
  void initState() {
    super.initState();
    _schedule();
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
    if (!_playing) return;
    // 마지막 장이면 걸지 않는다. 사진이 없으면 첫 장이 곧 마지막이다.
    if (_page >= _count - 1) return;

    _advance = Timer(
      _page == 0 ? CardMediaPager.baseDuration : CardMediaPager.photoDuration,
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
    // 손으로 밀었든 타이머가 넘겼든, 새 장은 처음부터 센다.
    _schedule();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.card.photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          // ⚠️ **한 장이 9:16이지 페이저가 9:16이 아니다.** 한 장의 폭은
          // 뷰포트 폭의 [_viewport]배라, 페이저의 높이는 `폭 × _viewport × 16/9`
          // 이고 비는 `9 / (16 × _viewport)`다. 그냥 `9/16`을 쓰면 페이저가
          // 화면보다 길어져 아래가 전부 밀려난다.
          aspectRatio: 9 / (16 * CardMediaPager._viewport),
          child: Semantics(
            label: AppStrings.recordCardPageSemantics(
              index: _page + 1,
              count: _count,
            ),
            container: true,
            child: GestureDetector(
              // 탭하면 멈추고 다시 탭하면 이어간다.
              onTap: _toggle,
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
        if (_page > 0 && photos[_page - 1].caption != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Text(
              photos[_page - 1].caption!,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body12.copyWith(
                color: context.appColorsV2.textSecondary,
              ),
            ),
          ),
        // ⚠️ 장이 하나뿐이면 막대를 두지 않는다. 늘 꽉 찬 막대 하나는
        // 알려 주는 것이 없다.
        if (_count > 1) ...[
          const SizedBox(height: AppSpacing.space3),
          CardPageBars(count: _count, current: _page),
        ],
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

/// 장마다 하나씩 차는 막대.
///
/// ⚠️ **점이 아니라 막대다.** 장마다 길이가 있는 재생이라, 점은 "몇 번째인가"만
/// 말하고 **얼마나 남았는지**를 못 알린다.
class CardPageBars extends StatelessWidget {
  const CardPageBars({required this.count, required this.current, super.key});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Row(
        children: [
          for (var index = 0; index < count; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.space1),
            Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: index <= current
                      ? colors.primary
                      : colors.borderDefault,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
