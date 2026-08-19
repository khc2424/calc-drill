// Vercel 서버리스 함수 — 문제은행용 PDF를 Claude API로 분석해서
// 문항별 "지문 텍스트 + 정답 + 난이도 추정 + 그래프 포함 여부/페이지"를 추출합니다.
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

  const { pdfBase64 } = req.body || {};
  if (!pdfBase64) {
    res.status(400).json({ error: 'PDF 데이터가 없습니다.' });
    return;
  }

  const prompt = `다음 PDF는 수학 문제 모음입니다. 각 문항을 분석해서 아래 형식의 순수 JSON 객체 하나만 출력하세요. 설명, 마크다운 코드블록 없이 JSON만 출력하세요.

형식:
{"questions":[{"question_no":1,"content_text":"함수 f(x)=x^2+1 에서 f(2)의 값은?","type":"mc","correct_choice":3,"difficulty":"중","has_graph":false,"page":1},{"question_no":2,"content_text":"그림과 같은 그래프에서...","type":"short","correct_value":"3/4","difficulty":"상","has_graph":true,"page":1}]}

규칙:
- content_text에는 문항의 지문(질문 텍스트) 전체를 그대로 옮겨 적기. 수식은 LaTeX로 표기하고 인라인은 $...$ 로 감싸기 (예: $x^2+1$). 그래프/그림 자체는 옮기지 말고 "그림 참조"처럼 짧게만 언급.
- type은 5지선다 객관식이면 "mc", 주관식(값을 직접 입력하는 문제)이면 "short"
- mc인 경우 correct_choice에 1~5 중 정답 번호(숫자)만 넣기
- short인 경우 correct_value에는 학생이 실제로 입력해야 하는 핵심 값만 넣기 (분수는 a/b 형태, 근호는 sqrt(x), 파이는 pi, 자연상수는 e, 무한대는 inf, 절댓값은 |x| 형태로 표기). 정답에 고정된 접두/접미 문구가 붙는 경우(예: "제3사분면", "150m") answer_prefix/answer_suffix에 넣고 correct_value에는 핵심 값만 남기기.
- difficulty는 문제 난이도를 "상"/"중"/"하" 중 하나로 추정
- has_graph는 이 문항에 그래프나 도형 그림이 포함되어 있으면 true, 순수 텍스트/수식 문제면 false
- page는 이 문항이 PDF의 몇 번째 페이지에 있는지 (1부터 시작)
- question_no는 1부터 문제 순서대로
- 정답을 확실히 알 수 없는 문항은 제외하지 말고 포함하되 correct_choice/correct_value를 비워두기`;

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
        max_tokens: 8192,
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
