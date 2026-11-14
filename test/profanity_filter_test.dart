import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/utils/profanity_filter.dart';

/// 비속어 마스킹.
///
/// ## ⚠️ 오탐이 미탐보다 나쁘다
///
/// 못 잡은 욕 한 개는 불쾌하지만, **잘못 가린 정상어 한 개는 기능을 망친다.**
/// 대기방에서 "시간 맞춰 갈게요"가 "** 맞춰 갈게요"로 보이면 아무도 이 필터를
/// 신뢰하지 않는다. 그래서 아래 '가리지 않는다' 묶음이 이 파일의 본체다.
///
/// 목록을 늘릴 때는 **반드시 그 단어를 넣은 채로 이 묶음을 다시 돌린다.**
void main() {
  group('가린다', () {
    test('번들 사전의 기본형과 우회 표기', () {
      // 숫자 삽입과 공백 우회는 패키지의 정규화가 처리한다.
      expect(maskProfanity('시발'), '**');
      expect(maskProfanity('씨발 진짜'), '** 진짜');
      expect(maskProfanity('시1발'), '***');
      expect(maskProfanity('아 씨 발'), '아 ***');
      expect(maskProfanity('병신같네'), '**같네');
    });

    test('우리가 보강한 단어 — 번들에는 없다', () {
      // 전부 번들이 못 잡던 것들이다. 보강이 실제로 먹는지 본다.
      expect(maskProfanity('좆'), '*');
      expect(maskProfanity('지랄하네'), '**하네');
      expect(maskProfanity('니애미'), '***');
      expect(maskProfanity('개색기'), '***');
      expect(maskProfanity('shit'), '****');
      expect(maskProfanity('asshole'), '*******');
    });

    test('존나 — 실측 미탐 1위였다', () {
      // 2runo 코퍼스의 욕설 문장에서 못 잡은 토큰 중 76회로 가장 많았고,
      // 정상어와 부딪히지 않는 것을 확인했다('존맛'·'존버'·'존재감' 안전).
      expect(maskProfanity('존나'), '**');
      expect(maskProfanity('존나 빠르네'), '** 빠르네');
    });

    test('보강한 단어도 정규화를 상속한다', () {
      // addedWords로 넣은 단어에도 숫자·공백 우회 처리가 따라붙는다.
      // 이것이 성립하지 않으면 단어를 넣는 전략 자체가 무너진다.
      expect(maskProfanity('좆1'), isNot(contains('좆')));
      expect(maskProfanity('니 애미'), isNot(contains('애미')));
      expect(maskProfanity('개색1기'), isNot(contains('색')));
    });

    test('초성 표기', () {
      expect(maskProfanity('ㅈㄹ'), '**');
      expect(maskProfanity('이 ㅄ아'), '이 *아');
      expect(maskProfanity('ㅈㄴ 빠르네'), '** 빠르네');
    });

    test('⚠️ 제로폭 공백 우회를 막는다', () {
      // U+200B를 끼우면 패키지 정규화는 통과한다. 미리 걷어내야 한다.
      expect(maskProfanity('시​발'), isNot(contains('발')));
      expect(maskProfanity('씨﻿발'), isNot(contains('발')));
    });
  });

  group('⚠️ 가리지 않는다', () {
    test('대기방에서 실제로 나올 말', () {
      const sentences = [
        '안녕하세요 오늘 잘 부탁드려요',
        '화이팅입니다',
        '곧 출발해요',
        '출발 5분 전이에요',
        '시간 맞춰 갈게요',
        '조금 늦을 것 같아요',
        '5km 목표로 뛸게요',
        '날씨 좋네요',
        '페이스는 6분대로 갈게요',
        '무릎 조심하세요',
        '물 챙기세요',
        '첫 러닝이라 긴장되네요',
        '천천히 가요',
        '수고하셨어요',
        '다음에 또 같이해요',
      ];

      for (final sentence in sentences) {
        expect(maskProfanity(sentence), sentence, reason: sentence);
      }
    });

    test('⚠️ 번들이 틀리게 잡던 말 — ignoreWords로 끈다', () {
      // 번들 사전은 始發點을 욕으로 본다. 러닝 앱에서 쓰는 말이라 꺼야 한다.
      expect(maskProfanity('시발점이 어디예요'), '시발점이 어디예요');
      expect(maskProfanity('시험 발표 끝났어요'), '시험 발표 끝났어요');
    });

    test('⚠️ 동사 활용이 욕과 겹치는 말', () {
      // '보지'·'자지'를 목록에 넣으면 전부 깨진다. 그래서 넣지 않았다.
      expect(maskProfanity('지도 보지 못했어요'), '지도 보지 못했어요');
      expect(maskProfanity('아직 안 자지요'), '아직 안 자지요');
    });

    test('⚠️ 초성 약어와 감탄 표현', () {
      // 'ㅗ'를 목록에 넣으면 'ㅗㅜㅑ'가 '*ㅜㅑ'가 된다. 그래서 빼기로 했다.
      const chatter = ['ㅎㅎ', 'ㅋㅋ', 'ㅇㅇ', 'ㄴㄴ', 'ㅅㄱ', 'ㅎㅇ', 'ㅠㅠ', 'ㅗㅜㅑ'];

      for (final one in chatter) {
        expect(maskProfanity(one), one, reason: one);
      }
    });

    test('⚠️ 짧은 단어가 어절 경계를 넘지 않는다', () {
      // ## 2026-11-11 실측에서 나온 회귀다
      //
      // 정규화가 공백을 접기 때문에 **두 글자 단어는 어절을 넘어 매칭된다.**
      // `니미`를 넣었더니 "했으**니 미**련"이 걸렸다 — "~니 미~"는 한국어에서
      // 아주 흔한 꼴이라 치명적이었다. 그래서 아래 네 단어를 뺐다.
      //
      // 두 글자 단어를 새로 넣을 때는 **반드시 이 꼴을 먼저 찾아봐야 한다.**
      const sentences = [
        '했으니 미련 없다', // 니미
        '그러니 미리 준비해요', // 니미
        '오니 미안해요', // 니미
        '호모사피엔스', // 호모
        '등신대 사진', // 등신
        '고등신학교', // 등신
        '돌을 쪼다', // 쪼다
      ];

      for (final sentence in sentences) {
        expect(maskProfanity(sentence), sentence, reason: sentence);
      }
    });

    test('⚠️ 영어 단어 안에 숨은 글자 (Scunthorpe 문제)', () {
      // 'cunt'·'dick'을 목록에 넣으면 아래 두 개가 깨진다. 그래서 넣지 않았다.
      const words = [
        'class is over',
        'passage',
        'assassin',
        'bass guitar',
        'Scunthorpe',
        'Dickens novel',
        'document',
        'shell script',
        'hello everyone',
        'analysis',
        'grass',
      ];

      for (final word in words) {
        expect(maskProfanity(word), word, reason: word);
      }
    });
  });

  group('모양을 지킨다', () {
    test('빈 입력과 공백은 그대로', () {
      expect(maskProfanity(''), '');
      expect(maskProfanity('   '), '   ');
      expect(maskProfanity('\n'), '\n');
    });

    test('⚠️ 이모지를 깨뜨리지 않는다', () {
      // 🏃‍♂️는 ZWJ(U+200D)로 이어 붙인 한 글자다. 제로폭을 몽땅 걷어내면
      // 달리는 사람이 둘로 쪼개진다. 그래서 ZWJ만 남긴다.
      expect(maskProfanity('🏃‍♂️💨'), '🏃‍♂️💨');
      expect(maskProfanity('오늘 화이팅 🏃‍♂️'), '오늘 화이팅 🏃‍♂️');
    });

    test('⚠️ 필터를 만드는 것 자체가 터지지 않는다', () {
      // 번들에 이미 있는 단어를 addedWords에 넣으면 생성자가 ArgumentError를
      // 던진다. 필터는 첫 메시지를 그릴 때 만들어지므로, 목록에 중복이 들어오면
      // **채팅 화면이 열리다 죽는다.** 목록을 늘릴 때 이 테스트가 막아 준다.
      expect(() => maskProfanity('아무 말'), returnsNormally);
    });
  });
}
