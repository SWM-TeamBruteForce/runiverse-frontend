import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/matching/presentation/invite_time_sheet.dart';

/// 시작 시각 다이얼.
///
/// ## ⚠️ 범위가 휠 안에 들어간다
///
/// 아날로그 시계판은 범위 밖을 고를 수 있어서 **되돌려 주는 수밖에 없다.**
/// 숫자 휠은 고를 수 있는 값만 담으므로 애초에 범위 밖이 없다 — 그 성질이
/// 깨지면 서버가 `INVITE_START_AT_OUT_OF_RANGE`로 거절한다.
void main() {
  Future<DateTime?> open(
    WidgetTester tester, {
    required DateTime from,
    required DateTime to,
    DateTime? selected,
  }) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showInviteTimeSheet(
                    context,
                    from: from,
                    to: to,
                    selected: selected,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return picked;
  }

  /// 그 휠에 그려진 숫자들.
  List<String> digitsOf(WidgetTester tester, Key key) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)),
      )
      .map((t) => t.data!)
      .toList();

  group('시 휠', () {
    testWidgets('⚠️ 범위 밖의 시는 아예 없다', (tester) async {
      await open(
        tester,
        from: DateTime(2026, 10, 29, 19, 11),
        to: DateTime(2026, 10, 29, 23, 59),
      );

      final hours = digitsOf(tester, const ValueKey('invite-hour-wheel'));
      // 19~23만. 18이나 0이 있으면 보낼 수 없는 값을 고를 수 있다.
      expect(hours, isNot(contains('18')));
      expect(hours, isNot(contains('00')));
      expect(hours, contains('19'));
    });

    testWidgets('바닥과 천장이 같은 시각이면 한 칸뿐이다', (tester) async {
      // 23:48에 열면 고를 수 있는 것이 23:59 하나다.
      await open(
        tester,
        from: DateTime(2026, 10, 29, 23, 59),
        to: DateTime(2026, 10, 29, 23, 59),
      );

      final hours = digitsOf(tester, const ValueKey('invite-hour-wheel'));
      expect(hours.where((h) => h == '23'), hasLength(1));
      expect(hours, isNot(contains('22')));
    });
  });

  group('분 휠', () {
    testWidgets('⚠️ 바닥 시각에서는 그 분부터 시작한다', (tester) async {
      await open(
        tester,
        from: DateTime(2026, 10, 29, 19, 11),
        to: DateTime(2026, 10, 29, 23, 59),
      );

      final minutes = digitsOf(
        tester,
        const ValueKey('invite-minute-wheel-19'),
      );
      // 19:05는 보낼 수 없다.
      expect(minutes, isNot(contains('05')));
      expect(minutes, contains('11'));
    });

    testWidgets('⚠️ 천장 시각에서는 그 분까지만 있다', (tester) async {
      await open(
        tester,
        from: DateTime(2026, 10, 29, 23, 30),
        to: DateTime(2026, 10, 29, 23, 45),
      );
      const wheel = ValueKey('invite-minute-wheel-23');

      // ⚠️ **휠은 보이는 칸만 만든다.** 아래쪽 값을 보려면 굴려야 한다.
      expect(digitsOf(tester, wheel), isNot(contains('29')));

      await tester.drag(find.byKey(wheel), const Offset(0, -1000));
      await tester.pumpAndSettle();

      final bottom = digitsOf(tester, wheel);
      expect(bottom, contains('45'));
      expect(bottom, isNot(contains('46')));
    });
  });

  group('고르면 그 시각을 준다', () {
    testWidgets('아무것도 안 돌리면 바닥 시각이다', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showInviteTimeSheet(
                      context,
                      from: DateTime(2026, 10, 29, 19, 11),
                      to: DateTime(2026, 10, 29, 23, 59),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.inviteTimeSheetConfirm));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 10, 29, 19, 11));
    });

    testWidgets('⚠️ 들고 있던 값이 범위 밖이면 끌어다 둔다', (tester) async {
      // 화면을 열어 둔 사이에 시간이 흘러 바닥이 올라갔을 때다.
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showInviteTimeSheet(
                      context,
                      from: DateTime(2026, 10, 29, 20),
                      to: DateTime(2026, 10, 29, 23, 59),
                      selected: DateTime(2026, 10, 29, 19, 30),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.inviteTimeSheetConfirm));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 10, 29, 20));
    });
  });

  group('⚠️ 아날로그 시계판이 아니다', () {
    testWidgets('시계판 피커를 쓰지 않는다', (tester) async {
      await open(
        tester,
        from: DateTime(2026, 10, 29, 19, 11),
        to: DateTime(2026, 10, 29, 23, 59),
      );

      // `showTimePicker`의 시계판이 서면 안 된다.
      expect(find.byType(TimePickerDialog), findsNothing);
      // 숫자 휠 둘이 선다.
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    });
  });
}
