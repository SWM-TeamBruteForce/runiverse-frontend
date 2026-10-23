import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';

/// 새 디자인의 카드 면.
///
/// 시안이 카드를 전부 같은 모양으로 그린다 — `bgSurface` 에 반경 20
/// (`158:3425` `158:3435` `158:3462` `158:3470` `158:3477`). 화면마다 다시
/// 적으면 한 군데만 고쳐지고 나머지가 남는다.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({required this.child, this.padding, super.key});

  final Widget child;

  /// 없으면 여백 없이 [child]만 담는다. 지도처럼 면을 꽉 채우는 것에 쓴다.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColorsV2.bgSurface,
        borderRadius: AppRadius.card,
      ),
      child: body,
    );
  }
}
