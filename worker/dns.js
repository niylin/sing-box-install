addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)

  // 只处理 /create_dns 路径
  if (url.pathname !== '/' + CREATE_PATH) {
    return new Response('Not Found', { status: 404 })
  }

  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  let data
  try {
    data = await request.json()
  } catch (err) {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400 })
  }

  const { domain, ip, enable_cdn } = data
  if (!domain || !ip) {
    return new Response(JSON.stringify({ error: 'domain 和 ip 必填' }), { status: 400 })
  }

  const recordType = getRecordType(ip)
  if (!recordType) {
    return new Response(JSON.stringify({ error: '无效 IP' }), { status: 400 })
  }

  const payload = {
    type: recordType,
    name: domain,
    content: ip,
    ttl: 120,
    proxied: enable_cdn
  }

  const urlApi = `https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records`

  try {
    const resp = await fetch(urlApi, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${API_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    })

    const result = await resp.json()
    if (!result.success) {
      return new Response(JSON.stringify({ error: '创建失败', details: result }), { status: 500 })
    }

    return new Response(JSON.stringify({ success: true, data: result.result }), {
      headers: { 'Content-Type': 'application/json' }
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: '请求 Cloudflare API 失败', details: err.message }), { status: 500 })
  }
}

function getRecordType(ip) {
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) return 'A'
  if (/^[0-9a-fA-F:]+$/.test(ip)) return 'AAAA'
  return null
}