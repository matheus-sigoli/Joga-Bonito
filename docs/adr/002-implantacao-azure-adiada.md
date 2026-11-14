# ADR 002 — Azure pronto para publicar, decisão de publicar adiada

**Data:** 27/10/2026 · **Situação:** aceita

## Contexto
A infraestrutura está descrita em `infra/main.bicep` (App Service com container, Azure SQL,
Key Vault) e documentada em `infra/IMPLANTACAO.md`. Publicar exige uma assinatura Azure e os
segredos do GitHub. O grupo ainda não decidiu se a banca verá a loja no Azure.

## Decisão
Deixar a implantação pronta e conferida (Bicep válido, workflow configurado, passo a passo
atualizado), sem publicar por enquanto. O plano base da apresentação é:
loja no PC + site público (GitHub Pages ou Vercel, modo demonstração).

## Consequências
- **O APK de produção não funciona sem a loja publicada:** ele só aceita HTTPS
  (ver [ADR 003](003-app-testado-em-celular-real.md)). Sem Azure, o app é demonstrado
  numa build de depuração ligada ao PC.
- HTTPS, firewall do Azure SQL e Key Vault só podem ser conferidos depois de publicar.
- Quando decidir, registrar num ADR novo que substitui este.
