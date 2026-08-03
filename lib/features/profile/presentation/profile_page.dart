import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 프로필 탭 (S22, 본인) — 아직 뼈대다.
///
/// 여기 들어올 것: 컬러 밴드 헤더 + 아바타 아우라, 대표 기록 대시보드(3열),
/// 컬러 컬렉션 2축, 피드 3열 그리드, 팔로워·팔로잉(S18)·편집(S22.1)·설정(S22.2) 진입.
///
/// 헤더는 러닝 색 위에 텍스트를 얹으므로 **스크림 레이어가 필수**다(디자인 시스템 §1-4).
///
/// ⚠️ 번호를 헷갈리기 쉽다 — **S22가 본인, S20이 타인**이다.
/// 타인 프로필(S20)은 **레이아웃이 같고 액션만 다르다**(미팔로우 시 지인공개 마스킹).
/// 같은 위젯을 조건부로 재사용한다.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          AppStrings.tabProfile,
          style: AppTypography.h1.copyWith(
            color: context.appColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
