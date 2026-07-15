# shot-board —— 电脑开服务，手机浏览器打开页面看最新截图（不进相册）
# 默认监视 SilentShot 目录：%USERPROFILE%\Pictures\Screenshots
# 用法: python shot_board.py
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}


def default_shot_dir() -> Path:
    pictures = Path(os.environ.get("USERPROFILE", "")) / "Pictures" / "Screenshots"
    return pictures


def list_images(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    files = [
        p
        for p in folder.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXT and not p.name.startswith("_")
    ]
    files.sort(key=lambda p: p.stat().st_mtime_ns, reverse=True)
    return files


def local_ipv4s() -> list[str]:
    ips: list[str] = []
    seen: set[str] = set()

    def add(ip: str):
        if ip and not ip.startswith("127.") and ip not in seen:
            seen.add(ip)
            ips.append(ip)

    for probe in (("8.8.8.8", 80), ("1.1.1.1", 80)):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(probe)
                add(s.getsockname()[0])
        except OSError:
            pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            add(info[4][0])
    except OSError:
        pass
    return ips


PAGE_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
<meta name="apple-mobile-web-app-capable" content="yes"/>
<title>截图看板</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  html, body {
    margin: 0; height: 100%; background: #0d0f12; color: #e8eaed;
    font-family: "Segoe UI", system-ui, sans-serif;
  }
  body { display: flex; flex-direction: column; }
  header {
    flex: 0 0 auto; z-index: 2;
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    padding: 10px 14px; background: rgba(13,15,18,.96);
    border-bottom: 1px solid #242830;
  }
  h1 { margin: 0; font-size: 15px; font-weight: 600; }
  #status { font-size: 12px; color: #9aa3af; text-align: right; max-width: 55%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #follow {
    border: 1px solid #3a414d; background: #1a1f27; color: #dbe1ea;
    border-radius: 999px; padding: 4px 10px; font-size: 12px; cursor: pointer;
  }
  #follow.on { border-color: #3d7eff; color: #8cb4ff; }
  main {
    flex: 1 1 auto; min-height: 0;
    display: flex; align-items: center; justify-content: center;
    padding: 10px 12px;
  }
  #shot {
    max-width: 100%; max-height: 100%;
    object-fit: contain; border-radius: 8px;
    box-shadow: 0 8px 32px rgba(0,0,0,.45);
    background: #161a20;
  }
  #empty { color: #6b7280; font-size: 14px; text-align: center; line-height: 1.6; }
  #rail-wrap {
    flex: 0 0 auto;
    border-top: 1px solid #242830;
    background: #11141a;
    padding: 8px 0 10px;
  }
  #rail-label {
    padding: 0 12px 6px; font-size: 11px; color: #7b8494; letter-spacing: .04em;
  }
  #rail {
    display: flex; gap: 8px; overflow-x: auto; padding: 0 12px 2px;
    -webkit-overflow-scrolling: touch; scrollbar-width: thin;
  }
  .thumb {
    flex: 0 0 auto; width: 72px; height: 72px; padding: 0; border: 2px solid transparent;
    border-radius: 8px; overflow: hidden; background: #1a1f27; cursor: pointer;
  }
  .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .thumb.active { border-color: #3d7eff; }
  .thumb .t { display: block; font-size: 9px; color: #9aa3af; text-align: center;
    padding: 2px 0; background: #151922; }
</style>
</head>
<body>
<header>
  <h1>截图看板</h1>
  <button type="button" id="follow" class="on">跟最新</button>
  <div id="status">连接中…</div>
</header>
<main>
  <img id="shot" alt="截图" hidden/>
  <div id="empty">等待新截图…<br/>目录里的历史图会出现在下方</div>
</main>
<section id="rail-wrap">
  <div id="rail-label">历史记录（点缩略图查看旧图）</div>
  <div id="rail"></div>
</section>
<script>
const shot = document.getElementById('shot');
const empty = document.getElementById('empty');
const status = document.getElementById('status');
const rail = document.getElementById('rail');
const followBtn = document.getElementById('follow');

let items = [];          // [{name, mtime, size}] 新→旧
let selectedName = null; // 当前查看的文件名
let followLatest = true; // true=有新图自动跳最新；false=停在当前历史
let listSig = '';

followBtn.onclick = () => {
  followLatest = !followLatest;
  followBtn.classList.toggle('on', followLatest);
  followBtn.textContent = followLatest ? '跟最新' : '已定格';
  if (followLatest && items.length) showItem(items[0]);
};

function imgUrl(it) {
  return '/img?name=' + encodeURIComponent(it.name) + '&v=' + it.mtime;
}

function showItem(it) {
  if (!it) return;
  selectedName = it.name;
  shot.src = imgUrl(it);
  shot.hidden = false;
  empty.hidden = true;
  const d = new Date(it.mtime * 1000);
  status.textContent = it.name + ' · ' + d.toLocaleString();
  [...rail.querySelectorAll('.thumb')].forEach(el => {
    el.classList.toggle('active', el.dataset.name === it.name);
  });
}

function renderRail() {
  rail.innerHTML = '';
  for (const it of items) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'thumb' + (it.name === selectedName ? ' active' : '');
    btn.dataset.name = it.name;
    const d = new Date(it.mtime * 1000);
    btn.innerHTML = '<img loading="lazy" alt="" src="' + imgUrl(it) + '"/>'
      + '<span class="t">' + d.toLocaleTimeString() + '</span>';
    btn.onclick = () => {
      followLatest = false;
      followBtn.classList.remove('on');
      followBtn.textContent = '已定格';
      showItem(it);
    };
    rail.appendChild(btn);
  }
}

async function tick() {
  try {
    const r = await fetch('/api/list?t=' + Date.now(), { cache: 'no-store' });
    const data = await r.json();
    const next = data.items || [];
    const sig = next.map(x => x.name + ':' + x.mtime).join('|');
    const newest = next[0] || null;
    const hadNew = newest && (!items[0] || items[0].name !== newest.name || items[0].mtime !== newest.mtime);

    if (sig !== listSig) {
      listSig = sig;
      items = next;
      renderRail();
    }

    if (!items.length) {
      status.textContent = '暂无图片';
      shot.hidden = true;
      empty.hidden = false;
      selectedName = null;
      return;
    }

    if (followLatest && (hadNew || !selectedName)) {
      showItem(items[0]);
    } else if (selectedName) {
      const cur = items.find(x => x.name === selectedName);
      if (cur) showItem(cur);
      else if (followLatest) showItem(items[0]);
      else {
        // 当前图被删了，停在下一张历史
        showItem(items[0]);
      }
    } else {
      showItem(items[0]);
    }
  } catch (e) {
    status.textContent = '断线，重试中…';
  }
}
tick();
setInterval(tick, 1000);
</script>
</body>
</html>
"""


def make_handler(folder: Path):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            # 安静一点，只打印 API / 错误相关可在需要时打开
            return

        def _send(self, code: int, body: bytes, content_type: str):
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path

            if path in ("/", "/index.html"):
                self._send(200, PAGE_HTML.encode("utf-8"), "text/html; charset=utf-8")
                return

            if path == "/api/latest":
                imgs = list_images(folder)
                if not imgs:
                    payload = {"name": None}
                else:
                    p = imgs[0]
                    payload = {
                        "name": p.name,
                        "mtime": int(p.stat().st_mtime),
                        "size": p.stat().st_size,
                    }
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                self._send(200, body, "application/json; charset=utf-8")
                return

            if path == "/api/list":
                items = []
                for p in list_images(folder)[:100]:
                    items.append(
                        {
                            "name": p.name,
                            "mtime": int(p.stat().st_mtime),
                            "size": p.stat().st_size,
                        }
                    )
                body = json.dumps({"items": items}, ensure_ascii=False).encode("utf-8")
                self._send(200, body, "application/json; charset=utf-8")
                return

            if path == "/img":
                qs = parse_qs(parsed.query)
                name = (qs.get("name") or [""])[0]
                # 防止路径穿越
                safe = Path(name).name
                target = folder / safe
                if not target.is_file() or target.suffix.lower() not in IMAGE_EXT:
                    self._send(404, b"not found", "text/plain")
                    return
                data = target.read_bytes()
                ctype = mimetypes.guess_type(safe)[0] or "application/octet-stream"
                self._send(200, data, ctype)
                return

            self._send(404, b"not found", "text/plain")

    return Handler


def main():
    parser = argparse.ArgumentParser(description="手机浏览器查看电脑最新截图")
    parser.add_argument(
        "--dir",
        type=Path,
        default=default_shot_dir(),
        help="截图目录（默认 Pictures\\Screenshots）",
    )
    parser.add_argument("--port", type=int, default=8765, help="端口，默认 8765")
    parser.add_argument("--host", default="0.0.0.0", help="监听地址")
    args = parser.parse_args()

    folder = args.dir.expanduser().resolve()
    folder.mkdir(parents=True, exist_ok=True)

    handler = make_handler(folder)
    server = ThreadingHTTPServer((args.host, args.port), handler)

    print("=" * 52)
    print("  截图看板已启动")
    print(f"  监视目录: {folder}")
    print("  手机浏览器打开下面任意一个地址：")
    for ip in local_ipv4s() or ["127.0.0.1"]:
        print(f"    http://{ip}:{args.port}/")
    print("  本机预览: http://127.0.0.1:%d/" % args.port)
    print("  结束: Ctrl+C")
    print("=" * 52)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
