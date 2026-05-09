"""
Kazumi Video Scraper Server
服务器代理 - 用于抓取视频 URL，解决 tvOS 无法执行 JavaScript 的问题

使用方法:
    pip install -r requirements.txt
    playwright install chromium  # 安装浏览器
    python server.py
"""

from flask import Flask, request, jsonify, Response, stream_with_context
import requests
from bs4 import BeautifulSoup
from contextlib import suppress
import re
import logging
import argparse
import os
import random
import threading
from urllib.parse import parse_qs, quote, unquote, urljoin, urlparse, urlencode

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
PLAYLIST_CACHE = {}
RULE_REPOSITORY_BASE_URLS = [
    "https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
    "https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/",
]


def positive_int_env(name: str, default: int) -> int:
    try:
        return max(1, int(os.environ.get(name, str(default))))
    except ValueError:
        return default


MAX_PLAYWRIGHT_JOBS = positive_int_env("KAZUMI_MAX_PLAYWRIGHT_JOBS", 1)
PLAYWRIGHT_SEMAPHORE = threading.BoundedSemaphore(MAX_PLAYWRIGHT_JOBS)

# 默认请求头
KAZUMI_USER_AGENTS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0",
]

ACCEPT_LANGUAGES = [
    "zh-CN,zh;q=0.9",
    "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
    "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
]

DEFAULT_HEADERS = {
    "User-Agent": KAZUMI_USER_AGENTS[0],
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": ACCEPT_LANGUAGES[0],
}


def pick_kazumi_user_agent() -> str:
    return random.choice(KAZUMI_USER_AGENTS)


def pick_accept_language() -> str:
    return random.choice(ACCEPT_LANGUAGES)


@app.route("/health")
def health():
    """健康检查"""
    return jsonify({"status": "ok"})


@app.route("/scrape", methods=["GET"])
def scrape_video():
    """
    抓取视频 URL (使用 Playwright 渲染)
    参数:
        url: 目标页面 URL
        plugin: 插件名称 (可选)
    """
    url = request.args.get("url")
    plugin = request.args.get("plugin", "default")

    if not url:
        return jsonify({"error": "缺少 url 参数"}), 400

    try:
        logger.info(f"正在抓取: {url} (插件: {plugin})")

        if not PLAYWRIGHT_SEMAPHORE.acquire(blocking=False):
            return jsonify({
                "success": False,
                "error": "服务器正忙，已有视频抓取任务正在运行，请稍后重试"
            }), 503

        # 使用 Playwright 渲染抓取，保持客户端选择的播放线路。
        try:
            result = scrape_selected_line(url, plugin)
        finally:
            PLAYWRIGHT_SEMAPHORE.release()

        if result:
            return jsonify({
                "success": True,
                "url": result["url"],
                "quality": result.get("quality", "默认"),
                "plugin": plugin,
                "referer": result.get("referer") or result.get("source_page"),
                "source_page": result.get("source_page")
            })
        else:
            return jsonify({
                "success": False,
                "error": "未找到视频源"
            }), 404

    except Exception as e:
        logger.error(f"抓取失败: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route("/scrape_js", methods=["GET"])
def scrape_video_js():
    """
    使用浏览器 JavaScript 渲染抓取视频 URL (备用接口)
    """
    url = request.args.get("url")

    if not url:
        return jsonify({"error": "缺少 url 参数"}), 400

    try:
        if not PLAYWRIGHT_SEMAPHORE.acquire(blocking=False):
            return jsonify({
                "success": False,
                "error": "服务器正忙，已有视频抓取任务正在运行，请稍后重试"
            }), 503

        try:
            result = scrape_selected_line(url, "default")
        finally:
            PLAYWRIGHT_SEMAPHORE.release()

        if result:
            return jsonify({
                "success": True,
                "url": result["url"],
                "referer": result.get("referer") or result.get("source_page"),
                "source_page": result.get("source_page"),
                "type": "m3u8" if "m3u8" in result["url"] else "mp4"
            })
        else:
            return jsonify({
                "success": False,
                "error": "未找到视频"
            }), 404

    except ImportError as e:
        return jsonify({
            "success": False,
            "error": f"playwright 未安装: {e}"
        }), 500
    except Exception as e:
        logger.error(f"浏览器渲染失败: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route("/rules/index", methods=["GET"])
def proxy_rule_index():
    """代理 Kazumi 规则仓库索引，给真机规避 GitHub raw 直连失败。"""
    return proxy_rule_repository_file("index.json")


@app.route("/rules/plugin", methods=["GET"])
def proxy_rule_plugin():
    """代理 Kazumi 单条规则 JSON。"""
    name = request.args.get("name", "").strip()
    if not name:
        return jsonify({"error": "缺少 name 参数"}), 400

    file_name = f"{quote(name, safe='')}.json"
    return proxy_rule_repository_file(file_name)


def proxy_rule_repository_file(file_name: str):
    last_error = None
    for base_url in RULE_REPOSITORY_BASE_URLS:
        target_url = base_url + file_name
        try:
            response = requests.get(
                target_url,
                headers=build_rule_repository_headers(),
                timeout=25,
                verify=False,
            )
            if response.status_code < 400:
                logger.info(f"规则仓库代理成功: {target_url}")
                return Response(
                    response.content,
                    status=response.status_code,
                    content_type="application/json; charset=utf-8",
                    headers={"Cache-Control": "no-cache"},
                )

            last_error = f"HTTP {response.status_code}"
            logger.warning(f"规则仓库代理失败[{response.status_code}]: {target_url}")
        except Exception as e:
            last_error = str(e)
            logger.warning(f"规则仓库代理异常: {target_url} - {e}")

    return jsonify({
        "error": f"规则仓库请求失败: {file_name}",
        "detail": last_error,
    }), 502


def build_rule_repository_headers() -> dict:
    return {
        "User-Agent": DEFAULT_HEADERS["User-Agent"],
        "Accept": "application/json,text/plain,*/*",
        "Accept-Language": DEFAULT_HEADERS["Accept-Language"],
        "Cache-Control": "no-cache",
    }


def scrape_selected_line(url: str, plugin: str) -> dict:
    """解析视频，服务端不擅自切换客户端选择的线路。"""
    result = scrape_with_playwright(url)
    if result:
        result["source_page"] = url
    return result


@app.route("/proxy/m3u8", methods=["GET"])
def proxy_m3u8():
    """代理并重写 HLS playlist，让 tvOS 只访问本地服务器。"""
    remote_url = request.args.get("url")
    referer = request.args.get("referer", "")
    source_page = request.args.get("source_page", "")

    if not remote_url:
        return jsonify({"error": "缺少 url 参数"}), 400

    try:
        original_remote_url = remote_url
        remote_url = unwrap_nested_media_url(remote_url, referer=referer)
        if remote_url != original_remote_url:
            logger.info(f"代理 m3u8 解出真实地址: {remote_url}")
        cached_playlist = PLAYLIST_CACHE.get(remote_url)
        if cached_playlist:
            logger.info(f"使用已缓存 m3u8: {remote_url}")
            effective_referer = cached_playlist.get("referer") or referer
            playlist = rewrite_m3u8_playlist(cached_playlist["text"], remote_url, effective_referer, source_page)
            return Response(
                playlist,
                status=200,
                content_type="application/vnd.apple.mpegurl; charset=utf-8",
                headers={
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "no-cache",
                }
            )

        upstream, effective_referer = fetch_remote(
            remote_url,
            referer=referer,
            source_page=source_page,
            accept="application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
            timeout=30,
        )
        try:
            playlist_text = upstream.text
        finally:
            upstream.close()

        PLAYLIST_CACHE[remote_url] = {
            "text": playlist_text,
            "referer": effective_referer,
        }
        playlist = rewrite_m3u8_playlist(playlist_text, remote_url, effective_referer, source_page)
        return Response(
            playlist,
            status=upstream.status_code,
            content_type="application/vnd.apple.mpegurl; charset=utf-8",
            headers={
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache",
            }
        )
    except Exception as e:
        logger.error(f"代理 m3u8 失败: {remote_url} - {e}")
        return jsonify({"error": str(e)}), 502


@app.route("/proxy/media", methods=["GET", "HEAD"])
def proxy_media():
    """代理 HLS 分片、key、init map 或 mp4，保留 Range 能力。"""
    remote_url = request.args.get("url")
    referer = request.args.get("referer", "")
    source_page = request.args.get("source_page", "")

    if not remote_url:
        return jsonify({"error": "缺少 url 参数"}), 400

    try:
        original_remote_url = remote_url
        remote_url = unwrap_nested_media_url(remote_url, referer=referer)
        if remote_url != original_remote_url:
            logger.info(f"代理媒体解出真实地址: {remote_url}")
        extra_headers = {}
        for header_name in ("Range", "If-Range", "If-None-Match", "If-Modified-Since"):
            if request.headers.get(header_name):
                extra_headers[header_name] = request.headers[header_name]

        upstream, _ = fetch_remote(
            remote_url,
            referer=referer,
            source_page=source_page,
            extra_headers=extra_headers,
            stream=True,
            timeout=45,
        )

        response_headers = {
            "Content-Type": media_response_content_type(remote_url, upstream.headers),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store",
            "Accept-Ranges": header_value(upstream.headers, "Accept-Ranges") or "bytes",
        }

        for header_name in ("Content-Length", "Content-Range"):
            value = header_value(upstream.headers, header_name)
            if value:
                response_headers[header_name] = value

        if request.method == "HEAD":
            upstream.close()
            return Response(
                status=upstream.status_code,
                headers=response_headers,
            )

        def generate_body():
            try:
                for chunk in upstream.iter_content(chunk_size=1024 * 256):
                    if chunk:
                        yield chunk
            finally:
                upstream.close()

        return Response(
            stream_with_context(generate_body()),
            status=upstream.status_code,
            headers=response_headers,
            direct_passthrough=True,
        )
    except Exception as e:
        logger.error(f"代理媒体失败: {remote_url} - {e}")
        return jsonify({"error": str(e)}), 502


def scrape_with_playwright(url: str) -> dict:
    """使用 Playwright 渲染页面并提取视频 URL"""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        # Playwright 未安装，尝试简单的 HTML 解析
        logger.warning("Playwright 未安装，使用简单 HTML 解析")
        return scrape_simple(url)

    logger.info(f"使用 Playwright 渲染: {url}")
    user_agent = pick_kazumi_user_agent()
    accept_language = pick_accept_language()
    logger.info(f"使用 Kazumi WebView UA: {user_agent}")

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                '--disable-blink-features=AutomationControlled',
                '--autoplay-policy=user-gesture-required',
            ],
        )
        context = browser.new_context(
            user_agent=user_agent,
            locale=accept_language.split(",")[0],
            timezone_id="Asia/Shanghai",
            viewport={"width": 1280, "height": 720},
            ignore_https_errors=True,
            extra_http_headers={
                "Accept-Language": accept_language,
                "Referer": url,
            },
        )
        install_kazumi_webview_blockers(context)
        install_browser_stealth(context)
        context.add_init_script("""
            (() => {
                if (window.__kazumiHookInstalled) return;
                window.__kazumiHookInstalled = true;
                window.__kazumiM3U8Hits = [];
                window.__kazumiVideoHits = [];

                function removeLazyLoading() {
                    try {
                        document.querySelectorAll('iframe[loading="lazy"]').forEach((iframe) => {
                            iframe.removeAttribute('loading');
                        });
                    } catch (e) {}
                }

                function rememberM3U8(targetUrl, text) {
                    try {
                        if (!text || !text.trim().startsWith("#EXTM3U")) return;
                        window.__kazumiM3U8Hits.push({
                            url: String(targetUrl || location.href),
                            text: text
                        });
                    } catch (e) {}
                }

                function rememberVideoURL(targetUrl) {
                    try {
                        if (!targetUrl) return;
                        const value = String(targetUrl);
                        if (!value || value.startsWith("blob:") || value.includes("googleads")) return;
                        window.__kazumiVideoHits.push(value);
                    } catch (e) {}
                }

                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', removeLazyLoading);
                } else {
                    removeLazyLoading();
                }

                const originalResponseText = window.Response && window.Response.prototype && window.Response.prototype.text;
                if (originalResponseText && !window.Response.prototype.__kazumiTextHooked) {
                    window.Response.prototype.__kazumiTextHooked = true;
                    window.Response.prototype.text = function () {
                        return originalResponseText.call(this).then((text) => {
                            rememberM3U8(this.url, text);
                            return text;
                        });
                    };
                }

                const originalFetch = window.fetch;
                if (originalFetch) {
                    window.fetch = function (...args) {
                        return originalFetch.apply(this, args).then((response) => {
                            try {
                                const clone = response.clone();
                                clone.text().then((text) => {
                                    const requestUrl = response.url || (args[0] && args[0].url) || args[0];
                                    rememberM3U8(requestUrl, text);
                                }).catch(() => {});
                            } catch (e) {}
                            return response;
                        });
                    };
                }

                const originalOpen = XMLHttpRequest.prototype.open;
                const originalSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.open = function (...args) {
                    this.__kazumiURL = args[1];
                    return originalOpen.apply(this, args);
                };
                XMLHttpRequest.prototype.send = function (...args) {
                    this.addEventListener("load", () => {
                        try {
                            const content = typeof this.responseText === "string" ? this.responseText : this.response;
                            rememberM3U8(this.responseURL || this.__kazumiURL, content);
                        } catch (e) {}
                    });
                    return originalSend.apply(this, args);
                };

                function processVideoElement(video) {
                    try {
                        rememberVideoURL(video.getAttribute("src"));
                        video.querySelectorAll("source").forEach((source) => {
                            rememberVideoURL(source.getAttribute("src"));
                        });
                    } catch (e) {}
                }

                function scanVideoElements() {
                    try {
                        document.querySelectorAll("video").forEach(processVideoElement);
                    } catch (e) {}
                }

                if (document.readyState === "loading") {
                    document.addEventListener("DOMContentLoaded", scanVideoElements);
                } else {
                    scanVideoElements();
                }

                const observer = new MutationObserver((mutations) => {
                    mutations.forEach((mutation) => {
                        if (mutation.type === "attributes" && mutation.target && mutation.target.nodeName === "VIDEO") {
                            processVideoElement(mutation.target);
                        }
                        mutation.addedNodes.forEach((node) => {
                            if (node.nodeName === "VIDEO") processVideoElement(node);
                            if (node.querySelectorAll) {
                                node.querySelectorAll("video").forEach(processVideoElement);
                            }
                        });
                    });
                });

                if (document.documentElement) {
                    observer.observe(document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ["src"]
                    });
                }
            })();
        """)

        video_urls = []
        pending_pages = [(url, 0)]
        seen_pages = set()
        rejected_media_urls = set()

        def remember_media_url(
            media_url: str,
            priority: int = 1,
            base_url: str = None,
            referer_url: str = None,
            allow_extensionless: bool = False
        ):
            media_url = urljoin(base_url or url, media_url)
            wrapper_url = media_url
            unwrapped_url = unwrap_nested_media_url(media_url, referer=referer_url or base_url or url)
            if unwrapped_url != media_url:
                logger.info(f"解出播放器内真实媒体地址: {unwrapped_url}")
                referer_url = wrapper_url
                media_url = unwrapped_url
            url_lower = media_url.lower()
            if should_ignore_media_url(url_lower):
                logger.info(f"忽略非正片媒体: {media_url}")
                return None

            is_playlist = is_playlist_url(media_url)
            is_file_video = is_direct_file_video_url(media_url)
            is_extensionless_video = allow_extensionless and is_probable_extensionless_video_url(media_url)

            if is_playlist or is_file_video or is_extensionless_video:
                if 'm3u8' in url_lower or 'manifest' in url_lower or 'playlist' in url_lower:
                    item = {
                        "url": media_url,
                        "type": "m3u8",
                        "priority": priority,
                        "referer": referer_url or base_url or url
                    }
                    video_urls.append(item)
                    return item
                else:
                    item = {
                        "url": media_url,
                        "type": "mp4",
                        "priority": priority if is_extensionless_video else priority - 1,
                        "referer": referer_url or base_url or url
                    }
                    video_urls.append(item)
                    return item

            return None

        def queue_page(page_url: str, level: int, source: str, base_url: str = None):
            page_url = urljoin(base_url or url, page_url)
            if not page_url.startswith("http") or level > 3 or page_url in seen_pages:
                return

            if is_direct_media_resource(page_url):
                logger.info(f"{source}: {page_url}")
                remember_media_url(page_url, priority=1, base_url=base_url or url, referer_url=base_url or url)
                return

            pending_pages.append((page_url, level))
            logger.info(f"{source}: {page_url}")

        def choose_playable_candidate(allow_probe: bool = False):
            candidates = dedupe_media_candidates(video_urls)
            candidates.sort(key=lambda x: x["priority"], reverse=True)

            for candidate in candidates:
                media_url = candidate["url"]
                if media_url in rejected_media_urls:
                    continue

                if candidate.get("type") != "m3u8":
                    return candidate

                if media_url in PLAYLIST_CACHE:
                    return candidate

                if not allow_probe:
                    continue

                if prime_playlist_cache(context, media_url, candidate.get("referer") or url):
                    return candidate

                rejected_media_urls.add(media_url)
                logger.warning(f"跳过无法读取的 m3u8 线路: {media_url}")

            return None

        def trigger_playback(page):
            selectors = [
                "button[aria-label*=Play]",
                "button[title*=Play]",
                ".vjs-big-play-button",
                ".plyr__control--overlaid",
                ".play",
                "#play",
                "video",
            ]
            for selector in selectors:
                try:
                    locator = page.locator(selector).first
                    if locator.count() > 0:
                        locator.click(timeout=1500, force=True)
                        page.wait_for_timeout(2000)
                        return
                except Exception:
                    pass

            try:
                box = page.viewport_size or {"width": 1280, "height": 720}
                page.mouse.click(box["width"] / 2, box["height"] / 2)
                page.wait_for_timeout(2500)
            except Exception:
                pass

        def harvest_browser_hits(page, target_url: str):
            for playlist_url in harvest_m3u8_hits(page, target_url):
                remember_media_url(playlist_url, priority=4, base_url=target_url, referer_url=target_url)

            for frame in page.frames:
                try:
                    hits = frame.evaluate("""
                        () => {
                            const hits = window.__kazumiVideoHits || [];
                            window.__kazumiVideoHits = [];
                            return hits;
                        }
                    """)
                except Exception:
                    continue

                for media_url in hits or []:
                    remember_media_url(
                        media_url,
                        priority=4,
                        base_url=target_url,
                        referer_url=target_url,
                        allow_extensionless=True
                    )

        def scan_page(target_url: str, level: int):
            if target_url in seen_pages or level > 3:
                return

            seen_pages.add(target_url)
            page = context.new_page()

            def handle_request(req):
                is_media_request = req.resource_type == "media"
                remember_media_url(
                    req.url,
                    priority=4 if is_media_request else 1,
                    base_url=target_url,
                    referer_url=target_url,
                    allow_extensionless=is_media_request
                )

            def handle_response(response):
                is_media_response = response.request.resource_type == "media"
                remember_media_url(
                    response.url,
                    priority=4 if is_media_response else 2,
                    base_url=target_url,
                    referer_url=target_url,
                    allow_extensionless=is_media_response
                )
                cache_m3u8_response_body(response, target_url)

            page.on("request", handle_request)
            page.on("response", handle_response)

            try:
                logger.info(f"渲染页面[{level}]: {target_url}")
                page.goto(target_url, wait_until="domcontentloaded", timeout=15000)
                try:
                    page.wait_for_load_state("networkidle", timeout=2500)
                except Exception:
                    pass

                page.wait_for_timeout(500 if level == 0 else 1000)
                queued_iframe = False
                for iframe in page.query_selector_all("iframe"):
                    src = iframe.get_attribute("src")
                    if src:
                        queued_iframe = True
                        queue_page(src, level + 1, "找到 iframe", base_url=target_url)

                if level == 0 and queued_iframe:
                    harvest_browser_hits(page, target_url)
                    return

                for _ in range(10):
                    page.wait_for_timeout(500)
                    harvest_browser_hits(page, target_url)
                    if choose_playable_candidate(allow_probe=False):
                        break

                if not choose_playable_candidate(allow_probe=False):
                    trigger_playback(page)

                for _ in range(12):
                    page.wait_for_timeout(700)
                    harvest_browser_hits(page, target_url)
                    if choose_playable_candidate(allow_probe=False):
                        break

                for video in page.query_selector_all("video"):
                    src = video.get_attribute("src")
                    if src:
                        item = remember_media_url(
                            src,
                            priority=4,
                            base_url=target_url,
                            referer_url=target_url,
                            allow_extensionless=True
                        )
                        if item and item["type"] == "m3u8":
                            prime_playlist_cache_from_page(page, item["url"], target_url)
                    for source in video.query_selector_all("source"):
                        source_src = source.get_attribute("src")
                        if source_src:
                            item = remember_media_url(
                                source_src,
                                priority=4,
                                base_url=target_url,
                                referer_url=target_url,
                                allow_extensionless=True
                            )
                            if item and item["type"] == "m3u8":
                                prime_playlist_cache_from_page(page, item["url"], target_url)

                for script in page.query_selector_all("script"):
                    content = script.inner_text() or ""
                    for media_url in extract_media_urls(content, target_url):
                        remember_media_url(media_url, priority=1, base_url=target_url, referer_url=target_url)

                    for iframe_url in extract_iframe_urls(content, target_url):
                        if iframe_url != target_url:
                            queue_page(iframe_url, level + 1, "脚本中找到播放器地址", base_url=target_url)

                html = page.content()
                for media_url in extract_media_urls(html, target_url):
                    remember_media_url(media_url, priority=1, base_url=target_url, referer_url=target_url)

                for iframe_url in extract_iframe_urls(html, target_url):
                    if iframe_url != target_url:
                        queue_page(iframe_url, level + 1, "HTML 中找到播放器地址", base_url=target_url)

                harvest_browser_hits(page, target_url)

            except Exception as e:
                logger.warning(f"页面加载失败 {target_url}: {e}")
            finally:
                page.close()

        while pending_pages:
            next_url, level = pending_pages.pop(0)
            scan_page(next_url, level)
            best = choose_playable_candidate(allow_probe=False)
            if best:
                logger.info(f"找到视频: {best['url']}")
                browser.close()
                return {"url": best["url"], "quality": "默认", "referer": best.get("referer")}

        # 选择最佳视频 URL
        if video_urls:
            best = choose_playable_candidate(allow_probe=True)
            if best:
                logger.info(f"找到视频: {best['url']}")
                browser.close()
                return {"url": best["url"], "quality": "默认", "referer": best.get("referer")}

        logger.warning("未找到视频 URL")
        browser.close()
    return None


def fetch_remote(
    remote_url: str,
    referer: str = "",
    source_page: str = "",
    accept: str = "*/*",
    extra_headers: dict = None,
    stream: bool = False,
    timeout: int = 30,
):
    """用多组浏览器化请求头尝试远端资源，返回成功响应和实际 referer。"""
    attempts = proxy_header_attempts(remote_url, referer, source_page, accept)
    last_error = None

    for headers, effective_referer, label in attempts:
        if extra_headers:
            headers.update(extra_headers)

        try:
            response = requests.get(
                remote_url,
                headers=headers,
                stream=stream,
                timeout=timeout,
                verify=False
            )
            if response.status_code < 400:
                if label != "primary":
                    logger.info(f"代理请求使用备用请求头成功: {label}")
                return response, effective_referer

            last_error = requests.HTTPError(
                f"{response.status_code} Client Error: {response.reason} for url: {remote_url}",
                response=response
            )
            logger.warning(f"代理请求失败[{label}]: {response.status_code} {remote_url}")
            response.close()
        except Exception as e:
            last_error = e
            logger.warning(f"代理请求异常[{label}]: {remote_url} - {e}")

    for headers, effective_referer, label in attempts:
        try:
            if extra_headers:
                headers.update(extra_headers)
            response = fetch_with_chromium(remote_url, headers, timeout=timeout)
            logger.info(f"代理请求使用 Chromium 成功: {label}")
            return response, effective_referer
        except Exception as e:
            last_error = e
            logger.warning(f"Chromium 代理请求失败[{label}]: {remote_url} - {e}")

    if last_error:
        raise last_error
    raise RuntimeError(f"无法请求远端资源: {remote_url}")


def cache_m3u8_response_body(response, referer: str):
    try:
        response_url = response.url
        if ".m3u8" not in response_url.lower() or response.status >= 400:
            return

        text = response.text()
        if not text.lstrip().startswith("#EXTM3U"):
            return

        PLAYLIST_CACHE[response_url] = {
            "text": text,
            "referer": referer,
        }
        logger.info(f"已从播放器响应缓存 m3u8: {response_url}")
    except Exception:
        pass


def harvest_m3u8_hits(page, referer: str):
    playlist_urls = []
    for frame in page.frames:
        try:
            hits = frame.evaluate("""
                () => {
                    const hits = window.__kazumiM3U8Hits || [];
                    window.__kazumiM3U8Hits = [];
                    return hits;
                }
            """)
        except Exception:
            continue

        for hit in hits or []:
            playlist_url = hit.get("url")
            playlist_text = hit.get("text")
            if not playlist_url or not playlist_text:
                continue
            if not playlist_text.lstrip().startswith("#EXTM3U"):
                continue

            PLAYLIST_CACHE[playlist_url] = {
                "text": playlist_text,
                "referer": referer,
            }
            playlist_urls.append(playlist_url)
            logger.info(f"已从 Kazumi WebView hook 缓存 m3u8: {playlist_url}")
    return playlist_urls


class MemoryHTTPResponse:
    def __init__(self, content: bytes, status_code: int, headers: dict, url: str):
        self.content = content
        self.status_code = status_code
        self.headers = headers or {}
        self.url = url
        self.reason = "OK" if status_code < 400 else "Error"

    @property
    def text(self) -> str:
        encoding = "utf-8"
        content_type = self.headers.get("content-type") or self.headers.get("Content-Type") or ""
        match = re.search(r"charset=([^;\s]+)", content_type, re.IGNORECASE)
        if match:
            encoding = match.group(1)
        return self.content.decode(encoding, errors="ignore")

    def iter_content(self, chunk_size=1024 * 256):
        for index in range(0, len(self.content), chunk_size):
            yield self.content[index:index + chunk_size]

    def close(self):
        pass


def fetch_with_chromium(remote_url: str, headers: dict, timeout: int = 30) -> MemoryHTTPResponse:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as e:
        raise RuntimeError(f"playwright 未安装: {e}")

    if not PLAYWRIGHT_SEMAPHORE.acquire(timeout=5):
        raise RuntimeError("Chromium 抓取通道正忙，请稍后重试")

    accept_language = headers.get("Accept-Language", DEFAULT_HEADERS["Accept-Language"])
    try:
        with sync_playwright() as p:
            browser = None
            context = None
            page = None
            try:
                browser = p.chromium.launch(
                    headless=True,
                    args=[
                        '--disable-blink-features=AutomationControlled',
                        '--autoplay-policy=user-gesture-required',
                    ],
                )
                context = browser.new_context(
                    user_agent=headers.get("User-Agent", DEFAULT_HEADERS["User-Agent"]),
                    locale=accept_language.split(",")[0],
                    timezone_id="Asia/Shanghai",
                    extra_http_headers=headers,
                    ignore_https_errors=True,
                )
                install_browser_stealth(context)
                page = context.new_page()
                response = page.goto(remote_url, wait_until="commit", timeout=timeout * 1000)
                if response is None:
                    raise RuntimeError("Chromium 未收到响应")
                body = response.body()
                if response.status >= 400:
                    raise requests.HTTPError(
                        f"{response.status} Client Error for url: {remote_url}"
                    )
                return MemoryHTTPResponse(body, response.status, response.headers, remote_url)
            finally:
                with suppress(Exception):
                    if page:
                        page.close()
                with suppress(Exception):
                    if context:
                        context.close()
                with suppress(Exception):
                    if browser:
                        browser.close()
    finally:
        PLAYWRIGHT_SEMAPHORE.release()


def install_browser_stealth(context):
    """尽量贴近 Kazumi Headless WebView，避免播放器只返回广告占位源。"""
    context.add_init_script("""
        (() => {
            try {
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en-US', 'en'] });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                const ua = navigator.userAgent || '';
                if (ua.includes('Chrome') || ua.includes('Edg')) {
                    window.chrome = window.chrome || { runtime: {} };
                }
            } catch (e) {}
        })();
    """)


def install_kazumi_webview_blockers(context):
    """模拟 Kazumi Headless WebView 的内容拦截器，减少广告播放器抢先加载。"""
    def route_handler(route):
        request_obj = route.request
        request_url = request_obj.url.lower()
        resource_type = request_obj.resource_type

        if resource_type == "image" or should_block_browser_url(request_url):
            route.abort()
            return

        route.continue_()

    context.route("**/*", route_handler)


def should_block_browser_url(url_lower: str) -> bool:
    blocked_markers = [
        "devtools-detector.js",
        "googleads",
        "googlesyndication.com",
        "prestrain.html",
        "prestrain%2ehtml",
        "adtrafficquality",
    ]
    return any(marker in url_lower for marker in blocked_markers)


def dedupe_media_candidates(video_urls: list) -> list:
    candidates_by_url = {}
    for item in video_urls:
        media_url = item.get("url")
        if not media_url:
            continue

        existing = candidates_by_url.get(media_url)
        if existing is None or item.get("priority", 0) > existing.get("priority", 0):
            candidates_by_url[media_url] = item

    return list(candidates_by_url.values())


def prime_playlist_cache(context, playlist_url: str, referer: str):
    if playlist_url in PLAYLIST_CACHE:
        return True

    page = context.new_page()
    try:
        page.set_extra_http_headers(build_proxy_headers(
            referer,
            accept="application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
            include_fetch_headers=True
        ))
        response = page.goto(playlist_url, wait_until="commit", timeout=6_000)
        if response is None or response.status >= 400:
            status = response.status if response else "no-response"
            logger.warning(f"预缓存 m3u8 失败[{status}]: {playlist_url}")
            return False

        body = response.body()
        playlist_text = body.decode("utf-8", errors="ignore")
        if not playlist_text.lstrip().startswith("#EXTM3U"):
            logger.warning(f"预缓存内容不是 m3u8: {playlist_url}")
            return False

        PLAYLIST_CACHE[playlist_url] = {
            "text": playlist_text,
            "referer": referer,
        }
        logger.info(f"已缓存 m3u8 playlist: {playlist_url}")
        return True
    except Exception as e:
        logger.warning(f"预缓存 m3u8 异常: {playlist_url} - {e}")
        return False
    finally:
        page.close()


def prime_playlist_cache_from_page(page, playlist_url: str, referer: str):
    """在播放器页自身上下文里预取 m3u8，保留该页的 origin/cookie 行为。"""
    if playlist_url in PLAYLIST_CACHE:
        return True

    try:
        result = page.evaluate("""
            async ({ playlistUrl }) => {
                const response = await fetch(playlistUrl, {
                    credentials: 'include',
                    cache: 'no-store',
                    headers: {
                        'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
                    }
                });
                const text = await response.text();
                return {
                    ok: response.ok,
                    status: response.status,
                    url: response.url || playlistUrl,
                    text
                };
            }
        """, {"playlistUrl": playlist_url})

        if not result or not result.get("ok"):
            status = result.get("status") if result else "no-response"
            logger.warning(f"播放器页预缓存 m3u8 失败[{status}]: {playlist_url}")
            return False

        playlist_text = result.get("text") or ""
        if not playlist_text.lstrip().startswith("#EXTM3U"):
            logger.warning(f"播放器页预缓存不是 m3u8: {playlist_url}")
            return False

        final_url = result.get("url") or playlist_url
        cache_entry = {
            "text": playlist_text,
            "referer": referer,
        }
        PLAYLIST_CACHE[playlist_url] = cache_entry
        PLAYLIST_CACHE[final_url] = cache_entry
        logger.info(f"已从播放器页 fetch 缓存 m3u8: {playlist_url}")
        return True
    except Exception as e:
        logger.warning(f"播放器页预缓存 m3u8 异常: {playlist_url} - {e}")
        return False


def proxy_header_attempts(remote_url: str, referer: str = "", source_page: str = "", accept: str = "*/*") -> list:
    referers = []
    for value in [
        referer,
        source_page,
        referer_origin(referer),
        referer_origin(source_page),
        remote_origin(remote_url),
        "",
    ]:
        if value not in referers:
            referers.append(value)

    attempts = []
    for index, candidate_referer in enumerate(referers):
        label = "primary" if index == 0 else f"referer:{candidate_referer or 'none'}"
        attempts.append((build_proxy_headers(candidate_referer, accept=accept, include_fetch_headers=False), candidate_referer, label))
        attempts.append((build_proxy_headers(candidate_referer, accept=accept, include_fetch_headers=True), candidate_referer, f"{label}:fetch"))

    return attempts


def build_proxy_headers(referer: str = "", accept: str = "*/*", include_fetch_headers: bool = False) -> dict:
    headers = {
        "User-Agent": DEFAULT_HEADERS["User-Agent"],
        "Accept": accept,
        "Accept-Language": DEFAULT_HEADERS["Accept-Language"],
        "Accept-Encoding": "identity",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
    }

    if referer:
        headers["Referer"] = referer

    if include_fetch_headers:
        headers.update({
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "cross-site",
        })

    return headers


def referer_origin(value: str) -> str:
    parsed = urlparse(value or "")
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}/"
    return ""


def remote_origin(value: str) -> str:
    return referer_origin(value)


def rewrite_m3u8_playlist(text: str, playlist_url: str, referer: str, source_page: str = "") -> str:
    rewritten_lines = []
    next_uri_is_playlist = False
    proxied_playlists = 0
    proxied_media = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            rewritten_lines.append(line)
        elif stripped.startswith("#"):
            rewritten_line, media_count, playlist_count = rewrite_m3u8_uri_attributes(line, playlist_url, referer, source_page)
            proxied_media += media_count
            proxied_playlists += playlist_count
            rewritten_lines.append(rewritten_line)
            next_uri_is_playlist = stripped.startswith("#EXT-X-STREAM-INF")
        else:
            absolute_url = urljoin(playlist_url, stripped)
            if next_uri_is_playlist or is_playlist_url(absolute_url):
                rewritten_lines.append(build_local_proxy_url(
                    absolute_url,
                    referer,
                    source_page,
                    is_playlist=True
                ))
                proxied_playlists += 1
            else:
                rewritten_lines.append(build_local_proxy_url(
                    absolute_url,
                    referer,
                    source_page,
                    is_playlist=False
                ))
                proxied_media += 1
            next_uri_is_playlist = False

    logger.info(f"m3u8 改写完成: playlist={proxied_playlists}, media/key={proxied_media}, url={playlist_url}")
    return "\n".join(rewritten_lines) + "\n"


def rewrite_m3u8_uri_attributes(line: str, playlist_url: str, referer: str, source_page: str = "") -> str:
    def replace_uri(match):
        raw_uri = match.group(1) or match.group(2)
        if not raw_uri or raw_uri.startswith("data:"):
            return match.group(0)

        absolute_url = urljoin(playlist_url, raw_uri)
        if is_playlist_url(absolute_url):
            proxied = build_local_proxy_url(
                absolute_url,
                referer,
                source_page,
                is_playlist=True
            )
            replace_uri.playlist_count += 1
            return f'URI="{proxied}"'
        proxied = build_local_proxy_url(
            absolute_url,
            referer,
            source_page,
            is_playlist=False
        )
        replace_uri.media_count += 1
        return f'URI="{proxied}"'

    replace_uri.media_count = 0
    replace_uri.playlist_count = 0
    rewritten = re.sub(r'URI="([^"]+)"|URI=([^,]+)', replace_uri, line)
    return rewritten, replace_uri.media_count, replace_uri.playlist_count


def build_local_proxy_url(remote_url: str, referer: str, source_page: str = "", is_playlist: bool = False) -> str:
    endpoint = "/proxy/m3u8" if is_playlist else "/proxy/media"
    query = urlencode({
        "url": remote_url,
        "referer": referer or "",
        "source_page": source_page or "",
    })
    return f"{endpoint}?{query}"


def is_playlist_url(url: str) -> bool:
    path = urlparse(url).path.lower()
    return ".m3u8" in path or "m3u8" in path or "manifest" in path or "playlist" in path


def is_direct_media_resource(url: str) -> bool:
    return is_playlist_url(url) or is_direct_file_video_url(url)


def is_direct_file_video_url(url: str) -> bool:
    path = urlparse(url).path.lower()
    return path.endswith((".mp4", ".m4v", ".mov"))


def unwrap_nested_media_url(candidate_url: str, referer: str = "") -> str:
    """播放器壳 URL 常把真实媒体放在 query 的 url/file/src 里。"""
    if not candidate_url:
        return candidate_url

    absolute_url = urljoin(referer or candidate_url, candidate_url)
    parsed = urlparse(absolute_url)
    query_values = parse_qs(parsed.query, keep_blank_values=False)
    preferred_keys = [
        "url",
        "playurl",
        "play_url",
        "file",
        "src",
        "source",
        "video",
        "path",
    ]

    nested_values = []
    for key in preferred_keys:
        nested_values.extend(query_values.get(key, []))

    if not nested_values:
        for values in query_values.values():
            nested_values.extend(value for value in values if looks_like_nested_media_url(value))

    for raw_value in nested_values:
        nested_url = normalize_nested_media_value(raw_value, absolute_url)
        if nested_url and nested_url != absolute_url and is_direct_media_resource(nested_url):
            return nested_url

    return absolute_url


def normalize_nested_media_value(value: str, base_url: str) -> str:
    if not value:
        return ""

    normalized = unquote(value).replace("\\/", "/").strip()
    if normalized.startswith("//"):
        return f"{urlparse(base_url).scheme}:{normalized}"
    return urljoin(base_url, normalized)


def looks_like_nested_media_url(value: str) -> bool:
    normalized = unquote(value or "").replace("\\/", "/").strip().lower()
    return normalized.startswith(("http://", "https://", "//")) and any(
        marker in normalized for marker in (".m3u8", ".mp4", ".m4v", ".mov")
    )


def is_probable_extensionless_video_url(url: str) -> bool:
    """Kazumi 原版会接受 video.src；部分 AGE 线路返回无扩展名直链。"""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return False

    lowered = url.lower()
    if should_ignore_media_url(lowered):
        return False

    blocked_markers = [
        ".js",
        ".css",
        ".jpg",
        ".jpeg",
        ".png",
        ".gif",
        ".svg",
        ".webp",
        ".ico",
        ".woff",
        ".ttf",
        "api.php",
        "hm.baidu.com",
        "googleads",
        "googlesyndication",
    ]
    if any(marker in lowered for marker in blocked_markers):
        return False

    media_host_markers = [
        "toutiao",
        "byte",
        "ixigua",
        "bfvvs",
        "ffzy",
        "fengbao",
        "baofeng",
        "ppqrrs",
        "mgtv",
        "bilivideo",
        "miguvideo",
        "alicdn",
        "akamaized",
        "bunnycdn",
    ]
    if any(marker in parsed.netloc.lower() for marker in media_host_markers):
        return True

    media_path_markers = ["/video/", "/tos/", "/play/", "/vod/", "/hls/"]
    return any(marker in parsed.path.lower() for marker in media_path_markers)


def guess_content_type(url: str) -> str:
    path = urlparse(url).path.lower()
    if path.endswith(".m3u8"):
        return "application/vnd.apple.mpegurl"
    if path.endswith(".ts"):
        return "video/mp2t"
    if path.endswith(".m4s"):
        return "video/iso.segment"
    if path.endswith(".mp4"):
        return "video/mp4"
    if path.endswith(".m4a"):
        return "audio/mp4"
    return "application/octet-stream"


def header_value(headers: dict, name: str) -> str:
    if not headers:
        return ""

    direct = headers.get(name)
    if direct:
        return direct

    lower_name = name.lower()
    for key, value in headers.items():
        if key.lower() == lower_name:
            return value
    return ""


def media_response_content_type(url: str, headers: dict) -> str:
    content_type = header_value(headers, "Content-Type")
    normalized = content_type.split(";", 1)[0].strip().lower() if content_type else ""
    guessed = guess_content_type(url)

    if normalized in ("", "application/octet-stream", "binary/octet-stream", "application/download"):
        if guessed != "application/octet-stream":
            return guessed
        if is_probable_extensionless_video_url(url):
            return "video/mp4"

    return content_type or guessed


def extract_media_urls(text: str, base_url: str) -> list:
    """从 HTML/JS 文本中提取 m3u8/mp4，并处理转义斜杠和相对地址。"""
    if not text:
        return []

    text = text.replace("\\/", "/")
    patterns = [
        r'["\']([^"\']+\.(?:m3u8|mp4)[^"\']*)["\']',
        r'(https?://[^\s"\'<>]+(?:m3u8|mp4)[^\s"\'<>]*)',
        r'(//[^\s"\'<>]+(?:m3u8|mp4)[^\s"\'<>]*)',
    ]

    urls = []
    for pattern in patterns:
        for match in re.findall(pattern, text, re.IGNORECASE):
            urls.append(urljoin(base_url, match))
    return urls


def should_ignore_media_url(url_lower: str) -> bool:
    """过滤广告、海报、占位视频，避免把它们当正片返回给 AVPlayer。"""
    ignored_markers = [
        "adposter",
        "/adposter",
        "/ad/",
        "advert",
        "poster.mp4",
        "loading.mp4",
        "blank.mp4",
        "logo.mp4",
        "placeholder",
    ]
    return any(marker in url_lower for marker in ignored_markers)


def extract_iframe_urls(text: str, base_url: str) -> list:
    """从常见播放器字段中提取 iframe/player 地址。"""
    if not text:
        return []

    text = text.replace("\\/", "/")
    patterns = [
        r'<iframe[^>]+src=["\']([^"\']+)["\']',
        r'(?:iframe|player|playurl|url)\s*[:=]\s*["\']([^"\']+)["\']',
        r'"url"\s*:\s*"([^"]+)"',
    ]

    urls = []
    for pattern in patterns:
        for match in re.findall(pattern, text, re.IGNORECASE):
            if not match or match.startswith("javascript:"):
                continue
            lowered = match.lower()
            if any(token in lowered for token in ["player", "play", "m3u8", "mp4", "api.php", "url="]):
                urls.append(urljoin(base_url, match))
    return urls


def scrape_simple(url: str) -> dict:
    """简单的 HTML 解析方法 (备用)"""
    try:
        resp = requests.get(url, headers=DEFAULT_HEADERS, timeout=10, verify=False)
        resp.raise_for_status()
    except Exception as e:
        logger.error(f"请求失败: {e}")
        return None

    html = resp.text
    soup = BeautifulSoup(html, "lxml")

    # 查找 iframe
    iframe = soup.find("iframe", src=True)
    if iframe:
        iframe_url = iframe["src"]
        if iframe_url.startswith("//"):
            iframe_url = "https:" + iframe_url
        if iframe_url.startswith("http"):
            logger.info(f"找到 iframe，递归抓取: {iframe_url}")
            return scrape_simple(iframe_url)

    # 查找 m3u8 URL
    for media_url in extract_media_urls(html, url):
        media_url = unwrap_nested_media_url(media_url, referer=url)
        if is_direct_media_resource(media_url):
            logger.info(f"找到视频地址: {media_url}")
            return {"url": media_url, "quality": "默认"}

    return None


# 禁用 SSL 警告
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Kazumi Video Scraper Server")
    parser.add_argument("--port", "-p", type=int, default=5001, help="服务器端口 (默认: 5001)")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="服务器地址 (默认: 0.0.0.0)")
    parser.add_argument("--debug", action="store_true", help="启用 Flask 调试模式")
    args = parser.parse_args()

    print(f"""
╔═══════════════════════════════════════════════════════════╗
║           Kazumi Video Scraper Server                     ║
║                                                           ║
║  启动服务: http://localhost:{args.port}                       ║
║                                                           ║
║  API 使用:                                                ║
║    - GET /scrape?url=xxx&plugin=age                     ║
║    - GET /scrape_js?url=xxx  (备用接口)                  ║
║    - GET /health                                         ║
║                                                           ║
║  安装依赖:                                                ║
║    pip install -r requirements.txt                        ║
║    playwright install chromium                            ║
╚═══════════════════════════════════════════════════════════╝
    """)
    app.run(host=args.host, port=args.port, debug=args.debug, threaded=True, use_reloader=False)
