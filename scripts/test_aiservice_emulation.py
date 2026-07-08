#!/usr/bin/env python3
"""
Emulates the new Plink AIService.chat() logic against the real OpenRouter API
to verify the v4 fix actually works end-to-end before the user rebuilds the iOS app.

Mirrors:
  - attemptOrder construction
  - 3 retries per model on 429
  - retry_after_seconds parsing (default 5s, cap 30s)
  - max_tokens=2048
  - content fallback to reasoning
  - empty-content-as-failure
"""
import json
import re
import sys
import time
import urllib.request
import urllib.error

API_KEY = "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"
URL = "https://openrouter.ai/api/v1/chat/completions"

FREE_MODELS = [
    "openrouter/free",
    "google/gemma-4-31b-it:free",
    "qwen/qwen3-next-80b-a3b-instruct:free",
    "openai/gpt-oss-120b:free",
    "nvidia/nemotron-3-super-120b-a12b:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "meta-llama/llama-3.2-3b-instruct:free",
]

def extract_retry_after(msg: str):
    m = re.search(r'"retry_after_seconds"\s*:\s*(\d+)', msg)
    if m:
        return int(m.group(1))
    return None

def call_model(model: str, messages: list, max_tokens: int = 2048):
    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": max_tokens,
    }).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=body,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            "HTTP-Referer": "Plink-iOS",
            "X-Title": "plink-ios",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return resp.status, data, None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, None, body

def chat(messages: list, max_tokens: int = 2048):
    last_error = None
    for i, candidate in enumerate(FREE_MODELS):
        for retry in range(3):
            tag = "trying" if retry == 0 else f"retry #{retry}"
            print(f"🤖 AI: {tag} {candidate}...")
            status, data, err_body = call_model(candidate, messages, max_tokens)
            if status == 200 and data:
                choices = data.get("choices", [])
                if not choices:
                    print(f"   no choices, moving on")
                    last_error = f"empty choices from {candidate}"
                    break
                msg = choices[0].get("message", {})
                content = msg.get("content")
                reasoning = msg.get("reasoning")
                result = content or reasoning or ""
                if result.strip():
                    print(f"✅ SUCCESS with {candidate}")
                    print(f"   content (first 200 chars): {result[:200]!r}")
                    if reasoning and not content:
                        print(f"   ⚠️  content was null, fell back to reasoning")
                    return result
                else:
                    print(f"   200 OK but empty content, moving on")
                    last_error = f"empty content from {candidate}"
                    break
            elif status == 429 and retry < 2:
                retry_after = extract_retry_after(err_body or "") or 5
                retry_after = min(retry_after, 30)
                print(f"   429 rate-limited, backing off {retry_after}s...")
                time.sleep(retry_after)
                last_error = f"429 from {candidate}"
                continue
            else:
                print(f"   failed: status={status} body={(err_body or '')[:120]}")
                last_error = f"status {status} from {candidate}"
                break  # non-429 → move to next model
    print(f"❌ ALL MODELS FAILED. last_error={last_error}")
    return None

if __name__ == "__main__":
    print("=" * 70)
    print("Test 1: Simple greeting")
    print("=" * 70)
    r1 = chat([{"role": "user", "content": "ответь одним словом: привет"}])
    print()
    print("=" * 70)
    print("Test 2: Film recommendation (the actual Plink use case)")
    print("=" * 70)
    SYSTEM = (
        "Ты — ИИ-помощник Плинка, приложения для совместного просмотра видео. "
        "Подбирай фильмы и сериалы. Отвечай кратко на русском."
    )
    r2 = chat([
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": "Посоветуй комедию для вечера с друзьями"},
    ])
    print()
    if r1 and r2:
        print("🎉 BOTH TESTS PASSED — v4 fix works end-to-end.")
        sys.exit(0)
    else:
        print("💥 ONE OR BOTH TESTS FAILED — review the log above.")
        sys.exit(1)
