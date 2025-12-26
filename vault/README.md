# Vault Setup (Local Docker + Kubernetes Auth)

This document describes the **Vault-specific configuration** used in this lab.
It intentionally focuses only on Vault internals and assumes Kubernetes and ESO
are documented elsewhere.

---

## Overview

Vault is run locally using Docker Compose with the following characteristics:

- Vault version: **1.21.1**
- TLS enabled using a locally generated CA
- KV secrets engine **v2**
- Kubernetes authentication enabled
- Read-only policy for application secrets
- Kubernetes auth role for External Secrets Operator

---

## Storage Backend (Raft)

Vault in this lab is configured to use the **integrated Raft storage backend**.

Raft is Vault’s recommended storage backend for both development and production
(single-node or HA) and does **not** require an external datastore.

---

Raft Characteristics in This Lab
- Integrated storage (no Consul or external DB)
- Single-node Raft cluster
- Data persisted under:
````
./vault/data
````
- Requires manual unseal after every restart
- Suitable for:
  - Local development
  - Labs
  - Single-node production setups

---

## TLS Configuration

Vault in this lab is configured to run **with TLS enabled** using a **locally generated Certificate Authority (CA)**.  
TLS is mandatory because External Secrets Operator communicates with Vault over HTTPS and validates the server certificate.

This section documents the TLS assumptions and layout without exposing sensitive material.

---

## TLS Overview

- A local Certificate Authority (CA) is generated for the lab
- Vault is configured to use TLS certificates signed by this CA
- The Vault server certificate includes required SANs (for example `vault.local` and `host.docker.internal`)
- The CA certificate is provided to Kubernetes via `caBundle` in the `ClusterSecretStore`

---

## TLS File Layout

TLS material is mounted into the Vault container from the host:
````
./vault/tls/
├── ca.pem # CA certificate (public)
├── vault.pem # Vault server certificate
└── vault-key.pem # Vault private key (never commit)
````

Only **public certificates** may be referenced outside Vault.

---

## Vault TLS Configuration

Vault is configured to use TLS via its configuration file mounted under:
```
/vault/config
```

The configuration references the TLS files mounted at:
```
/vault/tls
```

Typical TLS settings include:

- `tls_cert_file`
- `tls_key_file`
- `tls_client_ca_file`

## TLS Certificate Creation (Short Version)

The following commands generate a **local Certificate Authority (CA)** and a **Vault server certificate** suitable for local development.

All commands are run from the `vault/` directory.

---

### Create Certificate Authority (CA)
```bash
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365
-subj "/CN=local-ca" -out ca.pem
```
### Create Vault Server Key and CSR
```bash
openssl genrsa -out vault-key.pem 2048
openssl req -new -key vault-key.pem
-subj "/CN=vault.local" -out vault.csr
```

### Create SAN Configuration
```bash
openssl x509 -req -in tls/vault.csr \                              
  -CA tls/ca.pem -CAkey tls/ca.key \
  -CAcreateserial \
  -out tls/vault.pem \
  -days 365 -sha256 \
  -extensions req_ext \
  -extfile tls/vault-openssl.cnf
```

---

### Resulting Files
````
ca.pem # CA certificate (public)
ca.key # CA private key 
vault.pem # Vault server certificate
vault-key.pem # Vault private key
````

### Important Notes

- Only `ca.pem` may be shared with Kubernetes / ESO
- Private keys must never be committed to Git
- These certificates are for **local development only**

---

## Kubernetes and ESO Trust Chain

External Secrets Operator must trust the Vault CA.

This is achieved by:

- Base64-encoding the **CA certificate only**
- Supplying it via `caBundle` in the `ClusterSecretStore` at this line: `caBundle: <base64-encoded ca.pem>`

If the CA is incorrect or missing, ESO will fail with TLS verification errors.

---

## Manual TLS Verification

To verify TLS manually from a Kubernetes pod:

```bash
curl -v --cacert /tmp/ca.pem https://host.docker.internal:8200/v1/sys/health
```

Expected result:
- Successful TLS handshake
- HTTP 200 response
- `SSL certificate verify ok`

## Security Notes

- **Private keys must never be committed to Git**
- TLS files are excluded via `.gitignore`
- This lab uses manual TLS for transparency
- Production setups typically use:
  - Central PKI
  - Short-lived certificates
  - Automated rotation

## Summary

TLS is a **first-class requirement** in this lab:

- Vault only accepts HTTPS
- ESO validates Vault’s certificate
- A local CA establishes trust
- No insecure or plaintext communication is allowed

Any TLS misconfiguration will surface immediately as connection or verification errors.

## Running Vault

Vault is started using Docker Compose from this directory.

```bash
docker compose up -d
```
Verify Vault is running:

```bash
docker ps
```

Vault should appear as a running container.

Check Vault status from your local machine (ensure VAULT_ADDR is set appropriately):
```bash
VAULT_ADDR=https://vault.local:8200
VAULT_CACERT=./tls/ca.pem

vault status
```

## Vault Initialization and Unsealing
When Vault is started for the **first time**, it must be **initialized** and **unsealed** before it can be used.

This lab assumes a **single-node Vault** running locally.

---

### Initialize Vault (first run only)

Run this once after starting Vault for the first time:

```bash
vault operator init
```

Vault will output:
- Unseal keys (default: 5 keys)
- Initial root token

#### ⚠️ Important
- Store unseal keys securely
- Do not commit them to Git
- Losing them means losing access to Vault

#### Unseal Vault
Vault starts in a sealed state.
You must provide a quorum of unseal keys (default: 3 of 5).

Run the following command three times, each time with a different unseal key:
```bash
vault operator unseal <Unseal Key 1>
vault operator unseal <Unseal Key 2>
vault operator unseal <Unseal Key 3>
```

Verify Vault Status
```bash
vault status
```
Expected output:
- Initialized: true
- Sealed: false
- Version: 1.21.1

ESO authentication and secret access will not work unless Vault is unsealed.

Notes for Local Development
- Vault must be unsealed after every restart
- In production, this is typically handled by:
  - Auto-unseal (KMS, HSM)
  - Vault Enterprise features

This lab intentionally uses manual unsealing to keep the setup transparent.

## Secrets Engine and Policy

This section documents the **remaining Vault configuration steps** required for this lab:

- Enable the KV v2 secrets engine
- Create the application secret
- Create the read-only Vault policy
- Create the Kubernetes auth role for ESO

These steps are executed **after Vault is initialized and unsealed**.

---

## Enable KV v2 Secrets Engine

Enable the KV secrets engine as **version 2** at the `kv` mount path:

```bash
vault secrets enable -path=kv kv-v2
```

Verify:
```bash
vault secrets list
```
You should see:
````
kv/   kv   version=2
````
### Create Application Secret

Create the application secret at:
````
kv/app/config
````
With the keys username and password:
```bash
vault kv put kv/app/config \
  username="example-user" \
  password="example-password"
```
Verify the secret:
```bash
vault kv get kv/app/config
```

### Create Vault Policy (Read-Only)

```bash
vault policy write app-policy policies/app-policy.hcl

```
Verify:
```bash
vault policy read app-policy
```

## Enable Kubernetes Authentication
Enable the Kubernetes auth method:
```bash
vault auth enable kubernetes
```

### Configure Kubernetes Authentication
Configure Vault to talk to the Kubernetes API:
```bash
vault write auth/kubernetes/config \
  token_reviewer_jwt=@reviewer.jwt \
  kubernetes_host="https://test-cluster-control-plane:6443" \
  kubernetes_ca_cert=@k8s-ca.pem \
  issuer="https://kubernetes.default.svc.cluster.local"
```
Verify configuration:
```bash
vault read auth/kubernetes/config

```

### Create Kubernetes Auth Role for ESO
Create the role used by External Secrets Operator:
```bash
vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=app-policy \
  audience="https://kubernetes.default.svc.cluster.local" \
  ttl=1h
```
Verify the role:
```bash
vault read auth/kubernetes/role/eso-role

```
Confirm:
- Correct ServiceAccount and namespace bindings
- Correct policy attached (app-policy)
- Correct audience

---

## Validation (Required Before ESO)
Manually test Kubernetes authentication before relying on ESO:
```bash
vault write auth/kubernetes/login \
  role=eso-role \
  jwt=@eso.jwt
```

Expected result:
- Vault token issued
- Policy app-policy attached
If this step fails, ESO authentication will also fail.

## Summary

At this point, Vault is fully configured for this lab:
- KV v2 enabled
- Application secret created
- Read-only policy in place
- Kubernetes auth configured
- ESO role created and validated

The remaining steps (ClusterSecretStore, ExternalSecret, and workload consumption)
are handled entirely on the Kubernetes side.