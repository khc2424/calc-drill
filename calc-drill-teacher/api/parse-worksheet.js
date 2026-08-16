// Vercel 서버리스 함수 — PDF를 Claude API로 분석해서 학습지 문항을 자동 추출합니다.
// 이 파일은 브라우저가 아니라 Vercel 서버에서만 실행되므로, 여기서만 API 키를 사용합니다.
// (API 키는 Vercel 프로젝트의 환경변수 ANTHROPIC_API_KEY 로 설정하세요. 코드에 직접 넣지 마세요.)

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

  const { pdfBase64 } = req.body || {};
  if (!pdfBase64) {
    res.status(400).json({ error: 'PDF 데이터가 없습니다.' });
    return;
  }

  const prompt = `다음 PDF는 수학 학습지의 문제와 정답입니다. 각 문항을 분석해서 아래 형식의 순수 JSON 객체 하나만 출력하세요. 설명, 마크다운 코드블록 없이 JSON만 출력하세요.

형식:
{"questions":[{"question_no":1,"type":"mc","correct_choice":3},{"question_no":2,"type":"short","correct_value":"3/4"}]}

규칙:
- type은 5지선다 객관식이면 "mc", 주관식(값을 직접 입력하는 문제)이면 "short"
- mc인 경우 correct_choice에 1~5 중 정답 번호(숫자)만 넣기
- short인 경우 correct_value에 정답 값을 문자열로 넣기 (분수는 a/b 형태, 근호는 sqrt(x) 형태, 파이는 pi, 자연상수는 e, 무한대는 inf, 절댓값은 |x| 형태로 표기)
- question_no는 1부터 문제 순서대로
- 정답을 확실히 알 수 없는 문항은 결과에서 제외
- 문제 본문 텍스트는 포함하지 말고 번호/유형/정답만 출력`;

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'pdfs-2024-09-25'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 4096,
        messages: [{
          role: 'user',
          content: [
            { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdfBase64 } },
            { type: 'text', text: prompt }
          ]
        }]
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
      res.status(500).json({ error: 'AI 응답을 JSON으로 해석하지 못했습니다. 다시 시도하거나 수동으로 입력해주세요.', raw });
      return;
    }

    if (!parsed || !Array.isArray(parsed.questions)) {
      res.status(500).json({ error: 'AI 응답 형식이 올바르지 않습니다.', raw });
      return;
    }

    res.status(200).json(parsed);
  } catch (e) {
    res.status(500).json({ error: '서버 오류: ' + e.message });
  }
}
