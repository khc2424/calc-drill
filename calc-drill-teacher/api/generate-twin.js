// Vercel 서버리스 함수 — 문제은행의 원본 문제 하나를 받아 "쌍둥이(변형) 문제"를 자동 생성합니다.
// 구조/유형/난이도는 그대로 유지하고 숫자(조건)만 바꾼 뒤, AI가 스스로 정답을 계산하고 검산까지 한 결과를 돌려줍니다.
// 검수(승인/반려)는 항상 선생님이 문제은행 화면에서 직접 합니다 — 이 함수는 초안만 만듭니다.
// (API 키는 Vercel 프로젝트의 환경변수 ANTHROPIC_API_KEY 로 설정하세요. parse-worksheet.js와 동일한 키를 씁니다.)

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'POST 요청만 지원합니다.' });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: '서버에 ANTHROPIC_API_KEY가 설정되어 있지 않습니다. Vercel 프로젝트 Settings > Environment Variables에서 추가해주세요.' });
    return;
  }

  const { content_text, type, correct_choice, correct_value, answer_prefix, answer_suffix, difficulty } = req.body || {};
  if (!content_text) {
    res.status(400).json({ error: '원본 문제 지문이 없습니다.' });
    return;
  }

  const origAnswer = type === 'mc'
    ? `${correct_choice}번`
    : `${answer_prefix || ''}${correct_value || ''}${answer_suffix || ''}`;

  const prompt = `너는 수학 문제 출제 보조야. 아래 원본 문제와 구조/난이도는 완전히 같지만, 숫자나 조건만 바꾼 "쌍둥이(변형) 문제"를 하나 만들어야 해. 학생이 답을 외워서 풀 수 없도록 원본과 겹치지 않는 새 숫자를 써야 해.

[원본 문제]
${content_text}

[원본 정답]
${origAnswer}

[문제 유형]
${type === 'mc' ? '5지선다 객관식' : '주관식'}

[난이도]
${difficulty || '중'}

작업 순서:
1. 원본 문제의 구조(어떤 개념을 묻는지, 몇 단계 계산인지)를 그대로 유지하되 숫자/조건만 바꿔서 새 문제를 만든다.
2. 새 문제의 정답을 스스로 계산한다.
3. 계산을 처음부터 다시 검산해서 정답이 맞는지 재확인한다. (자체 검증)
4. 객관식이면 그럴듯한 오답 4개도 함께 만든다 (실수하기 쉬운 값들로).

아래 형식의 순수 JSON 객체 하나만 출력하고, 설명이나 마크다운 코드블록은 쓰지 마.

형식(객관식 예):
{"content_text":"...(LaTeX는 $...$ 로 감싸기)...","type":"mc","correct_choice":2,"choices":["오답1","정답과 같은 자리(정답)","오답2","오답3","오답4"],"verified":true}

형식(주관식 예):
{"content_text":"...","type":"short","correct_value":"7/2","answer_prefix":"","answer_suffix":"","verified":true}

규칙:
- content_text는 완전한 새 문제 지문 (원본과 숫자/조건이 달라야 함, 수식은 $...$ LaTeX)
- type은 원본과 동일하게 유지
- verified는 네가 검산을 실제로 마쳤으면 true, 확신이 없으면 false`;

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 2048,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    const data = await resp.json();
    if (!resp.ok) {
      res.status(500).json({ error: 'Claude API 오류: ' + (data?.error?.message || resp.status) });
      return;
    }

    const textBlock = (data.content || []).find(c => c.type === 'text');
    let raw = textBlock ? textBlock.text : '';
    raw = raw.trim().replace(/^```json/i, '').replace(/^```/, '').replace(/```$/, '').trim();

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      res.status(500).json({ error: 'AI 응답을 JSON으로 해석하지 못했습니다. 다시 시도해주세요.', raw });
      return;
    }

    if (!parsed || !parsed.content_text) {
      res.status(500).json({ error: 'AI 응답 형식이 올바르지 않습니다.', raw });
      return;
    }

    res.status(200).json(parsed);
  } catch (e) {
    res.status(500).json({ error: '서버 오류: ' + e.message });
  }
}
