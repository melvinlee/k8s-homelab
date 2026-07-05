# Langfuse

[Langfuse](https://langfuse.com/) — open-source LLM observability / tracing — deployed
via the `langfuse/langfuse` Helm chart (v1.5.37, app 3.201.1).

Langfuse v3 is not a single container; it brings four bundled backing stores, all run
single-replica here and slimmed down from the chart's production HA defaults
(`clickhouse` alone defaults to 3 replicas / `2xlarge` ≈ 7 CPU / 20Gi):

| Component | Purpose | Workload |
|---|---|---|
| PostgreSQL | transactional / config data | `langfuse-postgresql` |
| ClickHouse | traces/observations OLAP store | `langfuse-clickhouse` |
| Valkey (Redis) | queue + cache | `langfuse-redis` |
| MinIO (S3) | event & media blob storage | `langfuse-s3` |
| langfuse web/worker | app + async worker | `langfuse-web`, `langfuse-worker` |

ClickHouse runs as a single node, so the chart sets `CLICKHOUSE_CLUSTER_ENABLED=false`
(non-replicated tables) and the bundled Zookeeper is disabled — no coordinator needed.

All PVCs land on `longhorn` via `global.defaultStorageClass`. The app is exposed at
`http://langfuse.home` via an HTTPRoute on the homelab Gateway; external-dns syncs the
hostname to Pi-hole.

## Secrets

`resources/secret.yaml` is **gitignored** (`apps/ai/releases/*/resources/secret.yaml`) and
merged on top of `values.yaml` by `helmfile.yaml`. It holds `salt`, `nextauth.secret`,
`encryptionKey`, and the postgresql/clickhouse/redis/s3 passwords. Regenerate with:

```bash
openssl rand -base64 32   # salt, nextauth.secret
openssl rand -hex 32      # encryptionKey (must be 64 hex chars)
openssl rand -hex 16      # store passwords (hex avoids URL-encoding issues)
```

## Deploy

Applied directly (like the observability stack), **not** wired into the root
`infrastructure/helmfile.yaml`:

```bash
cd apps/ai && helmfile -f releases/langfuse/helmfile.yaml apply
# or the whole apps/ai aggregate:
cd apps/ai && helmfile apply
```

First sync runs PostgreSQL + ClickHouse migrations and can take several minutes
(the helmfile `timeout` is raised to 900s for this reason).

## Verify

```bash
kubectl get pods -n langfuse                       # all Ready
kubectl get httproute -n langfuse                  # Accepted + Programmed
kubectl logs -n langfuse deploy/langfuse-web       # migrations / startup
```

Browse to `http://langfuse.home`, create the first account (sign-up is open).
Consider setting `langfuse.features.signUpDisabled: true` afterwards to lock it down.

## Storage sizing & data retention (issue #69)

On 2026-07-03 the `data-langfuse-clickhouse-shard0-0` PVC hit **100% of its 20Gi**,
ClickHouse stopped accepting writes (`Cannot reserve ... not enough space`), and
`langfuse-worker` began dropping ingested records.

**Root cause — not what it looked like.** The volume was **not** filled by Langfuse
trace data (that was only ~360 KiB). It filled with ClickHouse's **own internal
system-log tables**, dominated by `system.trace_log` (~892M rows / 16 GiB in 18 days)
written by the always-on query profiler sampling every `langfuse-worker` query thread.
~19 GiB of that sat in **orphaned `*_log_0` tables** left behind when the #67 ClickHouse
25.2 → 25.7 image bump renamed the system-log tables on a schema change. The fix has
three parts.

### 1. PVC size — resized 20Gi → 40Gi

`clickhouse.persistence.size` in `values.yaml` is **40Gi**. Longhorn supports
online expansion (`allowVolumeExpansion=true`), so the live PVC was grown without
downtime:

```bash
kubectl -n langfuse patch pvc data-langfuse-clickhouse-shard0-0 \
  --type merge -p '{"spec":{"resources":{"requests":{"storage":"40Gi"}}}}'
# Longhorn expands the block device + filesystem online; watch:
kubectl -n langfuse get pvc data-langfuse-clickhouse-shard0-0 -w   # CAPACITY -> 40Gi
```

> **Immutable `volumeClaimTemplate`:** a StatefulSet's `volumeClaimTemplates` is
> immutable, so bumping `persistence.size` in `values.yaml` alone will **not**
> resize an existing PVC and a plain `helmfile apply` **errors** on the template
> diff (confirmed via `helmfile diff` — the only change is `storage: 20Gi → 40Gi`).
> Patch the live PVC directly (above). To make `helmfile apply` converge cleanly,
> recreate the STS keeping the running pod + data:
>
> ```bash
> kubectl -n langfuse delete statefulset langfuse-clickhouse-shard0 --cascade=orphan
> cd apps/ai && helmfile -f releases/langfuse/helmfile.yaml apply   # re-adopts the pod at 40Gi
> ```
>
> This recreate is also what converges the §2 ClickHouse config-mount volumes into
> the live STS (they are new pod-template additions on top of the immutable template
> change), so `helmfile apply` alone cannot land them either.

### 2. Bound ClickHouse system-log growth (the root-cause fix)

`values.yaml` adds two `clickhouse` overrides (both mount into `conf.d`/`users.d`
and take effect when ClickHouse **(re)starts**):

- `usersExtraOverrides` turns the sampling **query profiler off**
  (`query_profiler_real_time_period_ns` / `query_profiler_cpu_time_period_ns = 0`)
  so `system.trace_log` stops growing at the source — a homelab OLAP backend does
  not need query profiling.
- `extraOverrides` puts a **3-day TTL** on the noisy `*_log` tables (`trace_log`,
  `text_log`, `metric_log`, `asynchronous_metric_log`, `query_log`, …) as a backstop.

The **running** pod was remediated live (no restart): drop the orphaned `*_log_0`
tables to reclaim the ~19 GiB immediately, and TTL the active tables. These touch
only ClickHouse-internal diagnostic tables — no Langfuse data:

```bash
CH_PASS=$(kubectl -n langfuse get secret langfuse-clickhouse -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl -n langfuse exec -i langfuse-clickhouse-shard0-0 -c clickhouse -- \
  clickhouse-client --password "$CH_PASS" --multiquery "
    DROP TABLE IF EXISTS system.trace_log_0 SYNC;
    DROP TABLE IF EXISTS system.text_log_0 SYNC;
    DROP TABLE IF EXISTS system.metric_log_0 SYNC;
    DROP TABLE IF EXISTS system.opentelemetry_span_log_0 SYNC;
    DROP TABLE IF EXISTS system.query_log_0 SYNC;
    DROP TABLE IF EXISTS system.part_log_0 SYNC;
    ALTER TABLE system.trace_log             MODIFY TTL event_date + INTERVAL 3 DAY;
    ALTER TABLE system.text_log              MODIFY TTL event_date + INTERVAL 3 DAY;
    ALTER TABLE system.metric_log            MODIFY TTL event_date + INTERVAL 3 DAY;
    ALTER TABLE system.asynchronous_metric_log MODIFY TTL event_date + INTERVAL 3 DAY;"
```

Until the STS is recreated (§1) to mount the `values.yaml` overrides, the live SQL
above is the source of truth for the running pod (profiler stays on but the 3-day
TTL caps `trace_log`).

### 3. Langfuse data retention — 30 days (bounds actual trace data)

Independently of the system logs, Langfuse's **own** trace data is bounded by
**Langfuse's built-in per-project data retention**, not a raw ClickHouse TTL. This is
the authoritative mechanism for app data: its nightly job deletes expired **traces,
observations, scores, and their S3 media/event blobs** together (consistent across
ClickHouse + S3 + Postgres). A bare ClickHouse `TTL` on the Langfuse tables was
rejected — it would prune ClickHouse rows only, orphaning S3 blobs + Postgres
references, and Langfuse manages that schema via migrations that would fight a
hand-applied TTL.

- **Window: 30 days** (min allowed is 3). Chosen for a homelab — keeps ClickHouse
  comfortably under the 40Gi volume.
- Retention is a **per-project** setting stored in Postgres (`projects.retention_days`),
  **not** a Helm value. It is set on the `claude-code` project:

  ```bash
  PG_PASS=$(kubectl -n langfuse get secret langfuse-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)
  # inspect / change the window:
  kubectl -n langfuse exec langfuse-postgresql-0 -- env PGPASSWORD="$PG_PASS" \
    psql -U postgres -d postgres_langfuse -c \
    "UPDATE projects SET retention_days = 30 WHERE name = 'claude-code';"
  ```

  Equivalent UI path: **langfuse.home → Project Settings → Data Retention**.
  The worker enforces it via its `data-retention-processing-queue` (scans projects
  with `retention_days` set) + `data-retention-queue` (executes deletions), nightly.

> **Re-provisioning caveat:** `LANGFUSE_INIT_PROJECT_RETENTION` only applies when a
> project is **created** headlessly (with `LANGFUSE_INIT_PROJECT_ID`); it does not
> retrofit the existing UI-created project. If the Postgres volume is ever wiped and
> the project recreated, re-apply the `retention_days` value above.

### Verifying the fix held

After the reclaim (§2) and a few days, confirm the volume plateaus instead of
trending toward 100% — Prometheus (`monitoring` ns):

```promql
# used %, should sit well below 80 and stay flat (not climb)
100 * (1 - kubelet_volume_stats_available_bytes{persistentvolumeclaim="data-langfuse-clickhouse-shard0-0"}
         / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="data-langfuse-clickhouse-shard0-0"})
```

Spot-check the source is bounded — `system.trace_log` should stay small (profiler off
after the next ClickHouse restart; capped at 3 days by TTL until then) and the `system`
database should be a few GiB, not tens:

```bash
CH_PASS=$(kubectl -n langfuse get secret langfuse-clickhouse -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl -n langfuse exec langfuse-clickhouse-shard0-0 -c clickhouse -- clickhouse-client --password "$CH_PASS" \
  -q "SELECT database, formatReadableSize(sum(bytes_on_disk)) FROM system.parts WHERE active GROUP BY database ORDER BY sum(bytes_on_disk) DESC"
```

Timeline recorded during the incident: pinned **100%** for ~48h (from 2026-07-03) →
**~52%** immediately after the 40Gi resize → **~7%** expected after the §2 reclaim.

## PodSecurity note

The cluster enforces PodSecurity admission with only the `infra` namespace exempted
(`talos/patches/cp-01.yaml`). The langfuse app pods are hardened (non-root, drop ALL,
`RuntimeDefault` seccomp). If the Bitnami store pods (ClickHouse/MinIO/PostgreSQL/Valkey)
are rejected at admission, add `langfuse` to the PodSecurity `exemptions.namespaces` list
in `talos/patches/cp-01.yaml` and re-apply the control-plane config.
