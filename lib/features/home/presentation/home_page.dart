import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 홈 (S05) — 아직 뼈대다.
///
/// 상단 히어로 + 하단 카드 스택(다가오는 대회 · 최근 매칭 러닝) 구조다.
/// **히어로가 매칭 상태를 전담**하고 4상태(기본 · 대기 · 확정 · 실패)로 갈린다.
/// 그래서 홈에서는 글로벌 스티키 배너를 띄우지 않는다 — 중복이다.
///
/// 매칭 상태는 **홈이 소유하지 않는다.** 스티키 배너와 같은 provider를
/// 구독해야 하고, 탭을 옮겨도 살아있어야 한다(`docs/implementation-notes.md` §5-1).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          AppStrings.tabHome,
          style: AppTypography.h1.copyWith(
            color: context.appColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
