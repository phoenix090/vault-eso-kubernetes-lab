## Troubleshooting Vault Access Issues

This section documents the **exact checks and commands** used to debug Vault ↔ Kubernetes ↔ ESO connectivity and authorization issues in this lab.

Use this section if:
- `ClusterSecretStore` is not `Ready`
- ExternalSecret reports `403 permission denied`
- Vault Kubernetes auth login fails
- ESO cannot read secrets from Vault

---

### 1. Verify network connectivity from Kubernetes to Vault

Launch a temporary debug pod in the ESO namespace:

```bash
kubectl run net-debug \
  --image=curlimages/curl:8.6.0 \
  --restart=Never \
  -n external-secrets \
  --command -- sleep 3600

kubectl exec -it net-debug -n external-secrets -- sh

# Test Vault reachability (no CA yet)
curl -vk https://host.docker.internal:8200/v1/sys/health
```

Expected:
- Successful TLS handshake
- HTTP 200 response

If this fails, the issue is networking, not Vault auth.

### 2. Verify TLS trust using the Vault CA
```bash
cat > /tmp/vault-ca.pem <<'EOF'
-----BEGIN CERTIFICATE-----
<VAULT CA CERT HERE>
-----END CERTIFICATE-----
EOF

# Test TLS verification:
curl -v --cacert /tmp/vault-ca.pem https://host.docker.internal:8200/v1/sys/health
```
Expected:
- SSL certificate verify ok
If this fails, the issue is CA mismatch.

### 3. Verify Vault can reach the Kubernetes API
```bash
# Exec into the Vault container:
docker exec -it vault sh
# Check DNS resolution using the kind cluster name, e.g:
getent hosts test-cluster-control-plane
# Check TCP connectivity:
nc -vz test-cluster-control-plane 6443
# Check Kubernetes API access:
wget --no-check-certificate -qO- https://test-cluster-control-plane:6443/version
```
If this fails, Vault cannot validate Kubernetes tokens.

### 4. Verify Kubernetes auth configuration in Vault
Read the Kubernetes auth config:
```bash
vault read auth/kubernetes/config
```
Confirm:
- kubernetes_host is correct
- token_reviewer_jwt_set = true
- issuer is set (required for projected tokens)

### 5. Decode and verify the ServiceAccount token audience
Extract a projected token from a pod:
```bash
kubectl exec -n external-secrets eso-auth-debug -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token > eso.jwt
```
Devode the JWT payload and look for the `aud` value:
```bash
cut -d. -f2 eso.jwt | base64 --decode | jq .
"aud": ["https://kubernetes.default.svc.cluster.local"]
```
Vault role audience must match this exactly.

### 6. Verify the Vault Kubernetes auth role
Read the role:
```bash
vault read auth/kubernetes/role/eso-role
```
Confirm:
- bound_service_account_names = [external-secrets]
- bound_service_account_namespaces = [external-secrets]
- audience = https://kubernetes.default.svc.cluster.local
- Correct policy attached (e.g. app-policy)

### 7. Manually test Vault Kubernetes login
This is the most important diagnostic step.
```bash
vault write auth/kubernetes/login \
  role=eso-role \
  jwt=@eso.jwt
```
Expected:
- Vault token issued
- Correct policies attached
If this fails, ESO will also fail.

### 8. Verify Vault policy paths (KV v2)
List policies:
```bash
vault policy list
```
Read the policy attached to the role:
```bash
vault policy read app-policy
```
For KV v2, policies must reference:
```
kv/data/...
kv/metadata/...
```
Not:
```
kv/app/...
```
Incorrect paths will result in 403 permission denied.

## Golden rule

If manual Vault login works, ESO will work.