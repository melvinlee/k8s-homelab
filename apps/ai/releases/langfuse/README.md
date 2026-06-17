# Langfuse

[Langfuse](https://langfuse.com/) — open-source LLM observability / tracing — deployed
via the `langfuse/langfuse` Helm chart (v1.5.33, app 3.177.0).

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

All PVCs land on `longhorn` via `global.defaultStorageClass`. Ingress is
`nginx-internal` at `http://langfuse.home`; external-dns syncs the host to Pi-hole.

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
kubectl get ingress -n langfuse                    # host langfuse.home
kubectl logs -n langfuse deploy/langfuse-web       # migrations / startup
```

Browse to `http://langfuse.home`, create the first account (sign-up is open).
Consider setting `langfuse.features.signUpDisabled: true` afterwards to lock it down.

## PodSecurity note

The cluster enforces PodSecurity admission with only the `infra` namespace exempted
(`talos/patches/cp-01.yaml`). The langfuse app pods are hardened (non-root, drop ALL,
`RuntimeDefault` seccomp). If the Bitnami store pods (ClickHouse/MinIO/PostgreSQL/Valkey)
are rejected at admission, add `langfuse` to the PodSecurity `exemptions.namespaces` list
in `talos/patches/cp-01.yaml` and re-apply the control-plane config.
