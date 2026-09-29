import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

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
                    image: NetworkImage(image),
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
          Text(name, style: AppTypographyV2.body11.copyWith(color: accent)),
        ],
      ],
    );
  }
}
