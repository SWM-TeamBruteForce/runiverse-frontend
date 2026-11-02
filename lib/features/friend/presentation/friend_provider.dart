import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/friend/data/http_friend_repository.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_group.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => HttpFriendRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 검색어가 없을 때 보이는 두 탭.
enum FriendTab { friends, recommendations }

/// 친구 화면이 보는 상태.
class FriendState {
  const FriendState({
    this.tab = FriendTab.friends,
    this.query = '',
    this.friends = const [],
    this.friendCursor,
    this.recommendations = const [],
    this.results = const [],
    this.searchLimit = 0,
    this.loading = false,
    this.failure,
    this.actionFailure,
    this.changed = false,
    this.pending = const {},
  });

  final FriendTab tab;
  final String query;

  /// 내 친구 목록 — 받은 요청·보낸 요청·친구가 섞여 서버 순서대로 들어 있다.
  final List<FriendEntry> friends;
  final String? friendCursor;

  final List<FriendRecommendation> recommendations;

  /// 검색 결과. 검색어가 비면 비어 있다.
  final List<FriendEntry> results;

  /// 마지막으로 요청한 `limit`. 0이면 아직 안 받았다.
  final int searchLimit;

  final bool loading;

  /// **조회**가 실패했다. 본문이 이 자리를 대신 그린다.
  final FriendFailure? failure;

  /// **버튼**이 실패했다. 본문은 그대로 두고 한 줄로 알린다.
  ///
  /// ⚠️ [failure]와 가른 이유 — 404로 그 줄이 목록에서 빠지면 묶음이 빌 수
  /// 있는데, 하나로 두면 "불러오지 못했어요" 화면이 떠서 **멀쩡히 받아 둔
  /// 목록을 못 받은 것처럼** 보이게 된다.
  final FriendFailure? actionFailure;

  /// 이 화면에서 관계를 한 번이라도 바꿨는가.
  ///
  /// ⚠️ **프로필이 이것을 보고 친구 수를 다시 읽는다.** push된 라우트라
  /// 돌아가도 저절로 갱신되지 않는다. 들여다보기만 한 사람에게까지 요청을
  /// 보낼 이유는 없어서, 바꿨을 때만 참이다.
  final bool changed;

  /// 지금 서버에 다녀오는 중인 상대들. 연타를 막는다.
  final Set<String> pending;

  /// 검색 중인가. **참이면 화면이 탭을 접는다.**
  bool get searching => query.isNotEmpty;

  /// 지금 그릴 묶음.
  List<FriendGroup> get groups => switch (this) {
    _ when searching => groupFriends(results, friendOrderSearch),
    _ when tab == FriendTab.friends => groupFriends(friends, friendOrderMine),
    _ => const [],
  };

  /// 내가 답해야 할 요청 수. 프로필의 빨간 숫자가 이것을 쓴다.
  int get receivedCount =>
      friends.where((e) => e.relation == FriendRelation.requestReceived).length;

  FriendState copyWith({
    FriendTab? tab,
    String? query,
    List<FriendEntry>? friends,
    String? friendCursor,
    List<FriendRecommendation>? recommendations,
    List<FriendEntry>? results,
    int? searchLimit,
    bool? loading,
    FriendFailure? failure,
    FriendFailure? actionFailure,
    bool? changed,
    Set<String>? pending,
    bool clearFriendCursor = false,
    bool clearChanged = false,
  }) => FriendState(
    tab: tab ?? this.tab,
    query: query ?? this.query,
    friends: friends ?? this.friends,
    // ⚠️ `??`라 넘기지 않으면 남는다. 지우려면 `clearFriendCursor`다.
    friendCursor: clearFriendCursor
        ? null
        : (friendCursor ?? this.friendCursor),
    recommendations: recommendations ?? this.recommendations,
    results: results ?? this.results,
    searchLimit: searchLimit ?? this.searchLimit,
    loading: loading ?? this.loading,
    // ⚠️ `failure`는 `??`로 두지 않는다. 다음 동작이 성공했을 때 지울 수
    // 있어야 한다 — 그러려면 넘기지 않은 것과 `null`을 넘긴 것이 같아야 한다.
    failure: failure,
    actionFailure: actionFailure,
    changed: clearChanged ? false : (changed ?? this.changed),
    pending: pending ?? this.pending,
  );
}

final friendProvider = NotifierProvider<FriendController, FriendState>(
  FriendController.new,
);

/// 친구 화면의 상태를 옮긴다.
///
/// ## ⚠️ 버튼을 누른 뒤 목록을 다시 읽지 않는다
///
/// 응답이 준 관계로 **그 줄만** 바꾼다. 다시 받으면 수락한 줄이 사라졌다
/// 나타나고, 그 사이 스크롤 자리도 잃는다. 명세도 "다시 불러오지 말고 그
/// 항목을 친구 묶음 맨 위로 옮기라"고 권한다.
class FriendController extends Notifier<FriendState> {
  Timer? _debounce;

  /// 이어 읽기가 다녀오는 중인가.
  ///
  /// ⚠️ **상태에 두지 않는다.** 스크롤 알림마다 불리는 자리라, 응답이 오기
  /// 전에 또 들어온다. `searchLimit`은 응답이 와야 바뀌므로 막지 못한다.
  var _loadingMore = false;

  /// 검색을 미루는 시간. 닉네임 중복 확인(`nickname_field.dart`)과 같은 값이다.
  static const _searchDebounce = Duration(milliseconds: 500);

  /// 한 번에 받는 검색 결과. 더 보면 [_searchMax]로 다시 받는다.
  static const _searchFirst = 20;
  static const _searchMax = 50;

  @override
  FriendState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const FriendState();
  }

  FriendRepository get _repo => ref.read(friendRepositoryProvider);

  /// 내 친구 목록을 받는다. 화면에 들어올 때 한 번.
  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final me = await _myUserId();
      if (me == null) {
        state = state.copyWith(
          loading: false,
          failure: FriendFailure.sessionExpired,
        );
        return;
      }
      final page = await _repo.friends(userId: me);
      state = state.copyWith(
        friends: page.items,
        friendCursor: page.nextCursor,
        loading: false,
      );
    } on FriendException catch (error) {
      state = state.copyWith(loading: false, failure: error.failure);
    }
  }

  /// 탭을 옮긴다. **추천은 처음 열 때만 받는다.**
  Future<void> selectTab(FriendTab tab) async {
    state = state.copyWith(tab: tab);
    if (tab != FriendTab.recommendations) return;
    if (state.recommendations.isNotEmpty) return;

    state = state.copyWith(loading: true);
    try {
      final list = await _repo.recommendations();
      state = state.copyWith(recommendations: list, loading: false);
    } on FriendException catch (error) {
      state = state.copyWith(loading: false, failure: error.failure);
    }
  }

  /// 검색어가 바뀌었다.
  ///
  /// ⚠️ **상태는 바로 바꾸고 조회만 미룬다.** 탭은 글자를 치는 즉시 접혀야
  /// 한다 — 0.5초 뒤에 접히면 화면이 늦게 따라오는 것으로 느껴진다.
  void onQuery(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    state = state.copyWith(query: trimmed);

    if (trimmed.isEmpty) {
      state = state.copyWith(results: const [], searchLimit: 0);
      return;
    }
    _debounce = Timer(_searchDebounce, () => _search(_searchFirst));
  }

  /// 바닥까지 읽었다. 친구 목록은 **커서로 이어 읽는다.**
  ///
  /// ⚠️ 검색과 달리 50에서 끊을 수 없다 — 내 친구 전부가 대상이다.
  Future<void> loadMoreFriends() async {
    if (state.searching || _loadingMore) return;
    final cursor = state.friendCursor;
    if (cursor == null) return;

    _loadingMore = true;
    try {
      final me = await _myUserId();
      if (me == null) return;
      final page = await _repo.friends(userId: me, cursor: cursor);
      state = state.copyWith(
        friends: [...state.friends, ...page.items],
        // ⚠️ 마지막 장이면 `null`로 **지워야** 한다. 남겨 두면 같은 커서로
        // 영영 다시 읽는다.
        friendCursor: page.nextCursor,
        clearFriendCursor: page.nextCursor == null,
      );
    } on FriendException catch (error) {
      state = state.copyWith(actionFailure: error.failure);
    } finally {
      _loadingMore = false;
    }
  }

  /// 프로필이 친구 수를 다시 읽었다. 표시를 지운다.
  ///
  /// ⚠️ **안 지우면** 한 번 바꾼 뒤로는 들여다보기만 해도 매번 다시 읽는다.
  void clearChanged() => state = state.copyWith(
    changed: false,
    clearChanged: true,
    failure: state.failure,
    actionFailure: state.actionFailure,
  );

  /// 바닥까지 읽었다. 같은 검색어로 50을 다시 받는다.
  ///
  /// ⚠️ **커서를 쓰지 않는다.** 페이지를 넘기는 사이 닉네임을 바꾼 사람이
  /// 빠지거나 두 번 오는 구간이 아예 없다(설계 §5).
  Future<void> loadMoreSearch() async {
    if (!state.searching || _loadingMore) return;
    // 이미 상한까지 받았거나, 첫 장을 다 못 채웠으면 더 볼 것이 없다.
    if (state.searchLimit >= _searchMax) return;
    if (state.results.length < state.searchLimit) return;
    _loadingMore = true;
    try {
      await _search(_searchMax);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _search(int limit) async {
    final query = state.query;
    if (query.isEmpty) return;

    try {
      final page = await _repo.search(query: query, limit: limit);
      // 기다리는 사이 검색어가 바뀌었으면 늦게 온 결과다. 버린다.
      if (state.query != query) return;
      state = state.copyWith(results: page.items, searchLimit: limit);
    } on FriendException catch (error) {
      state = state.copyWith(failure: error.failure);
    }
  }

  Future<void> request(String userId) =>
      _act(userId, () => _repo.request(userId));

  /// 수락한다. **그 줄을 친구 묶음 맨 위로 옮긴다.**
  Future<void> accept(String userId) =>
      _act(userId, () => _repo.accept(userId), toTop: true);

  /// 보낸 요청을 취소하거나 받은 요청을 거절한다.
  Future<void> cancel(String userId) => _act(userId, () async {
    await _repo.cancel(userId);
    return FriendRelation.none;
  });

  /// 친구를 끊는다.
  Future<void> remove(String userId) => _act(userId, () async {
    await _repo.remove(userId);
    return FriendRelation.none;
  });

  /// 한 줄을 서버에 보내고 돌아온 관계로 갈아끼운다.
  ///
  /// ⚠️ **같은 줄을 연달아 누르면 뒤의 것은 버린다.** 취소·거절·삭제는 멱등이
  /// 아니라, 두 번 나가면 둘째가 `404`로 돌아온다.
  Future<void> _act(
    String userId,
    Future<FriendRelation> Function() call, {
    bool toTop = false,
  }) async {
    if (state.pending.contains(userId)) return;
    state = state.copyWith(pending: {...state.pending, userId});

    try {
      final relation = await call();
      _replace(userId, relation, toTop: toTop);
      state = state.copyWith(changed: true);
    } on FriendException catch (error) {
      // ⚠️ **404면 그 줄을 관계 없음으로 되돌린다.** 이미 처리된 요청이다 —
      // 내가 누르는 사이 상대가 취소했거나, 연결이 끊겨 두 번 나갔다. 그대로
      // 두면 눌러도 계속 404다.
      if (error.failure == FriendFailure.notFound) {
        _replace(userId, FriendRelation.none);
      }
      state = state.copyWith(actionFailure: error.failure);
    } finally {
      // ⚠️ **실패를 함께 넘긴다.** `copyWith`의 `failure`는 `??`가 아니라
      // 넘기지 않으면 지워진다(성공했을 때 지우려고 그렇게 뒀다). 여기서
      // 빠뜨리면 방금 담은 404가 조용히 사라져 화면이 아무 말도 못 한다.
      state = state.copyWith(
        pending: {...state.pending}..remove(userId),
        failure: state.failure,
        actionFailure: state.actionFailure,
      );
    }
  }

  /// 세 목록 어디에 있든 그 사람의 관계를 바꾼다.
  void _replace(String userId, FriendRelation relation, {bool toTop = false}) {
    final friends = [
      for (final entry in state.friends)
        if (entry.userId == userId) entry.withRelation(relation) else entry,
    ];
    if (toTop) {
      final moved = friends.where((e) => e.userId == userId).toList();
      friends
        ..removeWhere((e) => e.userId == userId)
        ..insertAll(0, moved);
    }

    state = state.copyWith(
      friends: friends,
      results: [
        for (final entry in state.results)
          if (entry.userId == userId) entry.withRelation(relation) else entry,
      ],
      recommendations: [
        for (final item in state.recommendations)
          if (item.entry.userId == userId)
            FriendRecommendation(
              entry: item.entry.withRelation(relation),
              reason: item.reason,
            )
          else
            item,
      ],
      failure: state.failure,
      actionFailure: state.actionFailure,
    );
  }

  Future<String?> _myUserId() async =>
      (await ref.read(tokenStoreProvider).read()).userId;
}
