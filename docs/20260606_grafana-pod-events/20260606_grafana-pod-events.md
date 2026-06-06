# Grafana Pod監視・Kubernetesイベント表示 設定記録

**日付**: 2026-06-06  
**対象**: monitoring namespace (ArgoCD管理)

---

## 概要

GrafanaでKubernetesの各Podステータスおよびイベントを可視化するため、  
**kube-state-metrics** と **Loki** を追加し、既存の Alloy・Prometheus・Grafana を拡張した。

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                                       │
│                                                                         │
│  ┌──────────────────┐    メトリクス    ┌──────────────┐                 │
│  │ kube-state-      │ ─────────────→ │              │                  │
│  │ metrics          │                │  Prometheus  │ ──→ Grafana      │
│  └──────────────────┘                │              │                  │
│                                      └──────────────┘                  │
│  ┌──────────────────┐    メトリクス         ↑                           │
│  │ Alloy (DaemonSet)│ ─────────────────────┘                           │
│  │ node_exporter    │                                                   │
│  └──────────────────┘                                                   │
│                                                                         │
│  ┌──────────────────┐    イベントログ  ┌──────────────┐                 │
│  │ Alloy (Deployment│ ─────────────→ │    Loki      │ ──→ Grafana      │
│  │ events-collector)│                └──────────────┘                  │
│  └──────────────────┘                                                   │
│         ↑                                                               │
│   Kubernetes Events API                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 変更ファイル一覧

### 新規作成

| ファイル | 内容 |
|---|---|
| `k8s/charts/monitoring/kube-state-metrics/` | kube-state-metrics Helm チャート |
| `k8s/charts/monitoring/loki/` | Loki Helm チャート |
| `k8s/charts/monitoring/alloy/templates/clusterrole.yaml` | Alloy用 ClusterRole |
| `k8s/charts/monitoring/alloy/templates/clusterrolebinding.yaml` | Alloy用 ClusterRoleBinding |
| `k8s/charts/monitoring/alloy/templates/events-configmap.yaml` | イベント収集 Alloy 設定 |
| `k8s/charts/monitoring/alloy/templates/events-deployment.yaml` | イベント収集用 Deployment |
| `k8s/argocd/applications/prd/monitoring/kube-state-metrics.yaml` | ArgoCD Application |
| `k8s/argocd/applications/prd/monitoring/loki.yaml` | ArgoCD Application |

### 変更

| ファイル | 変更内容 |
|---|---|
| `k8s/charts/monitoring/alloy/values.yaml` | Loki URL 追加 |
| `k8s/charts/monitoring/prometheus/templates/configmap.yaml` | kube-state-metrics スクレイプジョブ追加 |
| `k8s/charts/monitoring/grafana/templates/configmap.yaml` | Loki データソース追加 |
| `k8s/charts/monitoring/grafana/templates/dashboard-configmap.yaml` | Pod Overview & Events ダッシュボード追加 |

---

## 追加コンポーネント詳細

### 1. kube-state-metrics

Kubernetes オブジェクトの状態をPrometheusメトリクスとして公開するエクスポーター。

| 項目 | 値 |
|---|---|
| イメージ | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1` |
| デプロイ方式 | Deployment (replicas: 1) |
| ポート | 8080 (metrics), 8081 (telemetry) |
| nodeSelector | `node-role: worker`, `node-type: raspi` |
| RBAC | ClusterRole (pods, events, deployments, etc. の list/watch) |

**主要メトリクス:**

| メトリクス | 内容 |
|---|---|
| `kube_pod_status_phase` | Podのフェーズ (Running/Pending/Failed/Succeeded/Unknown) |
| `kube_pod_container_status_restarts_total` | コンテナの累積再起動回数 |
| `kube_pod_status_ready` | Pod の Ready 状態 |
| `kube_pod_info` | Pod の基本情報 (node, IP等) |

**Prometheusスクレイプ設定:**

```yaml
- job_name: 'kube-state-metrics'
  static_configs:
    - targets: ['kube-state-metrics-kube-state-metrics.monitoring.svc.cluster.local:8080']
```

---

### 2. Loki

Kubernetes イベントをログとして保存するログ集約システム。

| 項目 | 値 |
|---|---|
| イメージ | `grafana/loki:3.0.0` |
| デプロイ方式 | Deployment (replicas: 1), monolithic mode |
| ポート | 3100 (HTTP) |
| ストレージ | Longhorn PVC 5Gi |
| nodeSelector | `node-role: worker`, `node-type: raspi` |

**Loki 設定 (monolithic mode):**

```yaml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
```

---

### 3. Alloy イベントコレクター

Kubernetes Events API を監視し、イベントを Loki へ転送する単一レプリカ Deployment。

> **DaemonSet にしない理由**: `loki.source.kubernetes_events` はリーダー選出を行わないため、  
> DaemonSet で動かすとノード数分のイベントが重複して収集される。

**Alloy 設定 (`events-configmap.yaml`):**

```alloy
loki.source.kubernetes_events "k8s_events" {
  namespaces = []        // 全Namespaceを対象
  job_name   = "k8s-events"
  forward_to = [loki.write.loki.receiver]
}

loki.write "loki" {
  endpoint {
    url = "http://loki-loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
  }
}
```

収集されたイベントには以下のLokiラベルが付与される:

| ラベル | 内容 |
|---|---|
| `job` | `k8s-events` |
| `namespace` | イベント対象オブジェクトのNamespace |

**RBAC (ClusterRole):**

```yaml
rules:
  - apiGroups: [""]
    resources: [events, namespaces, pods]
    verbs: [get, list, watch]
```

---

## Grafana 設定

### データソース

| 名前 | UID | タイプ | URL |
|---|---|---|---|
| Prometheus | `prometheus` | prometheus | `http://prometheus-prometheus:9090` |
| Loki | `loki` | loki | `http://loki-loki.monitoring.svc.cluster.local:3100` |

---

### ダッシュボード: Pod Overview & Events

**UID**: `pod-overview`

**テンプレート変数:**

| 変数 | クエリ | 説明 |
|---|---|---|
| `$namespace` | `label_values(kube_pod_info, namespace)` | 対象Namespace (複数選択可) |
| `$pod` | `label_values(kube_pod_info{namespace=~"$namespace"}, pod)` | 対象Pod (複数選択可) |

**パネル一覧:**

| ID | タイプ | タイトル | データソース | クエリ |
|---|---|---|---|---|
| 1 | table | Pod ステータス一覧 | Prometheus | `kube_pod_status_phase{namespace=~"$namespace", pod=~"$pod"} == 1` |
| 2 | timeseries | CPU 使用量 (Pod別) | Prometheus | `sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{...}[5m]))` |
| 3 | timeseries | メモリ使用量 (Pod別) | Prometheus | `sum by (namespace, pod) (container_memory_working_set_bytes{...})` |
| 4 | timeseries | コンテナ再起動回数 | Prometheus | `sum by (namespace, pod, container) (kube_pod_container_status_restarts_total{...})` |
| 5 | piechart | Pod フェーズ分布 | Prometheus | `count by (phase) (kube_pod_status_phase{namespace=~"$namespace"} == 1)` |
| 6 | logs | Kubernetes イベント | **Loki** | `{job="k8s-events", namespace=~"$namespace"}` |

**Pod ステータステーブルのカラーコード:**

| フェーズ | 色 |
|---|---|
| Running | 🟢 Green |
| Pending | 🟡 Yellow |
| Failed | 🔴 Red |
| Succeeded | 🔵 Blue |
| Unknown | ⚪ Grey |

---

## ArgoCD Application 一覧 (monitoring namespace)

| Application名 | チャートパス | リリース名 |
|---|---|---|
| `monitoring-prometheus` | `k8s/charts/monitoring/prometheus` | `prometheus` |
| `monitoring-grafana` | `k8s/charts/monitoring/grafana` | `grafana` |
| `monitoring-alloy` | `k8s/charts/monitoring/alloy` | `alloy` |
| `monitoring-kube-state-metrics` | `k8s/charts/monitoring/kube-state-metrics` | `kube-state-metrics` |
| `monitoring-loki` | `k8s/charts/monitoring/loki` | `loki` |

---

## サービス名対応表

| コンポーネント | Service名 | FQDN |
|---|---|---|
| Prometheus | `prometheus-prometheus` | `prometheus-prometheus.monitoring.svc.cluster.local:9090` |
| Grafana | `grafana-grafana` | `grafana-grafana.monitoring.svc.cluster.local:3000` |
| Loki | `loki-loki` | `loki-loki.monitoring.svc.cluster.local:3100` |
| kube-state-metrics | `kube-state-metrics-kube-state-metrics` | `kube-state-metrics-kube-state-metrics.monitoring.svc.cluster.local:8080` |
