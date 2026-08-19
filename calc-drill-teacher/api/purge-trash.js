// Vercel Cron이 매일 호출하는 함수 — 휴지통(deleted_at)에 30일 넘게 있는 문제은행 문제를
// 그래프 이미지(Storage)까지 포함해서 영구 삭제합니다.
// 이 파일은 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 환경변수가 필요합니다.
// (service role 키는 Supabase 프로젝트 Settings > API 에서 확인할 수 있고, anon 키와 달리 RLS를 무시할 수 있는 민감한 키이므로
//  반드시 Vercel 환경변수로만 등록하고 코드에는 절대 넣지 마세요.)

module.exports = async function handler(req, res) {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    res.status(500).json({ error: 'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 환경변수가 설정되어 있지 않습니다.' });
    return;
  }

  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const headers = {
    'apikey': serviceKey,
    'authorization': `Bearer ${serviceKey}`,
    'content-type': 'application/json'
  };

  try {
    const listResp = await fetch(
      `${url}/rest/v1/bank_problems?select=id,image_url&deleted_at=lt.${encodeURIComponent(cutoff)}&deleted_at=not.is.null`,
      { headers }
    );
    const rows = await listResp.json();
    if (!Array.isArray(rows)) {
      res.status(500).json({ error: '휴지통 목록 조회 실패', detail: rows });
      return;
    }

    const images = rows.map(r => r.image_url).filter(Boolean).map(u => u.split('/bank_images/').pop()).filter(Boolean);
    if (images.length) {
      await fetch(`${url}/storage/v1/object/bank_images`, {
        method: 'DELETE',
        headers,
        body: JSON.stringify({ prefixes: images })
      });
    }

    if (rows.length) {
      const ids = rows.map(r => r.id);
      await fetch(`${url}/rest/v1/bank_problems?id=in.(${ids.join(',')})`, {
        method: 'DELETE',
        headers
      });
    }

    res.status(200).json({ purged: rows.length });
  } catch (e) {
    res.status(500).json({ error: '서버 오류: ' + e.message });
  }
}
