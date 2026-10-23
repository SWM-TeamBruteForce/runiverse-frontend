import 'package:runiverse/features/session/domain/step_repository.dart';

/// 케이던스 계산 — 순수 함수만 있다.
///
/// **케이던스는 분당 걸음 수(spm)다.** 러너는 대개 150~190 사이고, 180 근처가
/// 부상이 적다고 알려져 있다. 페이스와 함께 보면 "보폭을 늘렸나 회전을
/// 올렸나"를 알 수 있다.
///
/// ## 창으로 평균을 낸다
///
/// 걸음 표본은 **부팅 이후 누적값**이라 두 표본의 차이로만 뜻이 생긴다
/// ([StepSample]). 게다가 안드로이드가 이벤트를 묶어 보내 몇 초씩 몰려 오기도
/// 해서, 인접한 두 표본만 보면 값이 요동친다.
///
/// 그래서 [window] 안의 처음과 마지막을 보고 평균을 낸다. 페이스와 같은 30초다 —
/// 두 수치가 같은 구간을 말해야 화면이 한 이야기를 한다.
abstract final class CadenceCalculator {
  /// 사람이 낼 수 있는 값의 위아래.
  ///
  /// 센서가 튀거나 창이 어긋나면 300spm 같은 값이 나온다. **그런 값은 내지
  /// 않는다** — 틀린 숫자를 보여주는 것보다 `--`가 낫다.
  static const _minSpm = 30;
  static const _maxSpm = 260;

  /// 평균을 내기 위한 최소 시간. 이보다 짧으면 표본이 모자라다.
  static const _minSpan = Duration(seconds: 5);

  /// 최근 [window] 동안의 케이던스(spm). **낼 수 없으면 `null`이다.**
  ///
  /// 표본이 둘 미만이거나, 창이 [_minSpan]보다 짧거나, 사람이 낼 수 없는
  /// 값이면 `null`이다. 화면은 그것을 `--`로 그린다.
  static int? recent(
    List<StepSample> samples, {
    Duration window = const Duration(seconds: 30),
  }) {
    if (samples.length < 2) return null;

    final last = samples.last;
    final from = last.at.subtract(window);

    // 창 안에 들어오는 첫 표본을 찾는다. 하나도 없으면 마지막 둘만 본다.
    var start = samples[samples.length - 2];
    for (final sample in samples) {
      if (!sample.at.isBefore(from)) {
        start = sample;
        break;
      }
    }

    final span = last.at.difference(start.at);
    if (span < _minSpan) return null;

    final steps = last.steps - start.steps;
    // ⚠️ 음수가 나올 수 있다. 기기를 재부팅하면 누적값이 0으로 돌아간다.
    if (steps <= 0) return null;

    final spm = (steps / (span.inMilliseconds / 60000)).round();
    if (spm < _minSpm || spm > _maxSpm) return null;
    return spm;
  }

  /// 창을 벗어난 오래된 표본을 버린다.
  ///
  /// 안 버리면 30분 러닝에서 표본이 계속 쌓인다. 창 하나만큼은 남겨야
  /// 다음 계산이 시작점을 찾을 수 있어, **경계 바로 바깥 것 하나까지** 둔다.
  static List<StepSample> trimmed(
    List<StepSample> samples, {
    Duration window = const Duration(seconds: 30),
  }) {
    if (samples.length < 2) return samples;

    final from = samples.last.at.subtract(window);
    // 창 안에 드는 첫 표본의 **바로 앞**부터 남긴다.
    var keepFrom = 0;
    for (var i = 0; i < samples.length; i++) {
      if (!samples[i].at.isBefore(from)) {
        keepFrom = i == 0 ? 0 : i - 1;
        break;
      }
      keepFrom = i;
    }
    return samples.sublist(keepFrom);
  }
}
