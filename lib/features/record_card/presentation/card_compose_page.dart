import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/core/widgets/v2/stat_row.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/activity_label.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/compose_records_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';

/// 날짜 휠에 세울 연도들. 서비스보다 앞은 뜻이 없다.
List<int> composeYearValues(DateTime today) => [
  for (var y = today.year - 2; y <= today.year; y++) y,
];

/// 날짜 휠에 세울 달들. **올해라면 이번 달까지다.**
///
/// ⚠️ 뛰지 않은 날의 카드는 없다. 고른 뒤에 막는 것이 아니라 **못 고르게**
/// 한다 — 휠은 만들 수 없는 값이 아예 없는 것이 장점이다
/// (`wheel_picker_sheet.dart`).
List<int> composeMonthValues({required int year, required DateTime today}) => [
  for (var m = 1; m <= (year == today.year ? today.month : 12); m++) m,
];

/// 날짜 휠에 세울 날들. 그 달의 날 수까지, **이번 달이면 오늘까지다.**
List<int> composeDayValues({
  required int year,
  required int month,
  required DateTime today,
}) {
  final last = year == today.year && month == today.month
      ? today.day
      // 다음 달 0일 = 이번 달 마지막 날.
      : DateTime(year, month + 1, 0).day;
  return [for (var d = 1; d <= last; d++) d];
}

/// 기록카드 작성 1 — 기록 고르기 · 유형 · 회고 (설계 6-2).
///
/// ## ⚠️ 날짜는 받고, 기록은 고른다
///
/// 어느 날인지는 들어올 때 정해진다(달력의 운동화, 탭 머리의 쓰기, 나중에는
/// 러닝 요약). 그날 뛴 것이 둘이면 **어느 기록인지는 사용자가 고른다** —
/// 기록 하나에 카드 하나다.
///
/// ## ⚠️ 오류가 화면을 덮지 않는다
///
/// 기록 조회가 실패하면 **목록 자리에만** 오류를 둔다. 화면 전체를 오류로
/// 덮으면 날짜를 바꿀 길까지 사라져, 다른 날로 옮겨 쓰지도 못한다.
class CardComposePage extends ConsumerStatefulWidget {
  const CardComposePage({required this.day, this.cardId, this.card, super.key});

  /// 고치는 카드. **`cardId`가 있으면 반드시 함께 온다** — 카드 단건 조회 API가
  /// 없어 라우트가 `extra`로 넘겨 준다(상세와 같은 방식).
  final RecordCard? card;

  /// 어느 날의 기록을 고를 것인가. **시·분은 보지 않는다.**
  final DateTime day;

  /// 수정 중인 카드 번호. `null`이면 새 카드다.
  final int? cardId;

  @override
  ConsumerState<CardComposePage> createState() => _CardComposePageState();
}

class _CardComposePageState extends ConsumerState<CardComposePage> {
  late DateTime _day = DateTime(
    widget.day.year,
    widget.day.month,
    widget.day.day,
  );

  final _review = TextEditingController();

  @override
  void initState() {
    super.initState();
    // ⚠️ **`initState`에서 provider를 고칠 수 없다**(Riverpod이 막는다).
    // 고치러 들어왔으면 첫 프레임 뒤에 뿌린다. 이미 손댄 초안이면 `seed`가
    // 아무 일도 하지 않는다 — 사진 화면에서 돌아올 때마다 고친 것이
    // 되돌아가면 안 된다.
    final card = widget.card;
    if (card != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(cardDraftProvider(widget.cardId).notifier).seed(card);
        _review.text = ref.read(cardDraftProvider(widget.cardId)).reviewText;
      });
    }
    // 초안에 쓰던 글이 있으면 칸에 되돌려 놓는다 — 사진 화면에서 돌아왔을 때다.
    _review.text = ref.read(cardDraftProvider(widget.cardId)).reviewText;
    // ⚠️ **들어올 때 쓰던 것이 있으면 묻는다**(설계 7절). 초안은 앱을 끄면
    // 사라지므로, 조용히 덮으면 되돌릴 길이 없다. 첫 프레임 뒤에 띄운다 —
    // `initState` 안에서는 아직 시트를 올릴 수 없다.
    // ⚠️ **수정에서는 묻지 않는다.** "쓰던 기록카드가 있어요 / 새로 쓰기"는
    // 작성의 말이고, 고치러 들어온 사람에게는 **카드가 지워지는 것처럼**
    // 읽힌다. 고치다 만 것은 `seed`가 지켜 준다.
    if (!_editing && ref.read(cardDraftProvider(widget.cardId)).isDirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askResume());
    }
  }

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  CardDraftController get _draft =>
      ref.read(cardDraftProvider(widget.cardId).notifier);

  /// 고치러 들어왔나. 제목·날짜 줄·기록 목록이 이것으로 갈린다.
  ///
  /// ⚠️ **카드가 왔는지로 본다.** 첫 프레임에는 초안이 아직 비어 있어
  /// `draft.editing`으로는 가릴 수 없다 — 뿌리는 것은 프레임 뒤다.
  bool get _editing => widget.card != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final draft = ref.watch(cardDraftProvider(widget.cardId));
    // 고른 기록의 경로를 받아 초안에 넣는다. 받는 동안에는 자리만 지킨다.
    _watchRoute(draft.record);

    return PopScope(
      // ⚠️ **시스템 뒤로도 막는다.** 머리의 버튼만 막으면 안드로이드에서
      // 제스처로 그냥 빠져나가 쓴 글이 사라진다.
      canPop: !draft.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: _body(context, colors, draft),
    );
  }

  Widget _body(BuildContext context, AppColorsV2 colors, CardDraft draft) {
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: _leave,
        ),
        title: Text(
          _editing
              ? AppStrings.recordCardEditTitle
              : AppStrings.recordCardComposeTitle,
          style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            // ⚠️ **초안만 들고 간다.** 사진 화면은 날짜를 쿼리로 받지 않는다 —
            // 어느 날인지는 초안의 `record`가 안다. 두 곳에 두면 갈라진다.
            // ⚠️ **수정이면 카드를 들고 간다.** 사진·공개범위 라우트가
            // `extra`로 그것을 받아야 초안을 어느 번호로 가를지 안다.
            onPressed: draft.canProceed
                ? () => _editing
                      ? context.push(
                          AppRoutes.recordCardEditPhotosOf(widget.card!.id),
                          extra: widget.card,
                        )
                      : context.push(AppRoutes.recordCardNewPhotos)
                : null,
            child: Text(AppStrings.recordCardComposeNext),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space2,
            AppSpacing.space4,
            AppSpacing.space8,
          ),
          children: [
            _SectionLabel(AppStrings.recordCardComposeRecordSection),
            // ⚠️ **수정이면 날짜도 기록도 못 고른다**(설계 6-6). 날짜를 열어
            // 두면 그날의 다른 기록으로 옮기는 길이 함께 열린다.
            _DateRow(day: _day, onTap: _editing ? null : _pickDay),
            const SizedBox(height: AppSpacing.space2),
            if (_editing) ...[
              _Locked(AppStrings.recordCardEditRecordLocked),
              const SizedBox(height: AppSpacing.space4),
              _SavedRoute(card: widget.card!),
              const SizedBox(height: AppSpacing.space3),
              _SavedMetrics(card: widget.card!),
            ] else ...[
              _RecordList(
                day: _day,
                selectedId: draft.record?.id,
                onPick: _pick,
              ),
              if (draft.record != null) ...[
                const SizedBox(height: AppSpacing.space4),
                _RoutePreview(record: draft.record!, route: draft.route),
                const SizedBox(height: AppSpacing.space3),
                _Metrics(record: draft.record!),
              ],
            ],
            const SizedBox(height: AppSpacing.space6),
            _SectionLabel(AppStrings.recordCardComposeActivitySection),
            _ActivityChoice(
              selected: draft.activity,
              onChanged: _draft.setActivity,
            ),
            const SizedBox(height: AppSpacing.space6),
            _SectionLabel(AppStrings.recordCardReview),
            AppInputV2(
              controller: _review,
              hint: AppStrings.recordCardComposeReviewHint,
              minLines: 4,
              maxLines: 8,
              counter: AppStrings.recordCardComposeReviewCounter(
                draft.reviewText.length,
                CardDraft.reviewMaxLength,
              ),
              // ⚠️ 칸에서 막고 초안에서 한 번 더 자른다. 통째로 담으면
              // 저장에서 거절당하고 쓴 글을 잃는다.
              inputFormatters: [
                LengthLimitingTextInputFormatter(CardDraft.reviewMaxLength),
              ],
              onChanged: _draft.setReview,
            ),
          ],
        ),
      ),
    );
  }

  /// 뒤로. 쓴 것이 있으면 **버릴지 묻는다.**
  Future<void> _leave() async {
    if (!ref.read(cardDraftProvider(widget.cardId)).isDirty) {
      Navigator.of(context).maybePop();
      return;
    }
    await _confirmDiscard();
  }

  Future<void> _confirmDiscard() async {
    final card = widget.card;
    final discard = await _ask(
      title: card == null
          ? AppStrings.recordCardComposeDiscardTitle
          : AppStrings.recordCardEditDiscardTitle,
      body: card == null
          ? AppStrings.recordCardComposeDiscardBody
          : AppStrings.recordCardEditDiscardBody,
      yes: AppStrings.recordCardComposeDiscard,
      no: AppStrings.recordCardComposeKeep,
    );
    if (discard != true || !mounted) return;

    // ⚠️ **수정이면 비우지 않고 카드 값으로 되돌린다.** `clear()`는 `editing`
    // 까지 지우는데, 화면은 여전히 수정 모드라 기록을 채울 길이 없다 —
    // `canProceed`가 영원히 거짓이 되어 **저장할 수 없는 수정 화면**에 갇힌다.
    // 뜻으로도 "버리기"는 고친 것을 버리는 것이지 카드를 버리는 것이 아니다.
    if (card == null) {
      _draft.clear();
    } else {
      _draft.restore(card);
    }
    _review.text = ref.read(cardDraftProvider(widget.cardId)).reviewText;
    if (!mounted) return;
    // ⚠️ **`maybePop`을 쓰지 않는다.** 방금 비운 초안은 아직 다시 그려지지
    // 않아 `PopScope.canPop`이 그대로 `false`고, `maybePop`은 그것을 보고
    // 같은 시트를 또 띄운다 — 사용자가 버리겠다고 한 뒤 빈 화면에 갇힌다.
    // `pop`은 그 검사를 건너뛴다. 나갈 데가 없으면(루트) 아무것도 안 한다.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// 쓰던 초안을 이어 쓸지 묻는다. **화면에 그대로 머문다** — 어느 쪽을
  /// 골라도 나가지 않는다.
  Future<void> _askResume() async {
    final resume = await _ask(
      title: AppStrings.recordCardComposeResumeTitle,
      body: AppStrings.recordCardComposeResumeBody,
      yes: AppStrings.recordCardComposeResume,
      no: AppStrings.recordCardComposeStartOver,
    );
    if (!mounted) return;

    // ⚠️ **`null`은 이어 쓰기다.** 바깥을 눌러 닫거나 시스템 뒤로로 시트를
    // 치운 것은 "버려라"가 아니다. 이 앱의 모든 시트가 바깥 탭으로 닫히므로,
    // 그 무심한 동작 하나로 쓴 회고가 사라지면 되돌릴 길이 없다 — 초안은
    // 영속화하지 않는다.
    if (resume != false) {
      // 쓰던 기록이 있으면 그 날짜로 돌아간다 — 이어 쓰는 것은 그날 카드다.
      final record = ref.read(cardDraftProvider(widget.cardId)).record;
      if (record != null) setState(() => _day = record.day);
      _review.text = ref.read(cardDraftProvider(widget.cardId)).reviewText;
      return;
    }

    _draft.clear();
    _review.clear();
  }

  /// 예·아니오 두 갈래 시트. **바깥을 눌러 닫으면 `null`이다** — 아무것도
  /// 하지 않는다.
  Future<bool?> _ask({
    required String title,
    required String body,
    required String yes,
    required String no,
  }) => showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.appColorsV2.bgSurface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypographyV2.body04.copyWith(
                color: sheet.appColorsV2.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              body,
              style: AppTypographyV2.body18.copyWith(
                color: sheet.appColorsV2.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            AppButtonV2(
              label: yes,
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
            const SizedBox(height: AppSpacing.space2),
            AppButtonV2(
              label: no,
              variant: AppButtonV2Variant.secondary,
              onPressed: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      ),
    ),
  );

  /// 고른 기록의 경로 선 아트를 받아 초안에 넣는다.
  ///
  /// ⚠️ **경로는 기록 목록에 없다.** 러닝 결과 상세(`byRoom`)를 따로 받아야
  /// 좌표가 온다. 그래서 고른 뒤에 채워지고, 못 받으면 비어 있다.
  void _watchRoute(RunRecord? record) {
    if (record == null) return;
    final detail = ref.watch(runDetailProvider(record.runningRoomId));
    final art = detail.value;
    if (art == null) return;

    final normalized = normalizeRoute(art.track);
    final draft = ref.read(cardDraftProvider(widget.cardId));
    if (draft.route != null || draft.record?.id != record.id) return;
    if (normalized.isEmpty) return;
    // build 중에 상태를 바꾸지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _draft.setRoute(normalized);
    });
  }

  /// 기록 한 줄을 골랐다.
  ///
  /// ⚠️ **이미 카드가 있는 기록은 고르는 것이 아니라 그 카드로 간다**(설계
  /// 6-2). 수정 화면은 뒤 PR이라 지금은 상세로 보낸다 — 눌리는데 아무 일도
  /// 안 일어나는 줄을 만들지 않는다.
  void _pick(ComposableRecord choice) {
    final card = choice.existingCard;
    if (card != null) {
      context.push(
        // 내가 쓴 카드다 — 내 기록 목록에서 왔다.
        AppRoutes.recordCardDetailOf(card.id, mine: true),
        extra: card,
      );
      return;
    }
    _draft.pickRecord(choice.record);
  }

  Future<void> _pickDay() async {
    final now = ref.read(recordCardClockProvider)();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showWheelPickerSheet(
      context,
      title: AppStrings.recordCardComposeDateSheet,
      columns: [
        WheelColumn(
          unit: AppStrings.profileUnitYear,
          values: composeYearValues(today),
          initial: _day.year,
        ),
        WheelColumn(
          unit: AppStrings.profileUnitMonth,
          values: composeMonthValues(year: _day.year, today: today),
          initial: _day.month,
          valuesFor: (picked) =>
              composeMonthValues(year: picked[0], today: today),
        ),
        WheelColumn(
          unit: AppStrings.profileUnitDay,
          values: composeDayValues(
            year: _day.year,
            month: _day.month,
            today: today,
          ),
          initial: _day.day,
          valuesFor: (picked) =>
              composeDayValues(year: picked[0], month: picked[1], today: today),
        ),
      ],
    );
    if (picked == null) return;

    final next = DateTime(picked[0], picked[1], picked[2]);
    if (next == _day) return;

    setState(() => _day = next);
    // ⚠️ **고른 기록을 함께 푼다.** 안 풀면 날짜 행은 새 날인데 초안은 앞
    // 날의 기록을 들고 있고, 그 아래 경로와 지표도 앞 날 것이다. `다음`이
    // 켜진 채라 그대로 저장하면 **엉뚱한 러닝에 카드가 붙는다.**
    _draft.clearRecord();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
    child: Text(
      label,
      style: AppTypographyV2.body07.copyWith(
        color: context.appColorsV2.textPrimary,
      ),
    ),
  );
}

/// 왜 못 바꾸는지 적어 두는 한 줄.
///
/// ⚠️ **그냥 잠가 두지 않는다.** 이유 없이 안 눌리는 자리는 고장으로 읽힌다.
class _Locked extends StatelessWidget {
  const _Locked(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        Icon(LucideIcons.lock, size: 14, color: colors.textSecondary),
        const SizedBox(width: AppSpacing.space2),
        Text(
          text,
          style: AppTypographyV2.body20.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// 고치는 카드의 선 아트. **다시 받아 오지 않는다** — 카드가 경로를 들고 있다
/// (설계 3절).
class _SavedRoute extends StatelessWidget {
  const _SavedRoute({required this.card});

  final RecordCard card;

  static const _height = 240.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SizedBox(
      height: _height,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: AppRadius.md,
            ),
            child: card.route.isEmpty
                ? _Note(AppStrings.recordCardComposeRouteNone)
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: RouteArtView(
                      art: card.route,
                      color: colors.primary,
                      strokeWidth: 2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 고치는 카드의 지표. 카드가 스냅샷으로 들고 있다(설계 3절).
class _SavedMetrics extends StatelessWidget {
  const _SavedMetrics({required this.card});

  final RecordCard card;

  @override
  Widget build(BuildContext context) => StatRowV2(
    stats: [
      Stat(
        label: AppStrings.recordCardDistance,
        value:
            '${AppStrings.kmFloor(card.distanceMeters)} '
            '${AppStrings.runPartyUnitKm}',
      ),
      Stat(
        label: AppStrings.recordCardPace,
        value:
            '${AppStrings.recordRunDuration(card.averagePace)}'
            '${AppStrings.runPartyUnitPerKm}',
      ),
      Stat(
        label: AppStrings.recordCardDuration,
        value: AppStrings.recordRunDuration(card.duration),
      ),
    ],
  );
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.day, required this.onTap});

  final DateTime day;

  /// `null`이면 수정 중이라 날짜를 못 바꾼다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: AppRadius.md,
        ),
        child: Row(
          children: [
            Text(
              AppStrings.recordCardComposeDateLabel(day),
              style: AppTypographyV2.body07.copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Icon(LucideIcons.calendar, size: 20, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 그날 고를 수 있는 기록들. **loading / data / error 세 갈래다.**
class _RecordList extends ConsumerWidget {
  const _RecordList({
    required this.day,
    required this.selectedId,
    required this.onPick,
  });

  final DateTime day;
  final int? selectedId;
  final ValueChanged<ComposableRecord> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final records = ref.watch(composeRecordsProvider(day));

    return switch (records) {
      AsyncLoading() => const Padding(
        padding: EdgeInsets.all(AppSpacing.space6),
        child: Center(child: CircularProgressIndicator()),
      ),
      AsyncError() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.recordCardComposeRecordsError,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          AppButtonV2(
            label: AppStrings.recordRetry,
            variant: AppButtonV2Variant.secondary,
            expand: false,
            onPressed: () => ref.invalidate(composeRecordsProvider(day)),
          ),
        ],
      ),
      AsyncValue(:final value?) when value.isEmpty => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
        child: Text(
          AppStrings.recordCardComposeNoRecords,
          textAlign: TextAlign.center,
          style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
        ),
      ),
      AsyncValue(:final value?) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final choice in value)
            _RecordRow(
              choice: choice,
              on: choice.record.id == selectedId,
              onTap: () => onPick(choice),
            ),
        ],
      ),
    };
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.choice,
    required this.on,
    required this.onTap,
  });

  final ComposableRecord choice;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final record = choice.record;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.md,
            border: on ? Border.all(color: colors.primary) : null,
          ),
          child: Row(
            children: [
              Icon(
                on ? LucideIcons.circleDot : LucideIcons.circle,
                size: 18,
                color: on ? colors.primary : colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  AppStrings.recordRunLine(
                    record.startedAt,
                    record.distanceKm,
                    record.duration,
                  ),
                  style: AppTypographyV2.body18.copyWith(
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // ⚠️ **회색으로 죽이지 않는다.** 왜 못 고르는지 알 수 없다.
              // 누르면 그 카드로 간다(설계 6-2).
              if (choice.hasCard) _CardBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        AppStrings.recordCardComposeHasCard,
        style: AppTypographyV2.body18.copyWith(color: colors.textOnPrimary),
      ),
    );
  }
}

/// 고른 기록의 경로 선 아트. **9:16이다** — 카드가 세로로 서기 때문이다.
///
/// ## ⚠️ 높이를 고정한다
///
/// 폭을 다 쓰면 9:16이 **화면보다 높아진다**(폭 400dp면 높이 711dp). 그러면
/// 유형과 회고가 한 화면에 안 들어와, 입력하러 온 사람이 스크롤부터 해야 한다.
/// 작성 화면의 주인공은 입력이고 미리보기는 확인용이다.
///
/// ⚠️ **디자인 확인이 필요한 값이다.**
class _RoutePreview extends ConsumerWidget {
  const _RoutePreview({required this.record, required this.route});

  final RunRecord record;
  final RouteArt? route;

  static const _height = 240.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final detail = ref.watch(runDetailProvider(record.runningRoomId));

    return SizedBox(
      height: _height,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: AppRadius.md,
            ),
            child: switch (detail) {
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              // ⚠️ **못 받은 것과 없는 것을 갈라 말한다.** 다시 열면 보일 수
              // 있는 것을 "경로가 없는 러닝"이라고 하면 사실이 아니다.
              AsyncError() => _Note(AppStrings.recordCardComposeRouteFailed),
              _ when route == null || route!.isEmpty => _Note(
                AppStrings.recordCardComposeRouteNone,
              ),
              _ => Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: RouteArtView(
                  art: route!,
                  color: colors.primary,
                  strokeWidth: 2,
                ),
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypographyV2.body18.copyWith(
          color: context.appColorsV2.textSecondary,
        ),
      ),
    ),
  );
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) => StatRowV2(
    stats: [
      Stat(
        label: AppStrings.recordCardDistance,
        value:
            '${AppStrings.kmFloor(record.distanceMeters)} '
            '${AppStrings.runPartyUnitKm}',
      ),
      Stat(
        label: AppStrings.recordCardPace,
        value:
            '${AppStrings.recordRunDuration(record.averagePace)}'
            '${AppStrings.runPartyUnitPerKm}',
      ),
      Stat(
        label: AppStrings.recordCardDuration,
        value: AppStrings.recordRunDuration(record.duration),
      ),
    ],
  );
}

/// 러닝 유형 셋 중 하나. **`ActivityFilter`를 쓰지 않는다.**
///
/// 그쪽은 `null`(전체)을 허용하고 고른 것을 다시 누르면 꺼진다. 작성에서는
/// 하나가 **반드시** 켜져야 해서(설계 6-2의 `다음` 조건) 끄는 길이 있으면 안
/// 된다.
class _ActivityChoice extends StatelessWidget {
  const _ActivityChoice({required this.selected, required this.onChanged});

  final RecordCardActivity? selected;
  final ValueChanged<RecordCardActivity> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        for (final activity in RecordCardActivity.values) ...[
          if (activity != RecordCardActivity.values.first)
            const SizedBox(width: AppSpacing.space2),
          GestureDetector(
            onTap: () => onChanged(activity),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: selected == activity ? colors.primary : colors.bgSurface,
                borderRadius: AppRadius.full,
              ),
              child: Text(
                recordCardActivityLabel(activity),
                style: AppTypographyV2.body18.copyWith(
                  color: selected == activity
                      ? colors.textOnPrimary
                      : colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
