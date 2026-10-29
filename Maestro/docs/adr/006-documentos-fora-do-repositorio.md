# ADR 006 — Trabalho escrito e planilhas fora do repositório público

**Data:** 28/10/2026 · **Situação:** aceita e aplicada

## Contexto
O repositório `github.com/matheus-sigoli/Joga-Bonito` é público, e o trabalho ABNT do PIM IV
(`.docx` e `.pdf`), a versão do PIM III e a planilha de backlog podiam ser baixados sem login.
O manual do PIM IV (seção 7) diz que a UNIP compara o trabalho entregue com conteúdos da
internet, que similaridade alta reprova, e trata como autoplágio "a publicação do próprio PIM
em sites sem credibilidade acadêmica".

## Decisão
- Remover do repositório, **inclusive do histórico**, todos os `.docx`, `.pdf` e `.xlsx`.
- Bloquear esses formatos no `.gitignore`.
- Os arquivos continuam na pasta do projeto no PC e são entregues só pelo sistema de
  trabalhos acadêmicos da UNIP (e na cópia impressa ao coordenador).

## Consequências
- O código, os scripts do banco, as figuras (`ABNT/figuras`) e o site da Vercel continuam
  públicos: não são o texto do trabalho.
- O histórico do GitHub foi reescrito (`git filter-repo`) e enviado com push forçado. Quem tiver
  um clone antigo precisa clonar de novo.
- O GitHub ainda pode guardar os commits antigos em cache por um tempo, acessíveis só por quem
  tiver o endereço exato. Para apagar de vez: GitHub › Support › "Remove sensitive data".
- O `ABNT/PIM IV - Joga Bonito (visualizacao).pdf` local é uma versão antiga (38 páginas) e não
  deve ser entregue.
