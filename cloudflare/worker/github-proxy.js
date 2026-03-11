/**
 * Cloudflare Worker - GitHub Raw 内容代理
 *
 * 用途：加速 sing-box 规则集从 GitHub 的下载
 * 部署后将 sing-box 模板中的规则集 URL 替换为 Worker 地址
 *
 * 使用方式：
 *   原始 URL: https://raw.githubusercontent.com/{user}/{repo}/{branch}/{file}
 *   代理 URL: https://your-worker.workers.dev/{user}/{repo}/{branch}/{file}
 *
 * 示例：
 *   https://your-worker.workers.dev/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs
 */

const GITHUB_RAW = 'https://raw.githubusercontent.com';

// 允许代理的 GitHub 用户/组织白名单（留空则允许所有）
const ALLOWED_OWNERS = [
    'SagerNet',
];

export default {
    async fetch(request) {
        const url = new URL(request.url);
        const pathname = url.pathname;

        // 根路径返回使用说明
        if (pathname === '/' || pathname === '') {
            return new Response(
                'GitHub Raw Proxy\n\n' +
                'Usage: https://your-worker.workers.dev/{user}/{repo}/{branch}/{file}\n\n' +
                'Example:\n' +
                '  https://your-worker.workers.dev/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
                { headers: { 'Content-Type': 'text/plain' } }
            );
        }

        // 白名单检查
        if (ALLOWED_OWNERS.length > 0) {
            const owner = pathname.split('/')[1];
            if (!ALLOWED_OWNERS.includes(owner)) {
                return new Response('Forbidden', { status: 403 });
            }
        }

        // 转发请求到 GitHub Raw
        const githubUrl = GITHUB_RAW + pathname;
        const response = await fetch(githubUrl, {
            headers: {
                'User-Agent': request.headers.get('User-Agent') || 'sing-box',
            },
        });

        // 透传响应，附加 CORS 头
        const newHeaders = new Headers(response.headers);
        newHeaders.set('Access-Control-Allow-Origin', '*');
        newHeaders.set('Cache-Control', 'public, max-age=3600');

        return new Response(response.body, {
            status: response.status,
            headers: newHeaders,
        });
    },
};
