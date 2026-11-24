import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:runiverse/features/record_card/domain/card_audio_player.dart';

/// [CardAudioPlayer]를 `just_audio`로 구현한 것.
///
/// ## ⚠️ 반복은 플레이어에 맡긴다
///
/// 끝 신호를 받아 다시 트는 대신 [LoopMode.one]을 건다. 받아서 다시 틀면
/// 곡과 곡 사이에 빈 틈이 생기고, 그 틈에 장을 넘기면 두 번 튼다.
///
/// ## ⚠️ 포커스를 여기서 막지 않는다
///
/// `just_audio`의 `play()`는 **오디오 포커스를 가져간다** — 남이 듣던 음악이
/// 멈춘다. 자동 재생을 접을지는 **부르는 쪽**이 [otherAudioPlaying]으로 먼저
/// 가린다(설계 6-2). 여기서 막으면 사람이 직접 누른 `재생`까지 막힌다.
class JustAudioPlayer implements CardAudioPlayer {
  final _player = AudioPlayer();

  /// 반복을 걸어 뒀나. **곡마다 다시 걸 필요는 없다.**
  var _looping = false;

  @override
  Future<void> load(String url) async {
    // ⚠️ **기다려서 건다.** 생성자에서 던져 두면 실패해도 아무도 모르고,
    // 그러면 이 기능의 핵심인 반복이 조용히 빠진다.
    if (!_looping) {
      await _player.setLoopMode(LoopMode.one);
      _looping = true;
    }
    // ⚠️ **주소를 로그에 남기지 않는다.** 서명이 붙어 있다. 예외도 그대로
    // 올려 보내고 메시지에 주소를 붙이지 않는다.
    await _player.setUrl(url);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  /// ⚠️ **안드로이드 전용 채널이다.** 다른 플랫폼에서 부르면 터진다 — iOS는
  /// 이번 범위 밖이라(설계 3절) 묻지 않고 `false`를 낸다.
  @override
  Future<bool> otherAudioPlaying() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return AndroidAudioManager().isMusicActive();
  }

  @override
  Future<void> dispose() => _player.dispose();
}
