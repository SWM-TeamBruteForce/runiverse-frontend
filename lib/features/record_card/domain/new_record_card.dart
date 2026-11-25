import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 올릴 사진 한 장. **이미 9:16으로 잘린 것이다.**
///
/// ## ⚠️ 원본이 아니라 자른 결과를 올린다
///
/// 설계 6-3이 못 박았다 — 원본을 그대로 올리면 **AI가 보는 그림과 사람이 본
/// 그림이 달라진다.** 자르는 일은 `data`의 몫이라(`dart:io`가 필요하다) 이
/// 값에 닿을 때는 이미 끝나 있다.
class NewCardPhoto {
  const NewCardPhoto({
    required this.path,
    required this.thumbnailPath,
    this.caption,
  });

  /// 9:16으로 자른 파일.
  final String path;

  /// 긴 변 320px. **못 만들었으면 `null`이다** — 썸네일이 없어도 카드는 산다.
  final String? thumbnailPath;

  /// 이 사진에 붙인 한마디. 안 썼으면 `null`이다.
  final String? caption;
}

/// 만들어 달라고 보내는 카드 하나.
///
/// ## ⚠️ 러닝 기록을 통째로 든다
///
/// 서버가 생기면 `runningRecordId`만 보내면 되지만, 지금은 가짜가 **지표와
/// 시작 시각을 여기서 읽어** 카드를 짓는다. 카드가 지표·경로를 스스로 들고
/// 있어야 하는 이유는 설계 3절에 있다.
class NewRecordCard {
  const NewRecordCard({
    required this.record,
    required this.route,
    required this.activity,
    required this.visibility,
    required this.reviewText,
    required this.photos,
    required this.musicEnabled,
  });

  final RunRecord record;

  /// 선 아트. **경로가 없는 러닝이면 [RouteArt.empty]다** — 트레드밀이다.
  final RouteArt route;

  final RecordCardActivity activity;
  final RecordCardVisibility visibility;
  final String reviewText;

  /// 최대 다섯 장. 없을 수 있다.
  final List<NewCardPhoto> photos;

  /// AI 음악을 만들까. 서버가 이 값으로 생성 요청을 건다.
  final bool musicEnabled;
}
