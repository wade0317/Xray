/**
 * Cloudflare Worker - GitHub Raw 内容代理（带边缘缓存）
 *
 * 用途：加速 sing-box 规则集从 GitHub 的下载
 * 部署后将 sing-box 模板中的规则集 URL 替换为 Worker 地址
 *
 * 使用方式：
 *   原始 URL: https://raw.githubusercontent.com/{user}/{repo}/{branch}/{file}
 *   代理 URL: https://your-worker.workers.dev/{user}/{repo}/{branch}/{file}
 */

const GITHUB_RAW = 'https://raw.githubusercontent.com';

// 允许代理的 GitHub 用户/组织白名单（留空则允许所有）
const ALLOWED_OWNERS = [
    'SagerNet',
];

// 边缘缓存 TTL（秒）。规则集更新很慢，7 天足够
const EDGE_CACHE_TTL = 7 * 24 * 3600;

// 客户端缓存 TTL（秒）
const CLIENT_CACHE_TTL = 24 * 3600;

export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);
        const pathname = url.pathname;

        if (pathname === '/' || pathname === '') {
            return new Response(
                'GitHub Raw Proxy\n\n' +
                'Usage: https://your-worker.workers.dev/{user}/{repo}/{branch}/{file}\n',
                { headers: { 'Content-Type': 'text/plain' } }
            );
        }

        if (ALLOWED_OWNERS.length > 0) {
            const owner = pathname.split('/')[1];
            if (!ALLOWED_OWNERS.includes(owner)) {
                return new Response('Forbidden', { status: 403 });
            }
        }

        // 用 URL 作为缓存 key，仅按 GET 缓存
        const cacheKey = new Request(url.toString(), { method: 'GET' });
        const cache = caches.default;

        let response = await cache.match(cacheKey);
        if (response) {
            const hit = new Response(response.body, response);
            hit.headers.set('X-Cache', 'HIT');
            return hit;
        }

        // 回源 GitHub Raw
        const githubUrl = GITHUB_RAW + pathname;
        const upstream = await fetch(githubUrl, {
            headers: {
                'User-Agent': request.headers.get('User-Agent') || 'sing-box',
            },
            // 让 CF 自身在出站方向也做一次缓存
            cf: {
                cacheTtl: EDGE_CACHE_TTL,
                cacheEverything: true,
            },
        });

        // 只缓存成功响应
        if (!upstream.ok) {
            return new Response(upstream.body, {
                status: upstream.status,
                headers: { 'Content-Type': 'text/plain' },
            });
        }

        // 重写响应头，写入边缘缓存
        const headers = new Headers(upstream.headers);
        headers.set('Access-Control-Allow-Origin', '*');
        headers.set('Cache-Control', `public, max-age=${CLIENT_CACHE_TTL}, s-maxage=${EDGE_CACHE_TTL}`);
        headers.set('X-Cache', 'MISS');
        headers.delete('Set-Cookie');

        response = new Response(upstream.body, {
            status: upstream.status,
            headers,
        });

        ctx.waitUntil(cache.put(cacheKey, response.clone()));
        return response;
    },
};
