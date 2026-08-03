import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 기록 탭 (S21) — 아직 뼈대다.
///
/// 여기 들어올 것: 주간 바차트(최근 7일) + 월 캘린더 + 날짜별 기록 목록.
/// 상세는 별도 화면이 아니라 `S16.5`(구간별 상세 비교)를 재사용한다.
/// 날짜별 상태 3종을 모두 처리한다 — 다회(리스트) / 단일(상세 직행) / 빈 상태.
///
/// ⚠️ **잔디도, 색 모자이크 캘린더도 아니다.**
/// 월 전체를 칠하면 러닝하지 않은 날이 결손으로 읽혀 잔디의 죄책감 문제를 답습한다
/// (디자인 시스템 v1.1 §5-5). **러닝한 날에만 컬러 점을 찍고**, 주간 바차트의
/// 막대 색은 그날 획득한 러닝 컬러다.
class RecordPage extends StatelessWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          AppStrings.tabRecord,
          style: AppTypography.h1.copyWith(
            color: context.appColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
