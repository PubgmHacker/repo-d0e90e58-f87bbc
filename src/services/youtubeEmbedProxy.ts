// GET /api/media/youtube-embed?id=VIDEO_ID — Full Embed Page Proxy (v12)
//
// v12 approach: backend fetches the ENTIRE youtube.com/embed/ page,
// rewrites relative URLs to absolute, and serves it to iOS WKWebView.
//
// Why this works where v11 failed:
//   v11: our HTML → IFrame API creates iframe to youtube.com → WKWebView
//        loads iframe → YouTube bot-checks the iframe request → "Sign in"
//   v12: backend fetches embed page from YouTube (Railway IP) → serves
//        HTML to WKWebView → player JS runs directly in the page → NO
//        iframe request from WKWebView → NO bot check
//
// The only youtube.com requests from WKWebView are static JS/CSS files
// (player JS, CSS) which YouTube doesn't bot-check. Video data comes from
// googlevideo.com CDN (also not bot-checked).

export async function proxyYouTubeEmbed(videoId: string): Promise<string> {
  const embedUrl = `https://www.youtube.com/embed/${videoId}?playsinline=1&rel=0&modestbranding=1&iv_load_policy=3`;
  
  const response = await fetch(embedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });

  if (!response.ok) {
    throw new Error(`YouTube embed fetch failed: ${response.status}`);
  }

  let html = await response.text();

  // Rewrite relative URLs to absolute (YouTube uses // and / relative paths)
  html = html.replace(/href="\//g, 'href="https://www.youtube.com/');
  html = html.replace(/src="\//g, 'src="https://www.youtube.com/');
  html = html.replace(/href="\/\//g, 'href="https://');
  html = html.replace(/src="\/\//g, 'src="https://');
  
  // Rewrite CSS url() references
  html = html.replace(/url\(\//g, 'url(https://www.youtube.com/');
  html = html.replace(/url\(\/\//g, 'url(https://');

  // Add a base tag to handle any remaining relative URLs
  html = html.replace('<head>', '<head><base href="https://www.youtube.com/">');

  // Add viewport meta for mobile
  if (!html.includes('name="viewport"')) {
    html = html.replace('<head>', '<head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">');
  }

  return html;
}
