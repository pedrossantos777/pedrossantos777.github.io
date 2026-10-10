# RAIS agregada em H3 — Brasil

Mapa interativo de firmas e vínculos empregatícios da RAIS, agregados
em grade hexagonal H3. Roda **sem servidor** — depois de publicado,
tudo acontece dentro do navegador de quem está usando o mapa.

🖼️ Fluxograma visual do workflow: [`docs/fluxograma-workflow.svg`](docs/fluxograma-workflow.svg)

---

## A ideia em uma frase

O mapa separa **a forma dos hexágonos** (que nunca muda) dos
**números dentro de cada hexágono** (que mudam a cada ano) — e um
motor de banco de dados rodando no próprio navegador junta os dois na
hora, sem precisar de um servidor no meio.

## As três camadas

```
┌─────────────────────┐      ┌──────────────────────┐      ┌───────────────────────────┐
│   1. Pipeline em R   │  ──► │  2. Armazenamento     │  ──► │  3. Navegador do usuário   │
│                      │      │     (Cloudflare R2)   │      │                            │
│  Lê a RAIS e gera:   │      │                        │      │  MapLibre desenha os       │
│  • geometria.pmtiles │      │  Arquivos estáticos,   │      │  hexágonos; DuckDB-WASM    │
│  • hex_resX_cens4    │      │  servidos com suporte  │      │  consulta os atributos e   │
│  • uf_lookup.parquet │      │  a leitura parcial     │      │  "cola" o valor certo em   │
│                      │      │  (Range) e CORS        │      │  cada um                   │
└─────────────────────┘      └──────────────────────┘      └───────────────────────────┘
```

- **Camada 1 — Pipeline em R (`targets`)**: roda uma vez (ou sempre
  que há dado novo), gera os arquivos, não fica "ligado" depois.
- **Camada 2 — Cloudflare R2**: só guarda arquivos. Não roda código
  nenhum.
- **Camada 3 — Navegador**: é onde a interatividade acontece de
  verdade — trocar de ano, aplicar uma fórmula, reclassificar a
  legenda. Tudo isso é uma consulta SQL local, não uma chamada a um
  servidor.

## Os 3 arquivos que alimentam o site

- **PMTiles (`geometria_targets.pmtiles`)**: arquivo vetorizado que
  contém os hexágonos conectados e permite o "zoom" do mapa, com os
  hexágonos surgindo na tela conforme o nível de aproximação. Os tiles
  nunca se alteram — os hexágonos são sempre os mesmos —, então são
  gerados apenas uma vez, na construção do site. Só é necessário gerar
  novos tiles se você quiser aumentar ou diminuir a granularidade do
  zoom.
- **UF lookup (`uf_lookup.parquet`)**: arquivo parquet com a lista de
  todos os hexágonos de cada UF. É ele que permite ao navegador
  identificar a UF de cada hexágono na hora de aplicar os filtros de
  Região/Estado. Esses vínculos hexágono–UF também nunca se alteram,
  então o arquivo também é gerado apenas uma vez.
- **Atributos por resolução (`hex_res4_cens4.parquet`,
  `hex_res6_cens4.parquet`, `hex_res8_cens4.parquet`)**: estes são os
  arquivos que **podem ser alterados**, pois guardam as informações de
  cada hexágono — número de firmas, trabalhadores, setor da economia
  etc. Se o autor quiser mudar o que cada hexágono representa, são
  estes arquivos que devem ser alterados.

Todos esses arquivos são gerados a partir dos scripts contidos na pasta
`funcoes_principais`.

# Onde os arquivos são hospedados

- Os arquivos parquet e os tiles são todos armazenados em uma conta no
`CloudFlare`. Este site permite que gratuitamente sejam utilizados até
10gb de armazenamento.
- A partir do armazenamento dos arquivos no `CloudFlare`, é gerada uma
  espécie de API que é incluída no HTML que é aponta para os arquivos
  para ser gerado o site.


## Por que separar geometria de atributos

Um hexágono não muda de forma ou de posição de um ano para o outro —
só a quantidade de firmas/vínculos dentro dele muda. Gerar a geometria
de novo a cada ano seria redundante (e deixaria o arquivo do mapa cada
vez maior). Separando os dois, a geometria é gerada **uma vez só**. Os
atributos ficam em um parquet por resolução (`hex_res4_cens4.parquet`,
`hex_res6_cens4.parquet`, `hex_res8_cens4.parquet`), com todos os anos
juntos na coluna `year`: o navegador baixa cada arquivo uma vez e trocar
de ano vira só um `WHERE year = ...` local.

## Como rodar (resumo)

```r
# 1. gera os arquivos
targets::tar_make()
```
```bash
# 2. sobe pro armazenamento
rclone copy . r2:seu-bucket/ --include "*.pmtiles" --include "*.parquet"
```
```bash
# 3. testa localmente
python -m http.server 8000
# abra http://localhost:8000/map_br.html
```

Passo a passo detalhado, configuração de CORS, estrutura das funções,
erros comuns e decisões de arquitetura: veja a
[documentação completa](https://github.com/pedrossantos777/pedrossantos777.github.io/blob/main/documentacao-completa.md).
