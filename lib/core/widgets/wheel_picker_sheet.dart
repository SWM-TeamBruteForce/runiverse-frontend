import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 휠 한 칸.
class WheelColumn {
  const WheelColumn({
    required this.unit,
    required this.values,
    required this.initial,
    this.valuesFor,
  });

  /// 휠 아래 붙는 단위. `년` `cm` 처럼 짧게.
  final String unit;

  /// 고를 수 있는 값. [valuesFor]가 있으면 첫 화면에만 쓰인다.
  final List<int> values;

  /// 처음 가운데 놓일 값. 목록에 없으면 첫 값으로 떨어진다.
  final int initial;

  /// 다른 칸에 따라 목록이 달라질 때 쓴다.
  ///
  /// 예: 일(日)은 년·월에 따라 28~31로 달라진다. 이게 없으면 2월 31일을
  /// 만들 수 있고, 그걸 나중에 몰래 보정하면 사용자가 고른 값과 저장된 값이 어긋난다.
  final List<int> Function(List<int> picked)? valuesFor;
}

/// 휠 바텀시트를 띄우고 고른 값들을 돌려준다. 취소하면 `null`.
///
/// ## 디자인 시스템에 없는 컴포넌트다
///
/// v1 컴포넌트 목록에 휠 피커가 없다. §7-1에 따라 억지로 다른 컴포넌트를 끼우지 않고
/// **시각 규칙만 이식**했다 — 색·라운드·간격·타이포는 전부 토큰이고,
/// 항목 높이는 `size.touch.default`(44)를 그대로 쓴다.
///
/// ## 왜 키보드 대신 휠인가
///
/// 숫자를 치게 하면 잘못된 값을 만들 수 있고(2월 31일, 키 700cm) 키보드가 화면 절반을
/// 가린다. 휠은 **만들 수 없는 값이 아예 없다.** 검증이 필요 없어진다.
Future<List<int>?> showWheelPickerSheet(
  BuildContext context, {
  required String title,
  required List<WheelColumn> columns,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    isScrollControlled: true,
    builder: (context) => _WheelSheet(title: title, columns: columns),
  );
}

class _WheelSheet extends StatefulWidget {
  const _WheelSheet({required this.title, required this.columns});

  final String title;
  final List<WheelColumn> columns;

  @override
  State<_WheelSheet> createState() => _WheelSheetState();
}

class _WheelSheetState extends State<_WheelSheet> {
  /// 항목 하나의 높이. 44px 미만이면 굴리다 엉뚱한 값에 멈춘다.
  static const _itemExtent = AppSizes.touchDefault;

  /// 보이는 항목 수. 가운데 1 + 위아래 1.5씩.
  static const _visible = 4;

  late final List<FixedExtentScrollController> _controllers;
  late List<List<int>> _values;
  late List<int> _picked;

  @override
  void initState() {
    super.initState();
    _values = widget.columns.map((c) => c.values).toList();
    _picked = [
      for (var i = 0; i < widget.columns.length; i++)
        _values[i].contains(widget.columns[i].initial)
            ? widget.columns[i].initial
            : _values[i].first,
    ];
    _controllers = [
      for (var i = 0; i < widget.columns.length; i++)
        FixedExtentScrollController(
          initialItem: _values[i].indexOf(_picked[i]),
        ),
    ];
    _resolveDependents();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// 다른 칸에 기대는 목록을 다시 만든다.
  ///
  /// 고른 값이 새 목록에 없으면(2월로 옮겼는데 31일을 고르고 있었다면)
  /// 마지막 값으로 끌어내린다. **말없이 바꾸지 않고 휠을 실제로 움직여서** 보여준다.
  void _resolveDependents() {
    for (var i = 0; i < widget.columns.length; i++) {
      final build = widget.columns[i].valuesFor;
      if (build == null) continue;

      final next = build(_picked);
      if (listEquals(next, _values[i])) continue;
      _values[i] = next;

      if (!next.contains(_picked[i])) {
        _picked[i] = next.last;
        // 프레임 중에 컨트롤러를 만지면 스크롤이 어긋난다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controllers[i].hasClients) return;
          _controllers[i].animateToItem(
            next.length - 1,
            duration: AppMotion.base,
            curve: AppMotion.easeStandard,
          );
        });
      }
    }
  }

  void _onChanged(int column, int index) {
    setState(() {
      _picked[column] = _values[column][index];
      _resolveDependents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space3,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            Text(
              widget.title,
              style: AppTypography.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space4),

            SizedBox(
              height: _itemExtent * _visible,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 가운데 띠 — 어느 값이 골라진 것인지 짚어준다.
                  IgnorePointer(
                    child: Container(
                      height: _itemExtent,
                      decoration: BoxDecoration(
                        color: colors.primaryMuted,
                        borderRadius: AppRadius.sm,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < widget.columns.length; i++)
                        Expanded(child: _column(i)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space5),

            AppButton(
              label: '확인',
              onPressed: () => Navigator.of(context).pop(_picked),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(int i) {
    final colors = context.appColors;
    final values = _values[i];
    final selected = _picked[i];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          // 위아래 끝을 흐린다. 안 하면 맨 끝 항목이 반쯤 잘린 채로 캡션과 붙어
          // 렌더가 깨진 것처럼 보인다. 흐려지면 '더 있다'는 신호가 된다.
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, 0.24, 0.76, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListWheelScrollView.useDelegate(
              controller: _controllers[i],
              itemExtent: _itemExtent,
              physics: const FixedExtentScrollPhysics(),
              diameterRatio: 2.2,
              onSelectedItemChanged: (index) => _onChanged(i, index),
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: values.length,
                builder: (context, index) {
                  final value = values[index];
                  final isOn = value == selected;
                  return Center(
                    child: Text(
                      '$value',
                      style: AppTypography.bodyLg.copyWith(
                        color: isOn ? colors.textPrimary : colors.textTertiary,
                        fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          widget.columns[i].unit,
          style: AppTypography.micro.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
