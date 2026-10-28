import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/friend/presentation/friend_row.dart';

/// 친구를 보고 찾고 맺는 한 화면 — 시안 `79:2081`.
///
/// ```
/// ‹  [🔍 닉네임으로 찾기            ]
/// ─────────────────────────────────
///      친구          │      추천
///  ━━━━━━━━━━        │
/// ```
///
/// ## ⚠️ 검색하면 탭이 접힌다
///
/// 검색은 탭과 무관하게 **전체 사용자**를 뒤진다(`/users/search`). 탭을
/// 남겨 두면 "친구 탭에서 검색했는데 모르는 사람이 나온다"가 된다.
///
/// 왼쪽 탭은 **이미 맺은 관계**(받은 요청·보낸 요청·친구), 오른쪽은 **새로
/// 맺을 사람**이다.
class FriendPage extends ConsumerStatefulWidget {
  const FriendPage({super.key});

  @override
  ConsumerState<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends ConsumerState<FriendPage> {
  final _scroll = ScrollController();

  /// 좌우 여백. 시안 `79:2081`이 14로 잡았다 — `AppSpacing` 눈금에 없다.
  static const _gutter = 14.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(friendProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 바닥 가까이 가면 같은 검색어로 50을 다시 받는다.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    ref.read(friendProvider.notifier).loadMoreSearch();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(friendProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _gutter,
                AppSpacing.space2,
                _gutter,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.chevronLeft),
                    color: colors.textPrimary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(child: _SearchField()),
                ],
              ),
            ),
            // ⚠️ 검색 중에는 탭이 없다.
            if (!state.searching) _Tabs(tab: state.tab),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _body(FriendState state) {
    if (state.loading && state.groups.isEmpty && !state.searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.searching) {
      return state.groups.isEmpty
          ? EmptyStateV2(
              icon: LucideIcons.search,
              message: AppStrings.friendEmptySearch(state.query),
            )
          : _groupList(state);
    }

    return switch (state.tab) {
      FriendTab.friends =>
        state.groups.isEmpty
            ? const EmptyStateV2(
                icon: LucideIcons.users,
                message: AppStrings.friendEmptyFriends,
                why: AppStrings.friendEmptyFriendsWhy,
              )
            : _groupList(state),
      FriendTab.recommendations =>
        state.recommendations.isEmpty
            ? const EmptyStateV2(
                icon: LucideIcons.sparkles,
                message: AppStrings.friendEmptyRecommendations,
                why: AppStrings.friendEmptyRecommendationsWhy,
              )
            : _recommendationList(state),
    };
  }

  Widget _groupList(FriendState state) => ListView(
    controller: _scroll,
    padding: const EdgeInsets.symmetric(horizontal: _gutter),
    children: [
      for (final group in state.groups) ...[
        _SectionHeader(relation: group.relation, count: group.entries.length),
        for (final entry in group.entries)
          FriendRow(
            key: ValueKey(entry.userId),
            entry: entry,
            busy: state.pending.contains(entry.userId),
            onAccept: () =>
                ref.read(friendProvider.notifier).accept(entry.userId),
            onReject: () =>
                ref.read(friendProvider.notifier).cancel(entry.userId),
            onCancel: () =>
                ref.read(friendProvider.notifier).cancel(entry.userId),
            onRequest: () =>
                ref.read(friendProvider.notifier).request(entry.userId),
            onRemove: () => _confirmRemove(entry),
          ),
      ],
    ],
  );

  Widget _recommendationList(FriendState state) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: _gutter),
    children: [
      for (final item in state.recommendations)
        FriendRow(
          key: ValueKey(item.entry.userId),
          entry: item.entry,
          busy: state.pending.contains(item.entry.userId),
          meta: _Reason(reason: item.reason),
          // 추천은 전부 `none` 이라 버튼이 하나다. 눌러서 `requestSent` 가
          // 되면 행이 "요청 취소"로 바뀌는 대신 잠긴 "요청됨" 이 된다.
          onRequest: () =>
              ref.read(friendProvider.notifier).request(item.entry.userId),
          onCancel: null,
        ),
    ],
  );

  /// 되돌릴 수 없어서 한 번 더 묻는다.
  Future<void> _confirmRemove(FriendEntry entry) async {
    final colors = context.appColorsV2;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(AppStrings.friendRemoveConfirmTitle),
        content: Text(AppStrings.friendRemoveConfirmBody(entry.nickname)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.friendRemoveConfirmNo),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              AppStrings.friendRemoveConfirmYes,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(friendProvider.notifier).remove(entry.userId);
    }
  }
}

/// 상단 고정 검색창. 시안 `79:2086`.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: TextField(
              controller: _controller,
              style: AppTypographyV2.body05.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: AppStrings.friendSearchHint,
                hintStyle: AppTypographyV2.body05.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              // 상태는 바로 바꾸고 조회만 미룬다 — 탭은 글자를 치는 즉시
              // 접혀야 한다.
              onChanged: ref.read(friendProvider.notifier).onQuery,
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 18),
              color: colors.textTertiary,
              onPressed: () {
                _controller.clear();
                ref.read(friendProvider.notifier).onQuery('');
              },
            ),
        ],
      ),
    );
  }
}

/// 밑줄 탭 둘. 시안 `79:2127`.
class _Tabs extends ConsumerWidget {
  const _Tabs({required this.tab});

  final FriendTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;

    Widget one(FriendTab value, String label) {
      final selected = value == tab;
      return Expanded(
        child: InkWell(
          onTap: () => ref.read(friendProvider.notifier).selectTab(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.textPrimary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body05.copyWith(
                color: selected ? colors.textPrimary : colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.space4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          one(FriendTab.friends, AppStrings.friendTabFriends),
          one(FriendTab.recommendations, AppStrings.friendTabRecommendations),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.relation, required this.count});

  final FriendRelation relation;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.space4,
        bottom: AppSpacing.space1,
      ),
      // ⚠️ **머리글과 수를 따로 세운다.** 한 덩이로 쓰면 "받은 요청 2"가
      // 통째로 한 글자 덩어리가 돼, 수만 색을 달리할 수도 읽는 쪽에서 머리글만
      // 집을 수도 없다.
      child: Row(
        children: [
          Text(
            _label(relation),
            style: AppTypographyV2.body07.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(width: AppSpacing.space1),
          Text(
            '$count',
            style: AppTypographyV2.body07.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _label(FriendRelation relation) => switch (relation) {
    FriendRelation.requestReceived => AppStrings.friendSectionReceived,
    FriendRelation.requestSent => AppStrings.friendSectionSent,
    FriendRelation.friend => AppStrings.friendSectionFriends,
    FriendRelation.none => AppStrings.friendSectionOthers,
  };
}

/// 시안의 `온라인 · 최근 접속` 자리. **접속 상태를 주는 API가 없어** 추천
/// 이유가 그 자리를 받는다.
class _Reason extends StatelessWidget {
  const _Reason({required this.reason});

  final FriendReason reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final color = switch (reason) {
      FriendReason.ranTogether => colors.primary,
      FriendReason.similarPace => colors.success,
    };
    final label = switch (reason) {
      FriendReason.ranTogether => AppStrings.friendReasonRanTogether,
      FriendReason.similarPace => AppStrings.friendReasonSimilarPace,
    };

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.space2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypographyV2.body07.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
