---
status: "accepted"
date: 2026-06-14
---

# 0007. Manage secrets with SOPS/age and External Secrets Operator

## Context and Problem Statement

No secret may be committed in plaintext, yet the repo is the source of truth.
Some in-repo secrets (Talos cluster secrets, Loki, Grafana) can be encrypted in
place, while application secrets are better sourced from an external vault. How
should secrets be stored and delivered?

## Decision Drivers

* No plaintext secrets in Git
* GitOps-compatible (works with declarative `helmfile apply`)
* A central, auditable store for application secrets

## Considered Options

* SOPS/age encrypted files in the repo
* Sealed Secrets
* External Secrets Operator backed by a cloud vault
* HashiCorp Vault

## Decision Outcome

Chosen option: "SOPS/age **and** External Secrets Operator", using each where it
fits. SOPS/age encrypts in-repo secrets (`talos/secrets.yaml`, the Loki and
Grafana secrets). Application secrets are externalized via External Secrets
Operator backed by an Azure Key Vault, provisioned by `terraform/` (issue #47).

### Consequences

* Good, because no secret is stored in plaintext and app secrets live in one vault
* Bad, because it adds SOPS/age key management plus an ESO + Azure Key Vault
  dependency (and Azure cost)

## More Information

See the "Secrets" note in `CLAUDE.md`, `terraform/README.md`, and issue #47.
