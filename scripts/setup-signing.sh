#!/bin/zsh
# Cria (uma vez) um certificado local de assinatura de código no Chaveiro de login.
#
# Com assinatura ad-hoc, cada build tem uma identidade diferente, e o macOS volta a
# pedir acesso ao Chaveiro (chave "NeyZap WebCrypto Master Key") a cada recompilação.
# Assinando sempre com o mesmo certificado, o "Permitir Sempre" passa a valer.
#
# Para desfazer: Acesso às Chaves → login → apagar "NeyZap Local Signing".
set -euo pipefail

NAME="NeyZap Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ certificado \"$NAME\" já existe"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# OpenSSL do sistema (LibreSSL): o OpenSSL 3 do Homebrew gera um .p12 que o
# `security import` costuma recusar.
OPENSSL=/usr/bin/openssl
export PASS="$($OPENSSL rand -base64 18)"
$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
$OPENSSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/id.p12" -passout env:PASS

# -T libera o uso da chave pelo codesign sem pedir senha a cada build;
# -x deixa a chave privada não exportável.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign >/dev/null
echo "✓ certificado \"$NAME\" criado no Chaveiro de login"
