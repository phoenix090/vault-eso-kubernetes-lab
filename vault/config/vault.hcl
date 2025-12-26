storage "raft" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.pem"
  tls_key_file  = "/vault/tls/vault-key.pem"
}

api_addr = "https://vault.local:8200"
cluster_addr = "https://vault.local:8201"

disable_mlock = true
ui = true