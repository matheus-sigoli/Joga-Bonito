#!/bin/sh
# Gera o .env do docker-compose com segredos aleatórios e exclusivos deste computador.
# Se o .env já existe, só acrescenta o que faltar (nunca troca um segredo existente:
# trocar DADOS_CHAVE tornaria ilegíveis os endereços já cifrados no banco).
set -e
cd "$(dirname "$0")"
aleatorio() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
touch .env
chmod 600 .env
n=0
grep -q '^SQL_SA_PASSWORD=.' .env || { echo "SQL_SA_PASSWORD=Jb#$(aleatorio 20)9a" >> .env; n=$((n+1)); }
grep -q '^JWT_CHAVE=.' .env       || { echo "JWT_CHAVE=$(aleatorio 64)" >> .env; n=$((n+1)); }
grep -q '^DADOS_CHAVE=.' .env     || { echo "DADOS_CHAVE=$(head -c 32 /dev/urandom | base64)" >> .env; n=$((n+1)); }
echo ".env pronto ($n segredo(s) novo(s)). Guarde uma cópia de DADOS_CHAVE em lugar seguro."
echo "Suba com: docker compose up -d --build"
