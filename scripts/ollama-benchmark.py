#!/usr/bin/env python3
"""
Ollama パフォーマンス比較ベンチマーク
ローカル Ollama vs k3s (Tailscale Ingress) Ollama
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

# ── エンドポイント設定 ──────────────────────────────────────────
ENDPOINTS = {
    "k3s  ": "https://llm-ollama-ingress-ingress.tail0e51e0.ts.net",
    "local": "http://127.0.0.1:11434",
}

# ── ベンチマーク用プロンプト ────────────────────────────────────
PROMPTS = [
    {
        "name": "short (1文)",
        "prompt": "空の色は何ですか？一言で答えてください。",
        "expected_tokens": "~10",
    },
    {
        "name": "medium (説明)",
        "prompt": "Kubernetesとは何か、3文で説明してください。",
        "expected_tokens": "~80",
    },
    {
        "name": "long (コード生成)",
        "prompt": (
            "Pythonでフィボナッチ数列を再帰・ループ・メモ化の3通りで実装し、"
            "それぞれの時間計算量をコメントで示してください。"
        ),
        "expected_tokens": "~200",
    },
]

TIMEOUT = 120  # seconds per request


def unload_model(base_url: str, model: str):
    """モデルをVRAMからアンロードする (keep_alive=0)"""
    url = f"{base_url}/api/generate"
    payload = {"model": model, "prompt": "", "keep_alive": 0}
    try:
        requests.post(url, json=payload, timeout=30, verify=True)
    except Exception:
        pass


def generate(base_url: str, model: str, prompt: str) -> dict:
    """Ollama /api/generate を呼び出してメトリクスを返す"""
    url = f"{base_url}/api/generate"
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0,   # 再現性のため固定
            "seed": 42,
        },
    }
    t0 = time.perf_counter()
    resp = requests.post(url, json=payload, timeout=TIMEOUT, verify=True)
    elapsed = time.perf_counter() - t0
    resp.raise_for_status()
    data = resp.json()

    prompt_tokens = data.get("prompt_eval_count", 0)
    gen_tokens    = data.get("eval_count", 0)
    # Ollama の eval_duration は nanoseconds
    eval_ns       = data.get("eval_duration", 0)
    load_ns       = data.get("load_duration", 0)
    prompt_ns     = data.get("prompt_eval_duration", 0)

    tps = (gen_tokens / (eval_ns / 1e9)) if eval_ns > 0 else 0.0

    return {
        "total_elapsed_s"   : round(elapsed, 3),
        "load_ms"           : round(load_ns / 1e6, 1),
        "prompt_eval_ms"    : round(prompt_ns / 1e6, 1),
        "generate_ms"       : round(eval_ns / 1e6, 1),
        "prompt_tokens"     : prompt_tokens,
        "gen_tokens"        : gen_tokens,
        "tokens_per_sec"    : round(tps, 2),
        "response_preview"  : data.get("response", "")[:80].replace("\n", " "),
    }


def run_benchmark(model: str, runs: int = 3, prompts=None, cold: bool = False, warmup: int = 1):
    """
    cold=False (デフォルト・ウォームベンチ):
      各エンドポイント×プロンプトの先頭で warmup run を実行して破棄し、
      モデルがVRAMに乗った状態で計測する。

    cold=True (コールドスタートベンチ):
      各 run の前にモデルをアンロードし、ロード時間も含めた cold-start を計測する。
    """
    if prompts is None:
        prompts = PROMPTS

    results = {}  # endpoint -> prompt_name -> [metrics]

    for ep_name, base_url in ENDPOINTS.items():
        results[ep_name] = {}
        for p in prompts:
            metrics_list = []

            if not cold and warmup > 0:
                # ── ウォームアップ: モデルをVRAMに乗せてから計測開始 ──
                print(f"  ウォームアップ: {ep_name.strip()} | {p['name']} ...", end="", flush=True)
                try:
                    generate(base_url, model, p["prompt"])
                    print(" 完了 (結果は破棄)")
                except Exception as e:
                    print(f" WARN: {e}")

            for run in range(1, runs + 1):
                if cold:
                    # ── コールドスタート: 毎回アンロードしてからロード ──
                    print(f"  アンロード中: {ep_name.strip()} ...", end="", flush=True)
                    unload_model(base_url, model)
                    print(" 完了")

                label = f"{ep_name} | {p['name']} | run {run}/{runs}"
                print(f"  実行中: {label} ...", end="", flush=True)
                try:
                    m = generate(base_url, model, p["prompt"])
                    metrics_list.append(m)
                    load_info = f"  load={m['load_ms']}ms" if cold else ""
                    print(f" {m['tokens_per_sec']} tok/s  ({m['gen_tokens']} tokens){load_info}")
                except Exception as e:
                    print(f" ERROR: {e}")
                    metrics_list.append(None)

            results[ep_name][p["name"]] = metrics_list

    return results


def print_report(results: dict, model: str, runs: int, cold: bool, warmup: int):
    sep = "─" * 90
    mode = "コールドスタート (run毎にモデルアンロード)" if cold else f"ウォームスタート (先頭{warmup}回ウォームアップ後に計測)"
    print(f"\n{'═'*90}")
    print(f"  Ollama ベンチマーク結果  モデル: {model}  実行回数: {runs}")
    print(f"  計測モード: {mode}")
    print(f"  実施日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'═'*90}\n")

    for p in PROMPTS:
        pname = p["name"]
        print(f"【プロンプト: {pname}】  期待トークン数: {p['expected_tokens']}")
        print(sep)
        header = f"{'エンドポイント':<10} {'tok/s (avg)':>12} {'tok/s (min)':>12} {'tok/s (max)':>12} "
        header += f"{'生成トークン':>12} {'生成ms (avg)':>13} {'全体ms (avg)':>13}"
        print(header)
        print(sep)

        summaries = {}
        for ep_name in ENDPOINTS:
            runs_data = [m for m in results[ep_name].get(pname, []) if m is not None]
            if not runs_data:
                print(f"{ep_name:<10} {'N/A':>12}")
                continue

            tps_list   = [m["tokens_per_sec"] for m in runs_data]
            gen_ms_list = [m["generate_ms"] for m in runs_data]
            total_ms_list = [m["total_elapsed_s"] * 1000 for m in runs_data]
            gen_tok_list  = [m["gen_tokens"] for m in runs_data]

            avg_tps    = round(statistics.mean(tps_list), 2)
            min_tps    = round(min(tps_list), 2)
            max_tps    = round(max(tps_list), 2)
            avg_gen_ms = round(statistics.mean(gen_ms_list), 1)
            avg_tot_ms = round(statistics.mean(total_ms_list), 1)
            avg_gen_tok = round(statistics.mean(gen_tok_list), 1)

            summaries[ep_name] = avg_tps
            print(
                f"{ep_name:<10} {avg_tps:>12} {min_tps:>12} {max_tps:>12} "
                f"{avg_gen_tok:>12} {avg_gen_ms:>13} {avg_tot_ms:>13}"
            )

        # 勝者表示
        if len(summaries) == 2:
            ep_list = list(summaries.items())
            winner, w_tps = max(ep_list, key=lambda x: x[1])
            loser,  l_tps = min(ep_list, key=lambda x: x[1])
            if l_tps > 0:
                ratio = round(w_tps / l_tps, 2)
                print(f"\n  → 勝者: {winner.strip()}  ({ratio}x 高速)")
        print()

    # レスポンスプレビュー
    print(f"{'═'*90}")
    print("  レスポンスプレビュー (最後のrun, 先頭80文字)")
    print(sep)
    for p in PROMPTS:
        pname = p["name"]
        print(f"\n  [{pname}]")
        for ep_name in ENDPOINTS:
            runs_data = [m for m in results[ep_name].get(pname, []) if m is not None]
            if runs_data:
                preview = runs_data[-1]["response_preview"]
                print(f"    {ep_name}: {preview}")
    print(f"\n{'═'*90}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Ollama ローカル vs k3s ベンチマーク",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
計測モード:
  デフォルト (warm): 各エンドポイント×プロンプトの前にウォームアップrunを1回実行して破棄。
                     モデルがVRAMに乗った状態の純粋な推論速度を計測。
  --cold          : 各runの前にモデルをアンロード。ロード時間込みのcold-startを計測。
        """,
    )
    parser.add_argument(
        "--model", "-m",
        default="qwen3.6:35b-a3b-mtp-q4_K_M",
        help="テストするモデル名 (default: qwen3.6:35b-a3b-mtp-q4_K_M)",
    )
    parser.add_argument(
        "--runs", "-r",
        type=int, default=3,
        help="各プロンプトの実行回数 (default: 3)",
    )
    parser.add_argument(
        "--cold",
        action="store_true",
        help="各run前にモデルをアンロードしてcold-startを計測",
    )
    parser.add_argument(
        "--no-warmup",
        action="store_true",
        help="ウォームアップrunをスキップ (--cold時は無効)",
    )
    parser.add_argument(
        "--quick", "-q",
        action="store_true",
        help="shortプロンプトのみ、1回だけ実行 (動作確認用)",
    )
    args = parser.parse_args()

    if args.quick:
        runs = 1
        prompts = [PROMPTS[0]]
    else:
        runs = args.runs
        prompts = PROMPTS

    warmup = 0 if (args.cold or args.no_warmup) else 1

    print(f"\nモデル: {args.model}")
    print(f"実行回数: {runs}  プロンプト数: {len(prompts)}")
    if args.cold:
        print("計測モード: コールドスタート (各run前にモデルアンロード)")
    else:
        print(f"計測モード: ウォームスタート (先頭{warmup}回ウォームアップ後に計測)")
    print(f"エンドポイント:")
    for name, url in ENDPOINTS.items():
        print(f"  {name}: {url}")
    print()

    results = run_benchmark(args.model, runs=runs, prompts=prompts, cold=args.cold, warmup=warmup)
    print_report(results, args.model, runs, cold=args.cold, warmup=warmup)


if __name__ == "__main__":
    main()
