
# Mapa Interativo RAIS agregada em H3 — Brasil

Mapa interativo de firmas e vínculos empregatícios da RAIS, agregados
em grade hexagonal H3. 

📖 Documentação completa (para quem for mexer no código): [`documentacao-completa.md`](https://github.com/pedrossantos777/pedrossantos777.github.io/blob/main/documentacao-completa.md)
🖼️ Fluxograma visual do workflow: [`docs/fluxograma-workflow.svg`](docs/fluxograma-workflow.svg)

---
## Como funciona

O mapa é carregado com os hexagonos e os arquivos que contém os dados de empregos e de firmas separadamente, 
e dentro do navegador eles são conectados por quem está utilizando o mapa.

O mapa separa **a forma dos hexágonos** dos
**valores dentro de cada hexágono** — e um
motor de banco de dados rodando no próprio navegador junta os dois na
hora, sem precisar de um servidor no meio.

Os arquivos .tile possuem os hexágonos e os arquivos em parquet para cada resolução e ano são mantidos separadamente e unificados via
DUCK-DB WASM pelo navegador do prórprio usuário. Essa arquitetura permite que os arquivos gerados sejam mais leves
e que o navegador possa executar os códigos sem sobrecarregar a máquina.
O modelo também permite que o prório usuário possa realizar suas buscas utilizando SQL no próprio site.

## As três camadas

```
┌──────────────────────┐      ┌────────────────────────┐       ┌────────────────────────────┐
│   1. Pipeline        │  ──► │  2. Armazenamento      │  ──►  │  3. Navegador do usuário   │
│                      │      │     (Cloudflare R2)    │       │                            │
│  Lê a RAIS e gera:   │      │                        │       │  MapLibre desenha os       │
│  • geometria.pmtiles │      │  Arquivos estáticos,   │       │  hexágonos; DuckDB-WASM    │
│  • parquets por ano  │      │  servidos com suporte  │       │  consulta os atributos e   │
│  • uf_lookup.parquet │      │  a leitura parcial     │       │  publica o valor certo em  │
│                      │      │  (Range) e CORS        │       │  cada hexágono             │
└──────────────────────┘      └────────────────────────┘       └────────────────────────────┘
```

- **Camada 1 — Pipeline**: roda uma vez (ou sempre
  que há dado novo) e gera os arquivos.
- **Camada 2 — Cloudflare R2**: guarda arquivos. Não roda código
  nenhum.
- **Camada 3 — Navegador**: é onde a interatividade acontece de
  verdade — trocar de ano, aplicar uma fórmula, reclassificar a
  legenda. Tudo isso é uma consulta SQL local, não uma chamada a um
  servidor.

## Por que separar geometria de atributos

Um hexágono não muda de forma ou de posição de um ano para o outro —
só a quantidade de firmas/vínculos dentro dele muda. Gerar a geometria
de novo a cada ano seria redundante (e deixaria o arquivo do mapa cada
vez maior). Separando os dois, a geometria é gerada **uma vez só**, e
trocar de ano vira só buscar um arquivo pequeno novo.


## Níveis de Zoom

Inicialmente o mapa interativo permite que sejam observados os dados de empregos pelos 
hexágonos de nível 4, 6 e 8, para todo o Brasil, separado por UF e por Região.
Ao interagir com o mapa dando zoom, o próprio navegador carrega as tiles que compõema tela exibida, o que
permite que o navegador não faça consultas desnecessárias e force o processamento da própria máquina.

 
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
