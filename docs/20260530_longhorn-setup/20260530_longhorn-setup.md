# Longhorn セットアップ作業記録

**日付**: 2026-05-30  
**対象ノード**: raspi02, raspi03, raspi04 (raspi-worker)

---

## 概要

Raspberry Pi ワーカーノード（raspi02〜04）に分散ブロックストレージ **Longhorn v1.7.2** を導入した。  
Ansible で前提パッケージを整備し、Helm wrapper chart + ArgoCD で継続管理する構成とした。

---

## 実施内容

### 1. Ansible: 前提パッケージのインストール

`ansible/roles/k3s/tasks/longhorn.yml` を新規作成し、k3s agent セットアップ前に実行されるよう `main.yml` に組み込んだ。

**インストールパッケージ**

| パッケージ | 用途 |
|---|---|
| `open-iscsi` | Longhorn が使用する iSCSI イニシエーター（必須） |
| `nfs-common` | RWX ボリューム（NFS）サポート |
| `util-linux` | `lsblk` などのディスクユーティリティ |
| `e2fsprogs` | `mkfs.ext4` などのファイルシステムツール |

また、`iscsid` サービスの有効化と `iscsi_tcp` カーネルモジュールの永続ロード（`/etc/modules-load.d/iscsi.conf`）も設定した。

**タスク実行順序**（`k3s/tasks/main.yml`）

```
cgroup.yml → longhorn.yml → agent.yml（k3s agentインストール）
```

> **理由**: Longhornの前提ライブラリはk3s agentが起動する前に揃っている必要がある。

---

### 2. Kubernetes: Helm wrapper chart

`k8s/charts/common/longhorn/` に他のチャート（tailscale-operator 等）と同じ wrapper chart パターンで作成した。

**Chart.yaml**
```yaml
dependencies:
  - name: longhorn
    version: 1.7.2
    repository: https://charts.longhorn.io
```

**values-prd.yaml の主要設定**

| 設定 | 値 | 理由 |
|---|---|---|
| `defaultReplicaCount` | 3 | ワーカー3台（raspi02〜04）でレプリカ3 |
| `persistence.defaultClass` | false | `local-path` との二重デフォルト回避（後述） |
| `nodeSelector` | `node-role: worker, node-type: raspi` | Longhorn コンポーネントをワーカー限定に配置 |

---

### 3. ArgoCD: Application 定義

`k8s/argocd/applications/prd/common/longhorn.yaml` を作成。`app-of-apps-prd` の管理下に置き、Git push で自動デプロイされる構成とした。

---

## 発生した問題と解決策

### 問題1: `longhorn-pre-upgrade` Job が ServiceAccount を見つけられず起動しない

**症状**

```
Error creating: pods "longhorn-pre-upgrade-" is forbidden:
error looking up service account longhorn-system/longhorn-service-account:
serviceaccount "longhorn-service-account" not found
```

**原因**

`longhorn-pre-upgrade` は Helm の `pre-upgrade` フックとして定義されており、ArgoCD はすべての sync をアップグレードとして扱うため毎回実行される。このフックはメインチャートのリソース（ServiceAccount を含む）が適用される**前**に実行される設計であるため、初回インストール時は ServiceAccount が存在せず Pod を起動できない。

**対処**（初回のみ手動）

```bash
kubectl -n longhorn-system create serviceaccount longhorn-service-account
kubectl create clusterrolebinding longhorn-pre-upgrade-temp \
  --clusterrole=cluster-admin \
  --serviceaccount=longhorn-system:longhorn-service-account
```

フック完了後、ArgoCD が正式な RBAC を適用するため一時 ClusterRoleBinding を削除した。

```bash
kubectl delete clusterrolebinding longhorn-pre-upgrade-temp
```

---

### 問題2: `Replace=true` が ServiceAccount を毎 sync で削除する

**症状**

sync のたびに ServiceAccount が消え、`longhorn-pre-upgrade` Job が再度 stuck になる。

**原因**

`syncOptions: Replace=true` は ArgoCD が `kubectl replace`（削除 → 再作成）でリソースを適用する。pre-upgrade フックが実行されるタイミングではメインリソースがまだ適用されていないため、ServiceAccount が存在しない状態が毎回発生する。

**解決策**

`Replace=true` と `SkipHooks=true`（Helm ネイティブフックには効果なし）を削除し、`ServerSideApply=true` のみ残した。

```yaml
syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true   # kubectl apply --server-side でマージ更新
```

`ServerSideApply=true` は既存リソースを削除せずフィールド単位で上書きするため、ServiceAccount が sync をまたいで保持される。

---

### 問題3: StorageClass のデフォルトが二重になる

**症状**

```
local-path (default)   rancher.io/local-path   ...
longhorn (default)     driver.longhorn.io      ...
```

**原因**

Longhorn Helm chart はデフォルトで `storageclass.kubernetes.io/is-default-class: "true"` を付与する。一方 `local-path` は k3s が `objectset` で管理しており、ArgoCD から上書きすると k3s のコントローラーが戻してしまう。

**解決策**

Longhorn 側でデフォルト指定を無効化した（`values-prd.yaml`）。

```yaml
persistence:
  defaultClass: false
```

これにより `local-path` がデフォルトのまま維持され、Longhorn を使用するワークロードは明示的に `storageClassName: longhorn` を指定する。

---

### 問題4: `EngineImage`, `Engine`, CRD の OutOfSync

**症状**

ArgoCD UI で `engineimages.longhorn.io`, `engines.longhorn.io`, CRD（`preserveUnknownFields: false` 等）が OutOfSync と表示される。

**原因**

- `EngineImage`, `Engine`: Longhorn コントローラーが動作中に `status` や `spec.nodeDeploymentMap` を動的に書き換えるため、Helm の期待値と乖離する。
- CRD: Kubernetes apiserver が `spec.preserveUnknownFields` などのフィールドを自動付与するため差分が生じる。

**解決策**

`ignoreDifferences` で該当フィールドを差分検知から除外した。

```yaml
ignoreDifferences:
  - group: ""
    kind: ConfigMap
    name: longhorn-default-setting
    jsonPointers:
      - /data
  - group: longhorn.io
    kind: EngineImage
    jsonPointers:
      - /status
      - /spec/nodeDeploymentMap
  - group: longhorn.io
    kind: Engine
    jsonPointers:
      - /status
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jsonPointers:
      - /spec/preserveUnknownFields
      - /status
```

---

## 最終的な構成ファイル

| ファイル | 内容 |
|---|---|
| `ansible/roles/k3s/tasks/longhorn.yml` | 前提パッケージインストール |
| `ansible/roles/k3s/tasks/main.yml` | longhorn.yml を agent.yml の前に include |
| `k8s/charts/common/longhorn/Chart.yaml` | Longhorn 1.7.2 wrapper chart |
| `k8s/charts/common/longhorn/values-prd.yaml` | レプリカ数・nodeSelector・defaultClass 設定 |
| `k8s/argocd/applications/prd/common/longhorn.yaml` | ArgoCD Application（ignoreDifferences 含む） |

---

## Prometheus メトリクスストレージの Longhorn 移行（2026-05-31）

### 実施内容

Prometheus のデータ保存先を `emptyDir`（Pod 削除でデータ消失）から Longhorn PVC に変更した。  
また、monitoring 系 Pod の配置ノードを raspi-worker に統一した。

**変更ファイル**

| ファイル | 変更内容 |
|---|---|
| `k8s/charts/monitoring/prometheus/templates/pvc.yaml` | 新規作成。10Gi / storageClassName: longhorn |
| `k8s/charts/monitoring/prometheus/templates/deployment.yaml` | `emptyDir` → PVC、nodeSelector・securityContext 追加 |
| `k8s/charts/monitoring/prometheus/values.yaml` | storage・nodeSelector・podSecurityContext 設定追加 |
| `k8s/charts/monitoring/grafana/templates/deployment.yaml` | nodeSelector 追加 |
| `k8s/charts/monitoring/grafana/values.yaml` | nodeSelector 設定追加 |

> Alloy（DaemonSet）は各ノードの kubelet メトリクスを収集するため nodeSelector を設定せず全ノードで稼働させる。

---

### 発生した問題と解決策

#### 問題A: ubuntu-pc へスケジュールされ Longhorn PVC がアタッチできない

**症状**

```
AttachVolume.Attach failed: node.longhorn.io "obitwo-ubuntu-machine01" not found
```

**原因**

Prometheus Deployment に nodeSelector がなく、ubuntu-pc にスケジュールされた。  
ubuntu-pc は Longhorn の管理ノード（`node-type=raspi`）ではないため、Longhorn がボリュームをアタッチできない。

**解決策**

`values.yaml` に nodeSelector を追加し、raspi-worker のみにスケジュールさせた。

```yaml
nodeSelector:
  node-role: worker
  node-type: raspi
```

---

#### 問題B: permission denied でコンテナがクラッシュ（CrashLoopBackOff）

**症状**

```
open /prometheus/queries.active: permission denied
panic: Unable to create mmap-ed active query log
```

**原因**

Longhorn PVC はデフォルト root 所有で作成される。Prometheus は UID 65534（nobody）で動作するため、マウントされた `/prometheus` ディレクトリに書き込めない。

**解決策**

Pod の `securityContext` に `fsGroup: 65534` を設定した。Kubernetes はボリュームマウント時にディレクトリのグループ所有権を指定した GID に変更する。

```yaml
podSecurityContext:
  fsGroup: 65534
  runAsUser: 65534
  runAsNonRoot: true
```

---

#### 問題C: Multi-Attach error で新 Pod が起動できない

**症状**

```
Multi-Attach error for volume "pvc-xxxx": Volume is already used by pod prometheus-prometheus-xxxxx
```

**原因**

Longhorn PVC は ReadWriteOnce（1ノード同時アタッチ）のため、旧Pod（CrashLoopBackOff 状態）が PVC を保持したまま新Pod が起動しようとすると競合が発生する。

**解決策**

旧Pod を手動削除して PVC を解放した。

```bash
kubectl delete pod <旧Pod名> -n monitoring
```

---

## 今後の注意点

- **Longhorn のバージョンアップ時**: `pre-upgrade` フックが実行されデータ移行チェックが行われる。SA はすでに存在するため自動で完了するはずだが、メジャーバージョンアップ時は Longhorn 公式のアップグレード手順を確認すること。
- **Longhorn UI**: `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80` でアクセス可能。
- **PVC の使い方**: Longhorn を使用する場合は明示的に `storageClassName: longhorn` を指定する。
