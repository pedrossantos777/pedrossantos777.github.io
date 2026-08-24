# Mapa interativo RAIS agregada em H3 — Brasil

> **Este é o documento de referência completo.** Para uma visão rápida
> da arquitetura sem entrar em detalhe de implementação, veja o
> [`README.md`](../README.md) na raiz do repositório.

Mapa interativo de firmas e vínculos empregatícios da RAIS, agregados em
grade hexagonal H3, com classificação estatística, fórmulas customizadas
e filtro geográfico — tudo rodando **sem servidor**, direto no navegador.

Este README documenta o projeto de ponta a ponta: da preparação dos
dados em R até o HTML publicado. O objetivo é que qualquer pessoa —
mesmo sem ter acompanhado o desenvolvimento — consiga entender como as
peças se encaixam e onde mexer para dar manutenção ou adicionar algo
novo.

> **Status**: pipeline `targets` validado de ponta a ponta (execução
> completa, 21 alvos processados) e dashboard testado localmente com
> os arquivos gerados. Detalhes de configuração pendente/opcional na
> seção 7.

Se preferir uma visão só do fluxo geral antes de entrar nos detalhes,
veja o fluxograma em [`fluxograma-workflow.svg`](fluxograma-workflow.svg).

---

## Sumário

1. [Visão geral da arquitetura](#1-visão-geral-da-arquitetura)
2. [Pipeline de dados em R (`targets`)](#2-pipeline-de-dados-em-r-targets)
3. [Armazenamento (Cloudflare R2)](#3-armazenamento-cloudflare-r2)
4. [Frontend (`map_br.html`)](#4-frontend-map_brhtml)
5. [Como rodar tudo do zero](#5-como-rodar-tudo-do-zero)
6. [Como publicar](#6-como-publicar)
7. [Limitações conhecidas e próximos passos](#7-limitações-conhecidas-e-próximos-passos)
8. [Erros comuns ao rodar o pipeline `targets`](#8-erros-comuns-ao-rodar-o-pipeline-targets)
9. [Glossário rápido](#9-glossário-rápido)

---

## 1. Visão geral da arquitetura

A ideia central do projeto é separar **duas coisas que mudam em
velocidades diferentes**:

- **Geometria dos hexágonos** é gerada **uma única vez** e vira um arquivo `geometria.pmtiles`.
- **Atributos por ano** (quantidade de firmas, vínculos ativos) — mudam
  a cada ano de dado novo. Ficam em **arquivos `.parquet` pequenos e
  separados**, um por combinação de resolução × ano.

No navegador, um motor de banco de dados (**DuckDB-WASM**) lê esses
`.parquet` sob demanda e publica os valores certos em cada hexágono já
desenhado, via um mecanismo do MapLibre chamado `feature-state`. Essa
separação é o que permite trocar de ano, aplicar uma fórmula SQL
customizada, ou reclassificar a legenda **sem nunca regenerar a
geometria** — só uma consulta SQL leve.

Não existe backend, banco de dados hospedado, nem servidor de
aplicação rodando em lugar nenhum. Tudo que roda "depois de publicado"
acontece dentro do navegador de quem está usando o mapa.

```
RAIS (parquet bruto)
      │
      ▼
Pipeline R (targets, com crew) ──► geometria.pmtiles + parquets de atributos + uf_lookup.parquet
      │
      ▼
Cloudflare R2 (armazenamento estático, com CORS)
      │
      ▼
map_br.html (GitHub Pages) ──► MapLibre GL JS + DuckDB-WASM, tudo no navegador
```

Fluxograma detalhado: [`fluxograma-workflow.svg`](fluxograma-workflow.svg).

---

## 2. Pipeline de dados em R (`targets`)

### Estrutura de pastas

```
projeto/
├── _targets.R                 # pipeline de geração de tiles/parquets
├── R/
│   └── funcoes_hex_pmtiles.R  # funções usadas pelo _targets.R
└── data/
    └── rais_test_20260727.parquet   # dado de origem (não versionado)
```

> **Se este projeto convive com outro pipeline `targets`** (por
> exemplo, um pipeline de agregação/censura da RAIS que roda antes
> deste), veja a nota em [Relação com outros pipelines
> `targets`](#relação-com-outros-pipelines-targets) mais abaixo —
> a recomendação é manter os dois como projetos `targets`
> **separados**, conectados por arquivo, via `_targets.yaml`.

### Por que `targets`

- **Cache automático**: rodar `tar_make()` de novo depois de só trocar
  o parquet de origem reprocessa apenas o que depende disso — não
  refaz a geometria (que não mudou) do zero.
- **Branching automático** (`pattern = map(...)`/`cross(...)`):
  adicionar uma resolução nova ou um ano novo de dado não exige editar
  loop nenhum — o pipeline ramifica sozinho.
- **Paralelização real**, via `crew_controller_local()`: como cada
  resolução (e cada combinação resolução × ano) é processada de forma
  independente, o `crew` distribui essas branches entre múltiplos
  workers locais, em vez de rodar tudo sequencialmente.
- **Rastreabilidade**: `tar_visnetwork()` mostra visualmente o grafo
  de dependências.

### As funções (`R/funcoes_hex_pmtiles.R`)

| Função | O que faz |
|---|---|
| `carregar_rais(caminho)` | Lê o parquet de origem via `arrow::open_dataset()`. |
| `preparar_geometria(df, resolucao)` | Gera **uma linha por hexágono**, só com `h3_address` + geometria — **sem** `uf`/`code_intermediate`/`code_muni`. Ver nota abaixo sobre por que essas colunas foram removidas daqui. |
| `checar_hexagonos_multi_uf(df, resolucao)` | Informativo (`message()`, não bloqueia nada): conta quantos hexágonos tocam mais de uma UF, por resolução. |
| `nomear_geometrias(lista, resolucoes)` | Nomeia a lista de geometrias no padrão `h3_r04`, `h3_r06`, `h3_r08` — vira o nome da camada dentro do PMTiles. |
| `gerar_pmtiles(geometrias_nomeadas, caminho)` | Chama `freestiler::freestile()`. **Sempre `coalesce = FALSE`** — ver nota abaixo. |
| `preparar_atributos(df, resolucao, ano)` | Agrega `n_firmas`/`qt_vinc_ativos` por hexágono, para uma resolução e ano específicos. |
| `exportar_atributos_parquet(df, resolucao, ano, dir)` | Grava um `.parquet` por combinação resolução × ano. O ano **não vira coluna** — vira parte do nome do arquivo. |
| `preparar_uf_lookup_parcial(df, resolucao)` | Gera o lookup `h3_address → uf` de **uma** resolução, direto do `df` bruto (não da geometria). |
| `gerar_uf_lookup(lista_uf_por_resolucao, caminho)` | Junta os lookups parciais num único `uf_lookup.parquet`. |

> **Nota — por que a geometria não carrega `uf`/`code_intermediate`/
> `code_muni`**: uma versão anterior desta função incluía essas
> colunas no `distinct()` da geometria. Um hexágono que fisicamente
> toca mais de uma UF (comum em fronteiras, principalmente na
> resolução 4, que é maior) gerava **mais de uma linha de geometria
> para o mesmo hexágono** — ou seja, o mesmo polígono duplicado dentro
> do `geometria.pmtiles`, causando artefato visual no mapa. A correção
> foi tirar completamente as colunas administrativas da geometria
> (`distinct(h3_address)` puro) e mover essa informação para um
> arquivo à parte (`uf_lookup.parquet`), que **pode** ter mais de uma
> linha por hexágono sem problema — é responsabilidade do consumidor
> (o dashboard) lidar com isso via subquery de existência, não `JOIN`
> direto (ver seção 4).

> **Nota — `coalesce = FALSE` no `freestile()`**: `coalesce = TRUE`
> fundiria hexágonos adjacentes com atributos idênticos, quebrando a
> identidade individual de `h3_address` que o `feature-state` no
> navegador precisa. Nunca mude isso para `TRUE`.

> **Nota — `iteration = "list"`**: o alvo que gera a geometria por
> resolução (`geometria_por_resolucao`) precisa **obrigatoriamente**
> de `iteration = "list"`. Sem isso, o `targets` combina
> automaticamente os resultados das branches num único objeto
> (comportamento padrão de `iteration = "vector"`, que usa
> `vctrs::vec_c()` — e isso também funciona, silenciosamente, para
> objetos `sf`/data.frame). O passo seguinte (`nomear_geometrias()`)
> precisa de uma **lista** com uma geometria por resolução pra poder
> nomear cada uma individualmente — se essa opção for removida por
> engano, o pipeline não quebra com erro nenhum, só produz um
> `geometria.pmtiles` errado silenciosamente.

### O pipeline (`_targets.R`)

Segue a convenção já usada em outros pipelines do projeto: `crew`
para paralelização local, `tar_source("./R")` para carregar as
funções, e alvos numerados/comentados por etapa.

```r
tar_option_set(
  memory = "transient",
  garbage_collection = TRUE,
  controller = crew_controller_local(workers = 6, ...),
  storage = "worker",
  retrieval = "worker",
  trust_timestamps = TRUE,
  error = "null",
  packages = c("arrow", "dplyr", "h3jsr", "purrr", "sf", "freestiler", "tarchetypes")
)
```

Pontos que vale destacar:

- `resolucoes <- c(4, 6, 8)` é o **único lugar** onde as resoluções
  são definidas — todo o resto (geometria, PMTiles, atributos,
  lookup de UF) deriva daqui.
- `geometria_por_resolucao` e `uf_lookup_por_resolucao` são **pipelines
  paralelos independentes**, os dois lendo do mesmo `rais_df`, mas
  sem depender um do outro — é assim que a separação geometria/UF é
  garantida estruturalmente, não só por convenção.
- `atributos_parquet` ramifica de forma cruzada
  (`pattern = cross(resolucoes, anos)`) — uma branch por combinação
  resolução × ano.

Rodar:
```r
targets::tar_make()
```

Ver o grafo de dependências antes de rodar:
```r
targets::tar_visnetwork()
```

### Relação com outros pipelines `targets`

Se este projeto já tem outro pipeline `targets` (por exemplo, um que
faz agregação + censura por vizinhança dos dados brutos da RAIS antes
de chegar neste ponto), a recomendação é **não** misturar tudo numa
`_targets.R` só. Em vez disso, registre os dois como projetos
separados via `_targets.yaml` na raiz do repositório:

```yaml
rais:
  script: _targets_rais.R
  store: _targets/rais

tiles:
  script: _targets_tiles.R
  store: _targets/tiles
```

Cada um roda (e cacheia) de forma independente:
```r
targets::tar_make(script = "_targets_tiles.R", store = "_targets/tiles")
```

Nesse cenário, o primeiro alvo deste pipeline (`carregar_rais()`)
deveria ler o **resultado já censurado/agregado** do outro pipeline
(o output de `salva_rais_censurada()` ou equivalente), não o parquet
bruto da RAIS diretamente — isso ainda está pendente de ajuste neste
projeto e depende de saber exatamente onde/como o outro pipeline grava
sua saída.

### Saídas geradas

```
geometria.pmtiles          # geometria, 1 arquivo, gerado 1x
dados/
  hex_r04_2013.parquet     # atributos, 1 arquivo por resolução × ano
  hex_r04_2023.parquet
  hex_r06_2013.parquet
  hex_r06_2023.parquet
  hex_r08_2013.parquet
  hex_r08_2023.parquet
uf_lookup.parquet          # h3_address → uf (pode repetir h3_address em fronteiras)
```

Esses são exatamente os arquivos que precisam ser publicados na etapa
seguinte.

---

## 3. Armazenamento (Cloudflare R2)

### Por que R2, e não GitHub direto

O `geometria.pmtiles` e os `.parquet` são lidos pelo navegador via
**requisições HTTP Range** (o PMTiles e o DuckDB-WASM baixam só os
bytes necessários, não o arquivo inteiro) e via **`fetch()` com
CORS liberado**. Isso descarta algumas opções óbvias:

- **GitHub Releases**: aceita arquivos grandes, mas **não envia
  cabeçalho `Access-Control-Allow-Origin`** — o navegador bloqueia por
  CORS assim que o `fetch()` é feito via JavaScript (funciona para
  download direto por link, não para o app consultar programaticamente).
- **Repositório Git direto / GitHub Pages para os dados**: funciona
  tecnicamente, mas esbarra no limite de ~100 MB por arquivo sem Git
  LFS, e no limite recomendado de ~1 GB por repositório.

**Cloudflare R2** é a recomendação oficial do próprio criador do
formato PMTiles (documentação do Protomaps), por não cobrar taxa de
egress (só por requisição) e por suportar Range + CORS nativamente,
contanto que configurado.

### Estrutura no bucket

Todos os arquivos ficam na **raiz do bucket** (o código do dashboard
assume esse caminho):

```
geometria.pmtiles
uf_lookup.parquet
hex_r04_2013.parquet
hex_r04_2023.parquet
hex_r06_2013.parquet
hex_r06_2023.parquet
hex_r08_2013.parquet
hex_r08_2023.parquet
```

### Configuração de CORS necessária

No bucket → Settings → CORS Policy:

```json
[
  {
    "AllowedOrigins": ["https://SEU_USUARIO.github.io"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["Range"],
    "ExposeHeaders": ["Content-Range", "Content-Length", "Accept-Ranges"],
    "MaxAgeSeconds": 3600
  }
]
```

Sem isso, o mapa carrega o basemap normalmente, mas **nenhum hexágono
aparece** — o navegador bloqueia silenciosamente as respostas do
`fetch()`, e o erro só aparece no Console (`blocked by CORS policy`).

### Como subir os arquivos

Pelo dashboard da Cloudflare (mais simples, funciona bem até ~300 MB
por arquivo pela interface web): bucket → **Upload** → arrasta os
arquivos.

Para arquivos maiores, ou upload em lote via linha de comando, use
`rclone` — veja a documentação oficial do rclone para configurar um
remote apontando para o R2 (driver S3, endpoint
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`).

---

## 4. Frontend (`map_br.html`)

Um único arquivo HTML, sem build step, sem framework, sem dependência
de Node.js para rodar. Todas as bibliotecas vêm de CDN.

### Bibliotecas usadas

| Biblioteca | Papel |
|---|---|
| MapLibre GL JS | Renderização do mapa e das camadas vetoriais. |
| `pmtiles.js` | Protocolo que permite o MapLibre ler `.pmtiles` diretamente (registrado via `maplibregl.addProtocol`). |
| `@duckdb/duckdb-wasm` | Motor SQL compilado para WebAssembly, roda num Web Worker — é o que permite consultar os `.parquet` remotos com SQL de verdade, dentro do navegador. |

### Como a geometria é carregada

```js
map.addSource("hex", {
  type: "vector",
  url: "pmtiles://" + PMTILES_URL,
  promoteId: { h3_r04: "h3_address", h3_r06: "h3_address", h3_r08: "h3_address" }
});
```

`promoteId` é essencial: é isso que faz o MapLibre usar `h3_address`
como identificador de cada feature — sem isso, o `feature-state` (ver
abaixo) não teria como saber em qual hexágono colar cada valor.

Três camadas (`fill-h3-r04`, `fill-h3-r06`, `fill-h3-r08`) são
desenhadas, cada uma visível numa janela de zoom diferente
(`minzoom`/`maxzoom`), dando o efeito de troca de resolução conforme o
usuário dá zoom.

### Como os atributos são carregados

Ao trocar de ano (ou ao carregar a página), o código:

1. Busca o `.parquet` daquele ano/resolução via `fetch()` — **baixando
   o arquivo inteiro**, não usando leitura parcial por Range. Isso é
   proposital: uma tentativa anterior de deixar o DuckDB-WASM ler
   diretamente via `read_parquet('https://...')` (Range requests)
   esbarrou num bug conhecido do DuckDB-WASM em algumas combinações de
   sistema operacional/navegador (`TProtocolException: Invalid data`).
   Como os arquivos de atributo são pequenos, baixar inteiro não pesa.
2. Registra o buffer no DuckDB via `db.registerFileBuffer()`.
3. Roda uma query SQL (`SELECT h3_address, n_firmas, qt_vinc_ativos,
   (expressão) AS valor FROM read_parquet(...)`) — a "expressão" é a
   variável escolhida ou a fórmula SQL customizada do usuário.
4. Para cada linha do resultado, chama `map.setFeatureState()`,
   colando o valor no hexágono correspondente.

### `feature-state` — a ponte entre geometria e atributo

```js
map.setFeatureState(
  { source: "hex", sourceLayer: "h3_r06", id: row.h3_address },
  { n_firmas: ..., qt_vinc_ativos: ..., valor: ... }
);
```

A cor de cada hexágono é uma expressão de estilo do MapLibre que lê
esse estado, não uma propriedade fixa da tile:

```js
["interpolate", ..., ["feature-state", "valor"], ...]
```

Isso é o que permite trocar de ano, variável ou fórmula **sem
recarregar a geometria** — só troca o que está "colado" em cada
hexágono.

### Filtro de área (Região / UF)

Diferente do que seria o caminho mais direto (um `filter` do MapLibre
lendo a propriedade `uf` embutida na própria geometria), o filtro de
área **é resolvido via SQL no DuckDB**, usando `uf_lookup.parquet`:

```sql
SELECT a.h3_address, a.n_firmas, a.qt_vinc_ativos, (expressão) AS valor
FROM read_parquet('hex_r06_2023.parquet') a
WHERE a.h3_address IN (
  SELECT h3_address FROM read_parquet('uf_lookup.parquet') WHERE upper(uf) = 'SP'
)
```

Hexágonos fora do filtro simplesmente não recebem `feature-state`, e
ficam transparentes (mesma lógica usada para "sem dado"). Essa
subquery de existência (`IN (SELECT ...)`) foi escolhida em vez de um
`JOIN` direto porque um hexágono que intersecta mais de uma UF geraria
linhas duplicadas com `JOIN` — o que também distorceria a
classificação estatística (contaria esse hexágono mais de uma vez no
cálculo de quantis).

> Essa abordagem via SQL foi adotada depois de o filtro "padrão"
> (`setFilter` do MapLibre direto na tile) apresentar um bug que não
> foi totalmente diagnosticado com os dados deste projeto. Fica como
> possível otimização futura — ver seção 7.

### Classificação dinâmica

Três métodos, escolhidos pelo usuário, com número de classes
configurável (4 a 8):

- **Quantis** — `quantile_cont()` do próprio DuckDB.
- **Intervalos iguais** — `min`/`max` do DuckDB, dividido em partes
  iguais em JS.
- **Jenks (natural breaks)** — não existe função nativa para isso em
  SQL, então o DuckDB só traz os valores brutos, e um **algoritmo Jenks
  clássico roda em JavaScript** (com amostragem automática acima de 2000
  pontos, para não travar o navegador em bases grandes).

Os breaks são calculados **separadamente por resolução** (4, 6 e 8),
porque a escala de valores muda muito entre elas — e passam por uma
função de sanitização (`sanitizarBreaks()`) que garante sequência
estritamente crescente, um requisito da expressão `step` do MapLibre
que pode falhar quando a área filtrada tem poucos hexágonos (valores
duplicados nas quebras).

### Fórmula SQL customizada

O campo de fórmula aceita qualquer expressão SQL válida sobre as
colunas `n_firmas`/`qt_vinc_ativos` (ex.: `n_firmas /
NULLIF(qt_vinc_ativos, 0)`). Substitui a variável selecionada como
`expressaoAtiva`, que é a mesma variável usada em toda consulta
(coloração, classificação, exportação).

### Paletas, opacidade e fundo do mapa

- 7 paletas de cor pré-definidas (5 cores-âncora cada), amostradas
  dinamicamente para o número de classes escolhido via interpolação
  RGB (`amostrarRampa()`).
- Opacidade ajustável por slider.
- 3 fundos de mapa (OpenStreetMap, satélite Esri, relevo OpenTopoMap)
  — trocar de fundo exige `map.setStyle()`, que **apaga toda source e
  layer customizada**, então o código reconstrói a camada de
  hexágonos (`adicionarCamadasHex()`) toda vez que o fundo muda.

### Exportação CSV

Gerada 100% no navegador: consulta os dados já carregados no DuckDB,
monta uma string CSV em JavaScript, embrulha num `Blob` e dispara o
download via link temporário. A resolução exportada é escolhida num
seletor **gerado dinamicamente a partir do array `RESOLUCOES`** — não
hardcoded, então uma resolução nova adicionada ali aparece
automaticamente na exportação também.

### Responsividade mobile

Em telas ≤640px, o painel de controles começa **recolhido**, com um
botão flutuante (`☰`) para abrir/fechar — evita que o painel cubra o
mapa inteiro em celulares. Em desktop, o painel permanece sempre
visível, sem esse botão.

---

## 5. Como rodar tudo do zero

```r
# 1. Gerar os arquivos (R)
targets::tar_make()

# 2. Conferir o que foi gerado
list.files(".", pattern = "\\.pmtiles$|\\.parquet$", recursive = TRUE)
```

```bash
# 3. Subir para o R2 (via rclone, ou pelo dashboard da Cloudflare)
rclone copyto geometria.pmtiles r2:seu-bucket/geometria.pmtiles
rclone copyto uf_lookup.parquet r2:seu-bucket/uf_lookup.parquet
rclone copy dados/ r2:seu-bucket/ --include "*.parquet"
```

```bash
# 4. Testar o HTML localmente
python -m http.server 8000
# abra http://localhost:8000/map_br.html
```

> **Atenção ao cache do navegador durante testes locais.** Depois de
> qualquer mudança nos arquivos publicados no R2, use Ctrl+Shift+R
> (recarregamento forçado) e considere marcar "Disable cache" no
> DevTools (F12 → Network) — o DuckDB-WASM e o `fetch()` de parquet já
> causaram confusão de "versão antiga sendo servida" mais de uma vez
> durante o desenvolvimento.

---

## 6. Como publicar

1. Renomeie (ou copie) `map_br.html` para `index.html` na raiz do
   repositório, se for usar GitHub Pages.
2. Confirme que `R2_BASE` no início do `<script type="module">`
   aponta para a URL pública real do seu bucket R2.
3. Ative o GitHub Pages: repositório → Settings → Pages → Source:
   branch `main`, pasta `/ (root)`.
4. Confirme a política de CORS do R2 (seção 3) libera o domínio real
   do GitHub Pages publicado.

---

## 7. Limitações conhecidas e próximos passos

- **Hexágonos em fronteira entre UFs** aparecem associados a mais de
  uma UF no `uf_lookup.parquet` (um hexágono grande, especialmente na
  resolução 4, pode fisicamente cruzar a divisa de dois estados). Hoje
  o filtro de região/UF é **inclusivo** (mostra o hexágono se ele
  tocar a UF filtrada, mesmo que a maior parte dele esteja em outro
  estado) — o que pode ser visualmente confuso perto de fronteiras. A
  correção definitiva seria atribuir a UF pelo **centróide** do
  hexágono (que só pode estar dentro de uma UF), usando a malha oficial
  do IBGE (`geobr::read_state()`), em vez da intersecção do polígono
  inteiro.
- **Filtro por município** não está implementado — falta uma tabela de
  referência de códigos/nomes de município carregada no projeto.
- **Bounding boxes de UF usados para zoom automático são
  aproximados** — não vêm de uma fonte oficial, servem bem para
  centralizar o mapa mas não devem ser tratados como limite
  administrativo preciso.
- **O filtro de área roda via consulta SQL** (recarrega dados a cada
  troca de estado/região) em vez de um filtro puramente client-side —
  ver a nota na seção 4. Migrar de volta para `setFilter` do MapLibre
  seria mais eficiente, mas exigiria primeiro confirmar que o bug
  original (que motivou a mudança) não vai se repetir.
- **Apenas os anos 2013 e 2023 têm parquet de atributos gerado** no
  momento — os anos intermediários existem na fonte, mas ainda não
  foram processados/publicados.
- **A conexão com o pipeline de censura/agregação ainda não está
  ligada de fato**: o alvo `rais_df` deste pipeline hoje lê um parquet
  de origem diretamente; se este projeto usa outro pipeline `targets`
  para censura/anonimização antes deste ponto, falta apontar
  `carregar_rais()` para o output real desse outro pipeline (ver
  "Relação com outros pipelines `targets`" na seção 2).
- **`iteration = "list"` é fácil de remover por engano** e quebra o
  pipeline **silenciosamente** (sem erro — só gera um `geometria.pmtiles`
  incorreto). Não existe validação automática hoje que pegue esse
  problema; um teste que confira `length(geometrias_nomeadas) ==
  length(resolucoes)` antes de chamar `gerar_pmtiles()` seria uma
  proteção barata de adicionar.
- **O `crew_controller_local()` está comentado/desativado no
  `_targets.R` atual** — o pipeline foi validado de ponta a ponta
  (21 alvos, ~3 minutos) rodando sequencialmente, sem paralelização.
  O bloco do `controller`/`storage`/`retrieval` continua no arquivo,
  comentado, pronto para reabilitar quando fizer sentido (bases
  maiores, mais anos). Ao reabilitar, rode `targets::tar_destroy()`
  antes de testar de novo, e ajuste `workers` conforme os núcleos
  disponíveis na máquina — não há detecção automática.

---

## 8. Erros comuns ao rodar o pipeline `targets`

Registro de dois problemas reais que apareceram ao rodar este pipeline
pela primeira vez — as mensagens de erro do `targets` nesses casos
apontam pro sintoma, não pra causa, então vale documentar para quem
bater no mesmo.

### `cannot branch over empty target (resolucoes)`

Essa mensagem é **enganosa**: ela sugere que o problema está na
definição do `pattern = map(resolucoes)`/`cross(resolucoes, ...)` em
si, mas na prática ela aparece sempre que o **alvo que serve de base
pro branching falhou ao construir**, seja lá qual for o motivo real.
No caso deste projeto, a causa raiz não tinha nada a ver com
branching — era um pacote faltando (ver item abaixo). Antes de
mexer em `pattern`/`iteration`/`deployment`, **sempre rode isto
primeiro** para ver o erro de verdade:

```r
targets::tar_meta(fields = error, complete_only = TRUE)
```

### `could not find packages <pacote> in library paths`

Se `tar_option_set(packages = c(...))` lista um pacote que não está
instalado no ambiente, **todos os alvos falham ao tentar carregar o
ambiente de pacotes** — inclusive alvos triviais que nem usam aquele
pacote diretamente (ex. `resolucoes <- c(4, 6, 8)`). É por isso que um
alvo simples pode aparecer como `errored` sem nenhuma relação óbvia
com a mensagem de erro real, que só aparece no `tar_meta()`.

Correção: instalar o pacote faltante (`install.packages("freestiler")`
ou via GitHub, conforme a origem) e rodar `targets::tar_destroy()`
antes de tentar de novo.

### `format = "file"` com caminho relativo errado

Alvos `format = "file"` (como `caminho_rais`) exigem que o arquivo
**exista fisicamente** no caminho informado, resolvido a partir do
**working directory de onde o `targets` roda** — normalmente a raiz do
projeto (onde está o `_targets.R`), não a pasta pessoal do usuário nem
onde o arquivo foi originalmente baixado. Se o arquivo de origem foi
salvo em outro lugar (ex. `Downloads`), o alvo falha, e todo alvo que
depende dele falha em cascata.

Diagnóstico:
```r
getwd()
file.exists("./data/rais_test_20260727.parquet")
```

Se vier `FALSE`, ajuste `CAMINHO_RAIS` no `_targets.R` para o caminho
real, ou copie/mova o arquivo para dentro de `data/` na raiz do
projeto.

### Depois de corrigir qualquer um dos dois acima

```r
targets::tar_destroy()
targets::tar_make()
```

Se você desabilitou o `crew_controller_local()` temporariamente para
isolar algum desses erros (comentando o bloco `controller`/`storage`/
`retrieval` em `tar_option_set()`), pode reabilitar depois de
confirmar que o pipeline roda limpo sem ele — nos dois erros acima, o
`crew` nunca foi a causa real.

> Este pipeline já foi validado de ponta a ponta seguindo exatamente
> os passos acima (pacote faltante + caminho de arquivo corrigidos,
> `crew` mantido desativado) — 21 alvos completados em cerca de 3
> minutos, sem erros.

---

## 9. Glossário rápido

| Termo | O que é |
|---|---|
| **H3** | Sistema de indexação geoespacial hexagonal do Uber, usado para agregar dados em grades de tamanho e formato consistentes, em várias resoluções. |
| **PMTiles** | Formato de arquivo único que empacota uma pirâmide inteira de vector tiles, permitindo servir mapas vetoriais direto de um storage estático (sem servidor de tiles dedicado). |
| **Vector tile** | Um "pedaço" de mapa (geometria + atributos) recortado por zoom/x/y, no formato usado por bibliotecas como o MapLibre. |
| **`feature-state`** | Mecanismo do MapLibre para associar dados dinâmicos a uma feature já desenhada, sem precisar regerar a geometria. |
| **DuckDB-WASM** | Versão do banco de dados DuckDB compilada para rodar dentro do navegador (WebAssembly), permitindo consultas SQL reais sobre arquivos remotos (Parquet, CSV) sem servidor. |
| **CORS** | Política de segurança do navegador que controla se um site pode ler a resposta de uma requisição feita a outro domínio. Precisa estar configurada corretamente no bucket R2, ou o navegador bloqueia os dados mesmo que a requisição "funcione" tecnicamente. |
| **HTTP Range request** | Requisição que pede só um pedaço (intervalo de bytes) de um arquivo, em vez do arquivo inteiro — é o que permite o PMTiles/DuckDB-WASM ler só o necessário de arquivos grandes remotos. |
| **`targets`** | Pacote R para pipelines reprodutíveis, com cache automático e execução só do que mudou. |
| **Branching dinâmico (`pattern`)** | Mecanismo do `targets` para rodar o mesmo alvo várias vezes automaticamente, uma vez por elemento de um vetor (`map()`) ou por combinação de vetores (`cross()`) — cada execução é uma "branch". |
| **`crew`** | Pacote que adiciona paralelização real ao `targets` — distribui as branches entre múltiplos processos R (workers) rodando ao mesmo tempo, em vez de uma de cada vez. |
| **`iteration`** | Controla como um alvo ramificado (`pattern`) entrega seus resultados para o próximo alvo: `"vector"` (padrão) combina tudo automaticamente num objeto só; `"list"` mantém cada branch separada numa lista. Trocar isso sem querer pode quebrar um pipeline silenciosamente. |
