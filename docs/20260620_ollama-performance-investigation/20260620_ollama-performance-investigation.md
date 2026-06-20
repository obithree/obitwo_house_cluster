# Ollama パフォーマンス差異調査計画

**作成日**: 2026-06-20  
**対象モデル**: `qwen3.6:35b-a3b-mtp-q4_K_M`  
**観測された差異**: ローカル Ollama ~174 tok/s vs k3s Ollama ~50 tok/s（約 3.5x 差）

---

## 1. 事前調査で判明した事実

### 環境構成

| 項目 | ローカル Ollama | k3s Ollama |
|---|---|---|
| エンドポイント | `http://127.0.0.1:11434` | Tailscale Ingress (HTTPS) |
| バージョン | 0.30.10 | 0.30.10 |
| 動作形態 | systemd サービス | Kubernetes Pod (同一ノード: obitwopc) |
| GPU | RTX 5070 Ti (16GB) + RTX 3080 (20GB) を両方使用 | 同上 (`nvidia.com/gpu: 2` を要求) |
| GPU レイヤーオフロード | **42/42 層** → VRAM 合計 ~20.4 GB | **41/42 層** → VRAM 合計 ~4.9 GB |
| KV キャッシュ型 | f16 (デフォルト) | **q8_0** (明示設定) |
| 並列リクエスト数 | 設定なし（デフォルト: 1） | `OLLAMA_NUM_PARALLEL=2` |
| 同時ロードモデル数 | 設定なし（デフォルト: 1） | `OLLAMA_MAX_LOADED_MODELS=2` |
| Flash Attention | 設定なし | `OLLAMA_FLASH_ATTENTION=1` |
| MTP 投機的デコード | 有効（ログ確認済み） | 有効（ログ確認済み、acc rate ~80%） |

### ベンチマーク実施時の VRAM 使用状況（事前調査時点）

| GPU | 合計 | 空き | 使用中 |
|---|---|---|---|
| RTX 5070 Ti | 16,303 MiB | 1,958 MiB | **14,345 MiB** |
| RTX 3080 | 20,480 MiB | 1,000 MiB | **19,480 MiB** |

→ ローカル Ollama が約 20.4 GB のモデルをほぼ全量 VRAM に展開しており、
  k3s Ollama が後から起動する際に残り VRAM が不足し、大半を **システム RAM で処理** していた可能性が高い。

---

## 2. 性能差の仮説（優先度順）

### 仮説 A: VRAM 競合による CPU オフロード【最有力】

**根拠**:
- 事前調査時の k3s の GPU モデルバッファは **CUDA0: 546 MiB + CUDA1: 4,398 MiB = 約 4.9 GB** にとどまる
- モデルサイズ 22.6 GB のうち **約 17.7 GB がシステム RAM** に置かれた状態で推論
- 両サービスが **同一物理ノード上の GPU を共有** しており、先にロードしたローカルが大半の VRAM を確保

**検証方法**:
- ローカル Ollama を停止した状態で k3s 単独ベンチマークを実施し、GPU バッファサイズを確認
- `nvidia-smi dmon` でリアルタイム GPU メモリ使用量を監視しながらベンチマーク

### 仮説 B: `OLLAMA_NUM_PARALLEL=2` による VRAM 分割

**根拠**:
- k3s は 2 並列リクエスト分の KV キャッシュをあらかじめ確保するため、モデル本体に使える VRAM が減少
- CUDA0 の compute buffer が k3s 448 MB vs ローカル 424 MB と若干大きい

**検証方法**:
- k3s の `OLLAMA_NUM_PARALLEL=1` に変更して再ベンチマーク

### 仮説 C: `OLLAMA_KV_CACHE_TYPE=q8_0` の影響

**根拠**:
- k3s では KV キャッシュを q8_0（8bit 量子化）で格納しており、VRAM 節約になる一方で演算に変換オーバーヘッドが発生する可能性がある
- KV バッファサイズ: k3s 340 MB (q8_0) vs ローカル 640 MB (f16)

**検証方法**:
- k3s で `OLLAMA_KV_CACHE_TYPE` を `f16` に変更して再ベンチマーク（VRAM が充分な状態で実施）

### 仮説 D: Tailscale Ingress のネットワークオーバーヘッド

**根拠**:
- k3s はベンチマークスクリプトが外部から HTTPS 経由でアクセスするため、RTT が加算される
- ただし Ollama の `eval_duration`（純推論時間）は API レスポンス本体に含まれており、ネットワーク遅延を除いた値を確認できる

**検証方法**:
- `eval_duration` ベースの tok/s と `total_elapsed_s` ベースの tok/s を分離して比較
- 同一ノード上の Pod IP（ClusterIP）に直接アクセスするパターンも試す

### 仮説 E: CPU リソース制限（cgroups）による スロットリング

**根拠**:
- k3s Pod には `cpu limit: 16000m` が設定されており、CPU バウンドな処理（CPU オフロード発生時）でスロットルされる可能性がある

**検証方法**:
- k3s Pod の `kubectl top pod` と `cpu throttling` 統計を確認
- CPU オフロードが発生している場合に限り顕著な影響が出る

---

## 3. 調査手順

### Phase 1: VRAM 競合の確認（仮説 A の検証）

1. ローカル Ollama を停止: `sudo systemctl stop ollama.service`
2. `nvidia-smi` で VRAM の空き容量を確認
3. k3s Ollama を再起動してモデルをロードし直す: Pod を削除して再起動
4. `kubectl logs` でロード後の GPU バッファサイズを確認
5. k3s 単独でベンチマーク実施
6. ローカル Ollama を再起動して同条件でベンチマーク

### Phase 2: k3s 設定パラメータの個別検証（仮説 B・C の検証）

k3s Ollama の Helm values を一項目ずつ変更してベンチマーク比較:

| 試験番号 | 変更内容 | 目的 |
|---|---|---|
| 2-1 | `OLLAMA_NUM_PARALLEL: 1` | 並列数の影響を切り分け |
| 2-2 | `OLLAMA_KV_CACHE_TYPE` を削除（f16 に戻す） | KV キャッシュ量子化の影響 |
| 2-3 | 2-1 + 2-2 を両方適用 | 複合効果の確認 |

### Phase 3: ネットワークオーバーヘッドの定量化（仮説 D の検証）

1. ベンチマークスクリプトを修正し `eval_duration` 由来の tok/s を記録済み（現状維持）
2. ClusterIP (`http://10.43.19.187:11434`) 経由でのベンチマークを追加し Tailscale 経由と比較

### Phase 4: 結論と最適化案の策定

上記フェーズの結果をもとに:
- 性能差の主因を特定
- k3s Ollama の設定最適化案を提示
- ローカル Ollama を停止した場合のトレードオフを整理

---

## 4. 期待される成果

- k3s Ollama の tok/s がローカルと同等（~150 tok/s 以上）になるか否かの確認
- 設定変更のみで改善できる範囲の特定
- ハードウェアアーキテクチャ上の根本的な制約（GPU 共有）の明確化

---

## 5. 調査結果

### Phase 1: VRAM競合の確認 ✅

**ローカルOllama停止 → k3s単独でのVRAM使用状況**

| GPU | 合計 | 空き | 使用中 |
|---|---|---|---|
| RTX 5070 Ti | 16,303 MiB | 14,614 MiB | 1,689 MiB |
| RTX 3080 | 20,480 MiB | 20,041 MiB | 439 MiB |

**k3s単独でのモデルGPUバッファ（VRAM空き状態）**

| | VRAM競合あり（事前調査） | VRAM競合なし（Phase 1） |
|---|---|---|
| CUDA0 model buffer | 546 MiB | **8,781 MiB** |
| CUDA1 model buffer | 4,398 MiB | **11,646 MiB** |
| CPU_Mapped buffer | 20,293 MiB | 272 MiB |
| **k3s tok/s** | **~50 tok/s** | **~163 tok/s** |

**結論**: VRAM競合なし状態でk3sが50→163 tok/s（**3.3x向上**）。
VRAM競合が主因であることが確定。先にロードしたサービスがVRAMを先占し、後発がほぼRAM推論になる。

---

### Phase 2: k3s設定パラメータの個別検証 ✅

計測条件: VRAM競合なし（ローカルOllama停止状態）、short promptで3回計測の平均

| 試験 | NUM_PARALLEL | KV_CACHE_TYPE | tok/s (avg) | 変化 |
|---|---|---|---|---|
| ベースライン | 2 | q8_0 | 163.3 | - |
| 2-1 | **1** | q8_0 | 164.0 | +0.7（誤差範囲） |
| 2-2/2-3 | 1 | **f16** | 172.5 | **+9.2 (+5.6%)** |

- `OLLAMA_NUM_PARALLEL`: **影響なし**（シングルリクエストベンチマークでは差が出ない）
- `OLLAMA_KV_CACHE_TYPE=q8_0`: **約5〜6% の性能低下**。q8_0に変換するオーバーヘッドが発生

---

### Phase 3: ネットワークオーバーヘッドの定量化 ✅

計測条件: VRAM競合なし、KV_CACHE=f16、NUM_PARALLEL=1

| アクセス方法 | eval tok/s（純推論） | wall tok/s（実経過） | ネット遅延 |
|---|---|---|---|
| Tailscale Ingress (HTTPS) | 174.0 | 148.4 | **~240 ms** |
| ClusterIP 直接 (HTTP) | 173.1 | 150.6 | **~205 ms** |

- 純推論速度（`eval_duration`ベース）は **両者とも同等**（~173-174 tok/s）
- Tailscale経由は ClusterIP 比で **+35 ms** のオーバーヘッド（TLSハンドシェイク等）
- レスポンス全体の体感差はネット遅延 ~240 ms 程度で実用上問題なし

---

### VRAM競合状態での逆転現象

ローカルOllama再起動後（k3sが先にVRAMを占有済み）:

| エンドポイント | tok/s | 備考 |
|---|---|---|
| **ローカル** (後発) | **~49 tok/s** | VRAMを追い出され ~20 GB をRAMで処理 |
| **k3s** (先占) | **~172 tok/s** | VRAM 20 GB をフル利用 |

→ 性能差は「ローカル vs k3s」ではなく **「先にロードした方 vs 後からロードした方」** の差であることが確定。

---

### Phase 4: 結論と最適化案

#### 性能差の主因

1. **【決定的】VRAM競合** ― 同一物理ノード上でローカルOllamaとk3s OllamaがGPUを共有しており、先にモデルをロードしたサービスが ~20 GB のVRAMを先占する。後発サービスは残り ~4.9 GB しか使えず残りをRAM処理するため **約3.3x の速度差**が生じる。

2. **【軽微】KV_CACHE_TYPE=q8_0** ― q8_0量子化キャッシュは約5〜6%の性能低下をもたらす。

3. **【無影響】OLLAMA_NUM_PARALLEL** ― シングルリクエスト速度には影響なし。

4. **【軽微】Tailscaleネットワーク遅延** ― 純推論速度には影響なし。レスポンス取得に +35 ms 程度。

#### 最適化対応

| 対応 | 効果 | 採用 |
|---|---|---|
| `OLLAMA_KV_CACHE_TYPE` を `f16` に変更 | +5〜6% 向上 | ✅ 実施済み |
| ローカルOllamaを停止してk3sに一本化 | VRAMを独占できる | 検討余地あり |
| ローカルOllamaとk3s Ollamaで **異なるモデル** を分担 | VRAM競合を回避 | 推奨 |
| k3s OllamaをGPUの片方だけに限定（`NVIDIA_VISIBLE_DEVICES`） | 競合範囲を限定 | 検討余地あり |
