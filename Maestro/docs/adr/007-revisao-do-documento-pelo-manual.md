# ADR 007 — Revisão do trabalho escrito pelo manual do PIM IV

**Data:** 28/10/2026 · **Situação:** aceita e aplicada

## Contexto
O documento `PIM IV - Joga Bonito.docx` foi conferido contra o *Manual do PIM IV — ADS 2026/2*.

O que já atendia: capa e folha de rosto no modelo do manual; resumo com 242 palavras (150 a 500)
e abstract; sumário; introdução com objetivo, metodologia e apresentação da empresa;
desenvolvimento com as 9 etapas, da página 8 à 36 (**29 páginas**, limite de 20 a 30);
conclusão; referências ABNT; A4, margens 3/3/2/2 cm, Arial 12, entrelinhas 1,5, recuo de 1,5 cm,
texto justificado; numeração a partir da Introdução, no canto superior direito.

## Problemas encontrados e corrigidos
| Onde | Problema | Correção |
|---|---|---|
| Folha de rosto | `Orientador(a): [nome do(a) orientador(a)]` | Eder Lima |
| 4.5, 6.3, 8.6 | Nomes técnicos sem o `_` (o texto passou por Markdown: `_x_` virou itálico) | `sp_AnonimizarUsuario`, `fn_CalcularJogaJunto`, `flutter_secure_storage`, `vw_*`, `fn_CalcularFrete`, `gerar_catalogo.py` |
| 4.5 | Asteriscos de Markdown em `**Joga Junto**` | Removidos |
| 7.1 | Código C# citado como "Quadro 9" | Quadro 8 |
| 8.4 | Trecho da procedure citado como "Quadro 13" | Quadro 12 |
| Quadro 11 | 9 procedures; o banco tem 10 | Linha `sp_ExpurgarRegistrosAntigos` |
| Abstract | "a function" (são duas) | "functions" |
| 9.4 | "26 testes" E2E | 30 testes |
| Apêndice A | Sem o endereço público; só emulador | `https://joga-bonito-sigma.vercel.app` e celular com depuração USB |

## Como foi gerado
Edição pontual dos textos (sem mudar fontes nem espaçamento) e, no LibreOffice 24.2 (o mesmo
que gerou o PDF original), atualização do sumário e exportação do PDF. A edição moveu o item
5.5 da página 20 para a 21; o sumário atualizado já mostra isso. O PDF continua com 41 páginas.
Os originais de 24/10 ficaram guardados fora do projeto.

## O que continua com o grupo
- Conferir a lista de integrantes e RAs antes de postar.
- Postar no sistema da UNIP dentro do prazo e entregar a cópia impressa ao coordenador.
