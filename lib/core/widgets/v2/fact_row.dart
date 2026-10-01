import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 수치 몇 개를 한 줄에 나란히 놓는 패널 — 시안 `158:3121`.
///
/// 매칭 완료와 매칭 실패가 같은 모양으로 `시작 시간 · 목표거리 · 시작까지`를
/// 보여준다.
///
/// ## 칸을 균등하게 나눈다
///
/// 값의 길이가 제각각이다(`19:00` `5 km` `01:19:00`). 내용에 맞춰 폭을 주면
/// 1초마다 바뀌는 카운트다운 때문에 **다른 칸까지 좌우로 흔들린다.**
class FactRowV2 extends StatelessWidget {
  const FactRowV2({required this.facts, super.key});

  /// 왼쪽부터의 순서 그대로 놓인다.
  final List<Fact> facts;

  /// 시안 `158:3121`의 높이.
  static const _height = 98.0;

  /// 뒤가 비쳐 보이는 정도.
  static const _blur = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ClipRRect(
      borderRadius: AppRadius.card,
      // ⚠️ **블러는 `ClipRRect` 안에 둔다.** 밖에 두면 화면 전체가 흐려진다 —
      // `BackdropFilter`는 자기 뒤가 아니라 잘려나가기 전 전체를 먹는다.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: Container(
          height: _height,
          color: colors.bgGlass,
          child: Row(
            children: [
              for (final fact in facts)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fact.label,
                        // ⚠️ **시안은 `#575757`인데 쓰지 않았다.**
                        //
                        // 이 패널은 매칭 완료 카드의 **밝은 파란 면** 위에
                        // 앉는다. 시안 렌더에서 재면 대비가 `1.54:1`이고
                        // 우리 화면에서는 `1.14:1`이다 — WCAG AA 는 4.5:1,
                        // 큰 글자도 3:1 이다. **라벨이 안 보인다.**
                        //
                        // 값만 보이고 그것이 무엇인지 모르면 패널이 뜻을
                        // 잃어서, 읽히는 쪽을 골랐다. 디자인 확인이 필요하다.
                        style: AppTypographyV2.body11.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        fact.value,
                        style: AppTypographyV2.body02.copyWith(
                          color: colors.textStrong,
                          // ⚠️ `시작까지`가 1초마다 갈린다. 안 주면 자릿수가
                          // 흔들려 세 칸이 같이 춤춘다(CLAUDE.md).
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 라벨 하나와 값 하나.
class Fact {
  const Fact({required this.label, required this.value});

  final String label;

  /// **모르면 지어내지 않는다.** 부르는 쪽이 `-`를 넣는다.
  final String value;
}
