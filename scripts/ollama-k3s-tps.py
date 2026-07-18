#!/usr/bin/env python3
"""
k3s Ollama のトークン速度 (tokens/sec) を計測するスクリプト
ローカルOllamaとの比較はしない。
"""

import json
import time
import statistics
import argparse
import sys
from datetime import datetime

try:
    import requests
except ImportError:
    print("requests が必要です: pip install requests")
    sys.exit(1)

# ── エンドポイント設定 (k3s Ollama only) ──────────────────────
BASE_URL = "https://llm-ollama-ingress-ingress.tail0e51e0.ts.net"

# ベンチマーク用プロンプト
PROMPTS = [
    {"name": "short", "prompt": "空の色は何ですか？一言で答えてください。"},
    {"name": "medium", "prompt": "Kubernetesとは何か、3文で説明してください。"},
    {
        "name": "long",
        "prompt": (
            "Pythonでフィボナッチ数列を再帰・ループ・メモ化の3通りで実装し、"
            "それぞれの時間計算量をコメントで示してください。"
        ),
    },
]

HEADERS = {"Content-Type": "application/json"}

TIMEOUT = 300


def generate(base_url: str, model: str, prompt: str, stream: bool = False) -> dict:
    """Ollama /api/generate を呼び出してメトリクスを返す"""
    url = f"{base_url}/api/generate"
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": stream,
        "options": {"temperature": 0, "seed": 42},
    }
    t0 = time.perf_counter()
    resp = requests.post(url, json=payload, timeout=TIMEOUT)
    elapsed = time.perf_counter() - t0
    resp.raise_for_status()
    data = resp.json()

    gen_tokens = int(data.get("eval_count", 0))
    prompt_tokens = int(data.get("prompt_eval_count", 0))
    eval_ns = int(data.get("eval_duration", 0))
    load_ns = int(data.get("load_duration", 0))
    prompt_ns = int(data.get("prompt_eval_duration", 0))

    # tokens/sec (純推論速度)
    tps = (gen_tokens / (eval_ns / 1e9)) if eval_ns > 0 else 0.0

    return {
        "total_elapsed_s": round(elapsed, 3),
        "load_ms": round(load_ns / 1e6, 1),
        "prompt_eval_ms": round(prompt_ns / 1e6, 1),
        "generate_ms": round(eval_ns / 1e6, 1),
        "prompt_tokens": prompt_tokens,
        "gen_tokens": gen_tokens,
        "tokens_per_sec": round(tps, 2),
    }


def get_info(base_url: str) -> dict:
    """Ollama のモデル情報 (stats) を取得"""
    url = f"{base_url}/api/tags"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        pass
    return {}


def run_bench(model: str, runs: int, prompts=None):
    """ベンチマークを実行"""
    if prompts is None:
        prompts = PROMPTS

    print(f"モデル: {model}")
    print(f"エンドポイント: {BASE_URL}")
    print(f"実行回数: {runs} | 実施日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)

    # まずモデルリストを確認
    info = get_info(BASE_URL)
    if info:
        model_names = [m["name"] for m in info.get("models", [])]
        if not model_names:
            print("\n[警告]: models が空。モデルがロードされていない可能性があります。\n")
        else:
            print(f"ロード済みモデル: {model_names}\n")

    all_results = {}
    for p in prompts:
        pname = p["name"]
        tps_list = []
        
        for run in range(1, runs + 1):
            print(f"[{pname}] run {run}/{runs} ... ", end="", flush=True)
            try:
                m = generate(BASE_URL, model, p["prompt"])
                tps_list.append(m)
                label = f"tok/s: {m['tokens_per_sec']}, "
                label += f"生成: {m['gen_tokens']} tok, "
                label += f"{m['generate_ms']}ms, 全体: {m['total_elapsed_s']}s"
                print(label)
            except Exception as e:
                print(f"ERROR: {e}")
        if tps_list:
            all_results[pname] = tps_list

    # レポート表示
    print("\n" + "=" * 80)
    print("  計測結果サマリー")
    print("=" * 80)
    for pname, results in all_results.items():
        tps_vals = [r["tokens_per_sec"] for r in results]
        gen_mins = [r["generate_ms"] for r in results]
        total_s   = [r["total_elapsed_s"] for r in results]
        avg_tps  = round(statistics.mean(tps_vals), 2)
        min_tps  = round(min(tps_vals), 2)
        max_tps  = round(max(tps_vals), 2)
        print(f"\n  【{pname}】")
        print(f"    tok/s:   avg={avg_tps}, min={min_tps}, max={max_tps}")
        print(f"    生成時間: avg={round(statistics.mean(gen_mins), 1)}ms, "
              f"range=[{min(gen_mins)}, {max(gen_mins)}]")
        print(f"    全体時間: avg={round(statistics.mean(total_s), 3)}s")

    print("\n" + "=" * 80)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="k3s Ollama トークン速度計測")
    parser.add_argument("-m", "--model", default="qwen3.6:35b-a3b-mtp-q4_K_M")
    parser.add_argument("-r", "--runs", type=int, default=3, help="実行回数 (default: 3)")
    args = parser.parse_args()
    run_bench(args.model, args.runs)
