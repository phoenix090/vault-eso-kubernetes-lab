path "kv/data/app/*" {
  capabilities = ["read"]
}

path "kv/metadata/app/*" {
  capabilities = ["read", "list"]
}