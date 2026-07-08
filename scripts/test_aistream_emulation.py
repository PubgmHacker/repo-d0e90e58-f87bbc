#!/usr/bin/env python3
"""
Emulates the new chatStream() SSE logic against the real OpenRouter API
to verify streaming + reasoning fallback + 429 retry work end-to-end.

Streams via SSE (stream: true), reads 'data: {json}' lines, decodes
OpenRouterStreamChunk-equivalent, prefers delta.content over delta.reasoning.
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

def extract_retry_after(s):
    m = re.search(r'"retry_after_seconds"\s*:\s*(\d+)', s or "")
    return int(m.group(1)) if m else None

def stream_model(model, messages, max_tokens=2048):
    """Returns (tokens_list, status, error_str)."""
    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": max_tokens,
        "stream": True,
    }).encode("utf-8")
    req = urllib.request.Request(
        URL, data=body,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            "HTTP-Referer": "Plink-iOS",
            "X-Title": "plink-ios",
            "Accept": "text/event-stream",
        },
        method="POST",
    )
    try:
        resp = urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        body_str = e.read().decode("utf-8", errors="replace")
        return [], e.code, body_str

    tokens = []
    used_reasoning = False
    used_content = False
    for raw in resp:
        line = raw.decode("utf-8", errors="replace").rstrip()
        if not line.startswith("data: "):
            continue
        payload = line[6:]
        if payload == "[DONE]":
            break
        try:
            chunk = json.loads(payload)
        except Exception:
            continue
        choices = chunk.get("choices", [])
        if not choices:
            continue
        delta = choices[0].get("delta", {})
        c = delta.get("content")
        r = delta.get("reasoning")
        if c:
            tokens.append(c)
            used_content = True
        elif r:
            tokens.append(r)
            used_reasoning = True
    return tokens, 200, None, used_content, used_reasoning

def chat_stream(messages):
    last_error = None
    any_yielded = False
    for candidate in FREE_MODELS:
        for retry in range(3):
            tag = "trying" if retry == 0 else f"retry #{retry}"
            print(f"🤖 AI stream: {tag} {candidate}...")
            try:
                result = stream_model(candidate, messages)
                if len(result) == 5:
                    tokens, status, err, used_content, used_reasoning = result
                else:
                    tokens, status, err = result
                    used_content = used_reasoning = False
            except Exception as e:
                print(f"   exception: {e}")
                last_error = str(e)
                break

            if status == 429 and retry < 2:
                retry_after = extract_retry_after(err) or 5
                retry_after = min(retry_after, 30)
                print(f"   429, backing off {retry_after}s...")
                time.sleep(retry_after)
                last_error = f"429 {candidate}"
                continue
            elif status != 200:
                print(f"   failed: status={status} err={(err or '')[:120]}")
                last_error = f"status {status} {candidate}"
                break

            if tokens:
                full = "".join(tokens)
                print(f"✅ SUCCESS with {candidate} ({len(tokens)} chunks, "
                      f"content={'yes' if used_content else 'no'}, "
                      f"reasoning={'yes' if used_reasoning else 'no'})")
                print(f"   full text (first 300 chars): {full[:300]!r}")
                return full
            else:
                print(f"   200 OK but 0 tokens, moving on")
                last_error = f"empty stream {candidate}"
                break
    print(f"❌ ALL STREAMING MODELS FAILED. last_error={last_error}")
    return None

if __name__ == "__main__":
    print("=" * 70)
    print("Stream Test 1: Greeting")
    print("=" * 70)
    r1 = chat_stream([{"role": "user", "content": "ответь одним словом: привет"}])
    print()
    print("=" * 70)
    print("Stream Test 2: Film recommendation (long answer expected)")
    print("=" * 70)
    SYSTEM = (
        "Ты — ИИ-помощник Плинка, приложения для совместного просмотра видео. "
        "Подбирай фильмы и сериалы. Отвечай на русском, 2-4 предложения."
    )
    r2 = chat_stream([
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": "Посоветуй триллер для вечера субботы"},
    ])
    print()
    if r1 and r2:
        print("🎉 BOTH STREAM TESTS PASSED — chatStream() v4 fix works.")
        sys.exit(0)
    else:
        print("💥 ONE OR BOTH STREAM TESTS FAILED.")
        sys.exit(1)
