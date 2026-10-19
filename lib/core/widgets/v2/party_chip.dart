import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/profile_photo_image.dart';

/// 함께 뛰는 사람 하나 — 아바타 위, 이름 아래.
///
/// 대기방(`158:3441`)과 출발 대기실(`158:3483`)이 같은 모양을 쓴다.
/// 사진에 링을 두르고 그 아래 이름을 같은 색으로 적는다.
///
/// ## ⚠️ 이 위젯은 도메인을 모른다
///
/// `core/`는 feature의 타입을 들 수 없다. 그래서 `RoomPlayer`가 아니라
/// 이름·사진·색만 받는다. 누구를 어떤 색으로 그릴지는 **화면이 정한다** —
/// 대기방은 브랜드 색 하나로, 출발 대기실은 자리 번호별 색으로 그린다.
///
/// ## 사진이 없으면 머리글자를 쓴다
///
/// 사람 아이콘을 두면 넷이 다 같아 보인다. 머리글자는 누구인지 알려준다.
class PartyChip extends StatelessWidget {
  const PartyChip({
    required this.name,
    required this.accent,
    this.imageUrl,
    this.size = 30,
    this.showName = true,
    super.key,
  });

  final String name;

  /// 링과 이름의 색. 화면이 뜻을 정해서 넘긴다.
  final Color accent;

  final String? imageUrl;

  /// 시안의 아바타가 30이다. 3-2-1 구간처럼 크게 보여야 할 때만 올린다.
  final double size;

  final bool showName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final image = imageUrl;
    final initial = name.isEmpty ? '' : name.characters.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.bgElevated,
            borderRadius: AppRadius.full,
            border: Border.all(color: accent, width: 1.5),
            image: image == null
                ? null
                : DecorationImage(
                    image: profilePhoto(context, image, size),
                    fit: BoxFit.cover,
                  ),
          ),
          alignment: Alignment.center,
          child: image != null
              ? null
              : Text(
                  initial,
                  style: AppTypographyV2.body11.copyWith(color: accent),
                ),
        ),
        if (showName) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            name,
            // ⚠️ **닉네임은 최대 16자다.** [PartyChipRow]가 칸 폭을 정해 주므로
            // 줄이지 않으면 긴 이름이 두 줄로 내려가 칩 높이가 서로 달라진다.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypographyV2.body11.copyWith(color: accent),
          ),
        ],
      ],
    );
  }
}

/// [PartyChip] 여럿을 **아바타 중심 간격이 고르게** 늘어놓는다.
///
/// ## ⚠️ [Wrap]으로는 간격이 맞지 않는다
///
/// [PartyChip]은 아바타 아래에 이름을 붙여서 **칩 폭이 닉네임 길이를 따라간다.**
/// [Wrap]은 칩 **사이** 간격만 같게 맞추므로, 이름이 길고 짧은 사람이 섞이면
/// 아바타 중심 간격이 들쭉날쭉해진다.
///
/// 그래서 사람마다 **같은 폭의 칸**을 주고 그 안에서 가운데 정렬한다.
/// 칸 폭은 [maxChipWidth]와 `(남은 폭 − 칸 사이 간격) ÷ 인원수` 중 작은 값이다.
/// 둘 중 하나만 쓰면 한쪽이 깨진다 — 상한이 없으면 2명일 때 양쪽으로 벌어지고,
/// 상한만 쓰면 4명일 때 넘친다.
class PartyChipRow extends StatelessWidget {
  const PartyChipRow({
    required this.children,
    required this.maxChipWidth,
    super.key,
  });

  final List<PartyChip> children;

  /// 칸 폭의 상한.
  ///
  /// 이름을 보이는 자리는 넉넉히 주되 끝이 있어야 한다 — 닉네임이 최대 16자라
  /// 칸을 넓혀도 다 보이지 않고, 아바타만 멀어진다.
  /// **이름이 없는 자리에서는 아바타 지름을 넘겨** 칸과 아바타를 같게 둔다.
  final double maxChipWidth;

  /// 칸 사이 간격. 쓰는 두 화면이 같은 값이라 밖에서 정하지 않는다.
  static const _gap = AppSpacing.space4;

  @override
  Widget build(BuildContext context) {
    // 명단이 비는 순간이 있다 — 아래 `maxWidth` 셈이 음수가 된다.
    if (children.isEmpty) return const SizedBox.shrink();

    final cells = <Widget>[];
    for (final chip in children) {
      if (cells.isNotEmpty) cells.add(const SizedBox(width: _gap));
      // 남은 폭을 똑같이 나눠 가진다. 폭의 상한은 아래 [ConstrainedBox]가 쥔다.
      cells.add(Expanded(child: chip));
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              children.length * maxChipWidth + (children.length - 1) * _gap,
        ),
        child: Row(children: cells),
      ),
    );
  }
}
