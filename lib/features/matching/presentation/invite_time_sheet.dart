import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';

/// 시작 시각을 **숫자 다이얼**로 고른다.
///
/// ## ⚠️ 아날로그 시계판을 쓰지 않는다
///
/// `showTimePicker`의 기본은 바늘이 달린 시계판이다. 초대 러닝은 **분 단위
/// 자유 입력**이라 그 위에서 `19:37`을 맞추는 것이 손으로 어렵고, 범위 밖을
/// 고르면 되돌려 주는 수밖에 없다. 숫자 휠은 **고를 수 있는 값만 담아** 애초에
/// 범위 밖이 없다.
///
/// ## ⚠️ 범위가 휠 안에 들어간다
///
/// 시 휠은 `from.hour`~`to.hour`만, 분 휠은 **고른 시에 따라 다시 세운다** —
/// 바닥 시각이면 `from.minute`부터, 천장 시각이면 `to.minute`까지다. 그래서
/// 돌려서 나온 값은 늘 보낼 수 있는 값이다.
Future<DateTime?> showInviteTimeSheet(
  BuildContext context, {
  required DateTime from,
  required DateTime to,
  DateTime? selected,
}) => showModalBottomSheet<DateTime>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (_) => _InviteTimeSheet(from: from, to: to, selected: selected),
);

class _InviteTimeSheet extends StatefulWidget {
  const _InviteTimeSheet({required this.from, required this.to, this.selected});

  final DateTime from;
  final DateTime to;
  final DateTime? selected;

  @override
  State<_InviteTimeSheet> createState() => _InviteTimeSheetState();
}

class _InviteTimeSheetState extends State<_InviteTimeSheet> {
  late int _hour;
  late int _minute;

  late final FixedExtentScrollController _hourWheel;
  FixedExtentScrollController? _minuteWheel;

  /// 한 칸 높이. 44 미만이면 손가락이 빗나간다.
  static const _itemExtent = 44.0;

  /// 휠 높이 — 가운데 한 칸과 위아래 한 칸씩.
  static const _wheelHeight = _itemExtent * 3;

  @override
  void initState() {
    super.initState();
    final start = _clamp(widget.selected ?? widget.from);
    _hour = start.hour;
    _minute = start.minute;
    _hourWheel = FixedExtentScrollController(
      initialItem: _hours.indexOf(_hour),
    );
    _minuteWheel = FixedExtentScrollController(
      initialItem: _minutes.indexOf(_minute),
    );
  }

  @override
  void dispose() {
    _hourWheel.dispose();
    _minuteWheel?.dispose();
    super.dispose();
  }

  /// 범위 안으로 끌어다 둔다. 들고 있던 값이 범위 밖일 수 있다 — 화면을 열어
  /// 둔 사이에 시간이 흘렀으면 바닥이 올라간다.
  DateTime _clamp(DateTime at) {
    if (at.isBefore(widget.from)) return widget.from;
    if (at.isAfter(widget.to)) return widget.to;
    return at;
  }

  List<int> get _hours => [
    for (var h = widget.from.hour; h <= widget.to.hour; h++) h,
  ];

  /// 고른 시에서 고를 수 있는 분.
  ///
  /// ⚠️ **바닥·천장 시각에서는 잘린다.** 전부 0~59로 두면 `19:05`처럼 보낼 수
  /// 없는 값을 고를 수 있게 되고, 서버가 `INVITE_START_AT_OUT_OF_RANGE`로
  /// 거절한다.
  List<int> get _minutes {
    final first = _hour == widget.from.hour ? widget.from.minute : 0;
    final last = _hour == widget.to.hour ? widget.to.minute : 59;
    return [for (var m = first; m <= last; m++) m];
  }

  DateTime get _picked => DateTime(
    widget.from.year,
    widget.from.month,
    widget.from.day,
    _hour,
    _minute,
  );

  void _onHour(int index) {
    setState(() {
      _hour = _hours[index];
      // 시를 바꾸면 분 선택지가 달라진다. 밖으로 나간 값을 끌어다 둔다.
      final minutes = _minutes;
      if (!minutes.contains(_minute)) {
        _minute = _minute < minutes.first ? minutes.first : minutes.last;
      }
      // 휠도 새로 세운다 — 같은 컨트롤러를 두면 잘린 목록에서 엉뚱한 칸을
      // 가리킨다.
      _minuteWheel?.dispose();
      _minuteWheel = FixedExtentScrollController(
        initialItem: minutes.indexOf(_minute),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

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
              AppStrings.inviteRegisterWhen,
              style: AppTypographyV2.body05.copyWith(color: colors.textStrong),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              AppStrings.inviteRegisterWindow(widget.from, widget.to),
              style: AppTypographyV2.body12.copyWith(
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            SizedBox(
              height: _wheelHeight,
              child: Stack(
                children: [
                  // 가운데 칸을 밝혀 지금 고른 값을 드러낸다.
                  Center(
                    child: Container(
                      height: _itemExtent,
                      decoration: BoxDecoration(
                        color: colors.bgSurface,
                        borderRadius: AppRadius.md,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('invite-hour-wheel'),
                          controller: _hourWheel,
                          values: _hours,
                          selected: _hour,
                          onSelected: _onHour,
                        ),
                      ),
                      Text(
                        ':',
                        style: AppTypographyV2.body02.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      Expanded(
                        child: _Wheel(
                          key: ValueKey('invite-minute-wheel-$_hour'),
                          controller: _minuteWheel!,
                          values: _minutes,
                          selected: _minute,
                          onSelected: (index) =>
                              setState(() => _minute = _minutes[index]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space5),

            AppButtonV2(
              label: AppStrings.inviteTimeSheetConfirm,
              onPressed: () => Navigator.of(context).pop(_picked),
            ),
          ],
        ),
      ),
    );
  }
}

/// 숫자 하나를 고르는 휠.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.values,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final FixedExtentScrollController controller;
  final List<int> values;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _InviteTimeSheetState._itemExtent,
      physics: const FixedExtentScrollPhysics(),
      // 끝에서 더 돌리면 멈춘다. 순환시키면 23 다음에 0이 나와 범위 밖으로
      // 넘어간 것처럼 보인다.
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: values.length,
        builder: (context, index) {
          final value = values[index];
          final picked = value == selected;
          return Center(
            child: Text(
              value.toString().padLeft(2, '0'),
              style: AppTypographyV2.body02.copyWith(
                color: picked ? colors.textStrong : colors.textTertiary,
                // 자릿수가 흔들리지 않게 고정폭 숫자를 쓴다.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
        },
      ),
    );
  }
}
