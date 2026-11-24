import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 누구의 카드를, 몇 장까지.
///
/// ⚠️ **`limit`이 키에 들어간다.** 그리드는 여섯 장만 묻고 전체 보기는 서버
/// 기본값(20)으로 묻는다 — 둘은 **다른 조회**다. 키에서 빼면 전체 보기가
/// 그리드의 여섯 장을 그대로 쓴다.
typedef ProfileCardsQuery = ({String userId, int? limit});

/// 프로필 그리드가 읽는 **첫 페이지**(설계 6-7).
///
/// ## ⚠️ `profile/`에 있고 `record_card`의 provider를 읽는다
///
/// CLAUDE.md는 다른 feature의 **화면·위젯** import를 막지만 **provider는
/// 예외**로 적어 두었다. 그리드가 `profile/`에 있는 이유는 설계 7절이다 —
/// 반대로 두면 `profile`이 `record_card`의 화면을 가져다 쓴다.
///
/// ## ⚠️ 자동 재시도를 끈다
///
/// Riverpod 3은 실패한 provider를 **10번까지 다시 부른다**(지수 백오프, 합쳐
/// 약 38초 — `ProviderContainer.defaultRetry`). 그동안 화면은 로딩만 돌고
/// **오류 분기에 닿지 못한다.** 403·404는 기다려도 답이 달라지지 않고, 망
/// 오류도 사용자가 `다시 시도`를 누르는 편이 38초보다 낫다
/// (`composeRecordsProvider`에 같은 주석이 있다).
///
/// ## ⚠️ 화면을 닫으면 버린다
///
/// 남의 프로필을 여럿 다녀오면 사람마다 목록이 하나씩 쌓인다. 다시 열 때
/// 새로 받는 편이 맞다 — 그 사이에 카드가 늘거나 줄었다.
final profileCardsProvider = FutureProvider.autoDispose
    .family<RecordCardListPage, ProfileCardsQuery>(
      retry: (_, _) => null,
      (ref, query) => ref
          .read(recordCardRepositoryProvider)
          .cardsOf(userId: query.userId, limit: query.limit),
    );

/// 전체 보기가 보는 상태. loading / data / error 세 갈래다.
sealed class ProfileCardsState {
  const ProfileCardsState();
}

class ProfileCardsLoading extends ProfileCardsState {
  const ProfileCardsLoading();
}

class ProfileCardsError extends ProfileCardsState {
  const ProfileCardsError(this.failure);

  final RecordCardFailure failure;
}

class ProfileCardsData extends ProfileCardsState {
  const ProfileCardsData({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<RecordCardListItem> items;

  /// `null`이면 **여기가 끝이다.**
  final String? nextCursor;

  /// 다음 페이지를 받는 중. 바닥에 표시를 세운다.
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  ProfileCardsData copyWith({
    List<RecordCardListItem>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
  }) => ProfileCardsData(
    items: items ?? this.items,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// 전체 보기 — **커서로 이어 받는다**(설계 6-7, 연동 가이드 5절 2번).
///
/// ## ⚠️ 그리드의 커서를 물려받지 않는다
///
/// 그리드가 떠 있었는지에 따라 전체 보기의 첫 요청이 달라지면, 새로 고침
/// 뒤에는 커서가 없어 **같은 화면이 두 가지로 돈다.** 가이드가 둘 다 허용한다
/// ("전체 보기를 빈 목록으로 시작한다면 첫 요청은 커서 없이"). 값: 첫 여섯
/// 장을 한 번 더 받는다.
final profileCardsPageProvider =
    NotifierProvider.family<ProfileCardsController, ProfileCardsState, String>(
      ProfileCardsController.new,
      isAutoDispose: true,
    );

class ProfileCardsController extends Notifier<ProfileCardsState> {
  ProfileCardsController(this.userId);

  final String userId;

  /// 더 받는 중인가.
  ///
  /// ⚠️ **없으면 스크롤이 요청을 쏟는다.** 바닥에 닿으면 스크롤하는 내내 매
  /// 프레임 [loadMore]가 불린다 — 달력이 같은 함정을 적어 두었다
  /// (`RecordCardController._loadingOlder`).
  var _loadingMore = false;

  var _alive = false;

  @override
  ProfileCardsState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(load);
    return const ProfileCardsLoading();
  }

  /// 첫 페이지. 오류 화면의 `다시 시도`도 이것을 부른다.
  Future<void> load() async {
    _loadingMore = false;
    try {
      final page = await ref
          .read(recordCardRepositoryProvider)
          .cardsOf(userId: userId);
      if (!_alive) return;
      state = ProfileCardsData(items: page.items, nextCursor: page.nextCursor);
    } on RecordCardException catch (error) {
      if (!_alive) return;
      state = ProfileCardsError(error.failure);
    }
  }

  /// 다음 페이지를 뒤에 붙인다.
  Future<void> loadMore() async {
    final current = state;
    if (_loadingMore) return;
    if (current is! ProfileCardsData) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    _loadingMore = true;
    state = current.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(recordCardRepositoryProvider)
          .cardsOf(userId: userId, cursor: cursor);
      if (!_alive) return;
      state = ProfileCardsData(
        items: [...current.items, ...page.items],
        nextCursor: page.nextCursor,
      );
    } on RecordCardException {
      // ⚠️ **받아 둔 목록을 오류 화면으로 덮지 않는다.** 지하철에서 한 번
      // 끊겼다고 잘 보던 카드가 사라지면 안 된다 — 표시만 거두고, 다시
      // 스크롤하면 또 시도한다.
      if (!_alive) return;
      state = current.copyWith(loadingMore: false);
    } finally {
      _loadingMore = false;
    }
  }
}
