// 디자인 토큰 확인용 임시 화면. 제품 코드가 아니다.
//
// 실행:
//   fvm flutter run -t lib/dev/token_preview.dart
//
// main.dart를 건드리지 않으려고 별도 진입점으로 뒀다.
// 토큰이 화면 작업에서 실제로 쓰이기 시작하면 이 폴더째 지운다.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/extensions/app_elevation.dart';
import 'package:runiverse/core/theme/extensions/app_glow.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 러닝 색 샘플. 디자인 시스템 §5-2 참조 팔레트에서 셋만 가져왔다.
/// 실제 팔레트는 `features/color/`가 소유한다 — 여기 있는 건 글로우를 보기 위한 대역이다.
const _runColors = <(String, Color)>[
  ('거리 · 틸', Color(0xFF42DCCC)),
  ('속도 · 레드오렌지', Color(0xFFE95834)),
  ('케이던스 · 바이올렛', Color(0xFF7144D9)),
];

void main() => runApp(const TokenPreviewApp());

class TokenPreviewApp extends StatefulWidget {
  const TokenPreviewApp({super.key});

  @override
  State<TokenPreviewApp> createState() => _TokenPreviewAppState();
}

class _TokenPreviewAppState extends State<TokenPreviewApp> {
  // 기본 테마는 다크다.
  var _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '디자인 토큰 확인',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: TokenPreviewPage(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(() {
          _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

class TokenPreviewPage extends StatefulWidget {
  const TokenPreviewPage({
    required this.isDark,
    required this.onToggleTheme,
    super.key,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<TokenPreviewPage> createState() => _TokenPreviewPageState();
}

class _TokenPreviewPageState extends State<TokenPreviewPage> {
  final _random = Random();
  Timer? _timer;
  var _pace = "5'32\"";

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {
        final m = 4 + _random.nextInt(3);
        final s = _random.nextInt(60);
        _pace = "$m'${s.toString().padLeft(2, '0')}\"";
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.bgSurface,
        title: Text('디자인 토큰', style: AppTypography.h3),
        actions: [
          TextButton(
            onPressed: widget.onToggleTheme,
            child: Text(
              widget.isDark ? '라이트로' : '다크로',
              style: AppTypography.body.copyWith(color: colors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space4),
        children: [
          _Section(title: '색 — 배경 · 텍스트', child: _surfaceSwatches(colors)),
          _Section(title: '색 — 브랜드 · 상태', child: _stateSwatches(colors)),
          _Section(title: '색 — 매칭 상태', child: _matchSwatches(colors)),
          _Section(title: '러닝 수치 (tabular)', child: _metric(colors)),
          _Section(title: '간격 space0~10', child: _spacing(colors)),
          _Section(title: '라운드', child: _radii(colors)),
          _Section(title: 'elevation — 중립 그림자', child: _elevations(colors)),
          _Section(title: 'glow — 러닝 색 전용', child: _glows()),
          _Section(title: '터치 타깃', child: _touchTargets(colors)),
        ],
      ),
    );
  }

  // ── 색 ────────────────────────────────────────────────────────

  Widget _surfaceSwatches(AppColors c) => Column(
    children: [
      _swatchRow('bgBase', c.bgBase, c),
      _swatchRow('bgSurface', c.bgSurface, c),
      _swatchRow('bgElevated', c.bgElevated, c),
      _swatchRow('borderDefault', c.borderDefault, c),
      _swatchRow('borderStrong', c.borderStrong, c),
      const SizedBox(height: AppSpacing.space3),
      _textSample('textPrimary — 본문·러닝 수치', c.textPrimary, c),
      _textSample('textSecondary — 보조 설명', c.textSecondary, c),
      _textSample('textTertiary — 캡션·플레이스홀더', c.textTertiary, c),
      _textSample('textDisabled — 비활성', c.textDisabled, c),
    ],
  );

  Widget _stateSwatches(AppColors c) => Column(
    children: [
      _swatchRow('primary', c.primary, c),
      _swatchRow('primaryHover', c.primaryHover, c),
      _swatchRow('primaryMuted', c.primaryMuted, c),
      _swatchRow('success', c.success, c),
      _swatchRow('warning', c.warning, c),
      _swatchRow('error', c.error, c),
      _swatchRow('info', c.info, c),
    ],
  );

  /// 실패 색이 순수 error보다 담담한지 나란히 확인한다.
  Widget _matchSwatches(AppColors c) => Column(
    children: [
      _swatchRow('matchWaiting', c.matchWaiting, c),
      _swatchRow('matchConfirmed', c.matchConfirmed, c),
      _swatchRow('matchFailed (블렌드)', c.matchFailed, c),
      _swatchRow('참고: 순수 error', c.error, c),
    ],
  );

  Widget _swatchRow(String label, Color color, AppColors c) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.sm,
            border: Border.all(color: c.borderDefault),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Text(label, style: AppTypography.body.copyWith(color: c.textSecondary)),
      ],
    ),
  );

  Widget _textSample(String label, Color color, AppColors c) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space1),
    child: Text(label, style: AppTypography.body.copyWith(color: color)),
  );

  // ── 러닝 수치 ─────────────────────────────────────────────────

  Widget _metric(AppColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '500ms마다 갱신 — 자릿수가 흔들리지 않아야 한다',
        style: AppTypography.caption.copyWith(color: c.textTertiary),
      ),
      const SizedBox(height: AppSpacing.space2),
      Text(
        _pace,
        style: AppTypography.metricHero.copyWith(color: c.textPrimary),
      ),
      Text(_pace, style: AppTypography.metricLg.copyWith(color: c.textPrimary)),
      Text(_pace, style: AppTypography.metricMd.copyWith(color: c.textPrimary)),
    ],
  );

  // ── 간격 · 라운드 ─────────────────────────────────────────────

  Widget _spacing(AppColors c) {
    const steps = <(String, double)>[
      ('space0', AppSpacing.space0),
      ('space1', AppSpacing.space1),
      ('space2', AppSpacing.space2),
      ('space3', AppSpacing.space3),
      ('space4', AppSpacing.space4),
      ('space5', AppSpacing.space5),
      ('space6', AppSpacing.space6),
      ('space7', AppSpacing.space7),
      ('space8', AppSpacing.space8),
      ('space9', AppSpacing.space9),
      ('space10', AppSpacing.space10),
    ];
    return Column(
      children: [
        for (final (label, value) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space1),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: AppTypography.micro.copyWith(color: c.textTertiary),
                  ),
                ),
                Container(width: value, height: 12, color: c.primary),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  '${value.toInt()}',
                  style: AppTypography.micro.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _radii(AppColors c) {
    const items = <(String, BorderRadius)>[
      ('sm 8', AppRadius.sm),
      ('md 12', AppRadius.md),
      ('lg 16', AppRadius.lg),
      ('xl 24', AppRadius.xl),
      ('full', AppRadius.full),
    ];
    return Wrap(
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space3,
      children: [
        for (final (label, radius) in items)
          Column(
            children: [
              Container(
                width: 72,
                height: 56,
                decoration: BoxDecoration(
                  color: c.bgElevated,
                  borderRadius: radius,
                  border: Border.all(color: c.borderStrong),
                ),
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                label,
                style: AppTypography.micro.copyWith(color: c.textTertiary),
              ),
            ],
          ),
      ],
    );
  }

  // ── elevation · glow ─────────────────────────────────────────

  Widget _elevations(AppColors c) {
    final e = context.appElevation;
    final items = <(String, List<BoxShadow>)>[
      ('level0', AppElevation.level0),
      ('level1', e.level1),
      ('level2', e.level2),
      ('level3', e.level3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '다크에서는 그림자 대신 면 밝기로 높이를 표현한다 — level1이 비어 있는 것이 정상이다',
          style: AppTypography.caption.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space4),
        Wrap(
          spacing: AppSpacing.space5,
          runSpacing: AppSpacing.space5,
          children: [
            for (final (label, shadows) in items)
              Column(
                children: [
                  Container(
                    width: 88,
                    height: 56,
                    decoration: BoxDecoration(
                      color: label == 'level0' ? c.bgSurface : c.bgElevated,
                      borderRadius: AppRadius.lg,
                      border: Border.all(color: c.borderDefault),
                      boxShadow: shadows,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    label,
                    style: AppTypography.micro.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _glows() {
    final glow = context.appGlow;
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '라이트에서는 절반 강도로 약해진다',
          style: AppTypography.caption.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space6),
        for (final (name, runColor) in _runColors)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.caption.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space5),
                Row(
                  children: [
                    for (final (label, shadows) in <(String, List<BoxShadow>)>[
                      ('sm', glow.sm(runColor)),
                      ('md', glow.md(runColor)),
                      ('lg', glow.lg(runColor)),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.space9,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: runColor,
                                borderRadius: AppRadius.md,
                                boxShadow: shadows,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space3),
                            Text(
                              label,
                              style: AppTypography.micro.copyWith(
                                color: c.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 터치 타깃 ─────────────────────────────────────────────────

  Widget _touchTargets(AppColors c) => Row(
    children: [
      for (final (label, size) in <(String, double)>[
        ('일반 44', AppSizes.touchDefault),
        ('러닝 56', AppSizes.touchRunning),
      ])
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.space4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size, minWidth: size * 2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.primaryMuted,
                borderRadius: AppRadius.full,
                border: Border.all(color: c.primary),
              ),
              child: Center(
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(color: c.primary),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.h3.copyWith(color: c.textPrimary)),
          const Divider(),
          const SizedBox(height: AppSpacing.space3),
          child,
        ],
      ),
    );
  }
}
