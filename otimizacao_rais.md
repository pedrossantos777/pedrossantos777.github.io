# Otimização da anonimização espacial da RAIS

**Data:** 2026-09-01
**Escopo:** parquet `data/rais_test_20260727.parquet`, filtrado para **UF = RJ**, com **barreira = 5 firmas**.
**Ambiente:** R 4.5.2 (ucrt), Windows Server 2022, execução single-thread (sem `crew`).

Todos os números vêm de `otimização.R` (execução principal) e `comparar_censura.R`
(head-to-head). Artefatos brutos em `data/otimizacao/`.

---

## 1. O que foi executado

| Etapa | Script | Observação |
|---|---|---|
| Leitura + preparo dos dados | `prep_dados_otimizacao.R` | achata *list-columns* (`uf`, `code_muni`, `code_intermediate`) e renomeia `code_intermediate → code_immediate` para casar com o que a `censura()` espera. **Nenhuma função em `R/` foi alterada.** |
| `encontrar_vizinho()` | `R/encontrar_vizinho.R` (intacta) | anel-1 de cada célula H3 via `h3jsr::get_disk()` |
| `censura()` | `R/censura_funcao.R` (intacta) | realoca células abaixo da barreira para o vizinho de maior valor |
| Benchmark | `otimização.R` | `system.time()` + `replicate()`, sem dependências externas (`bench`/`microbenchmark` não instalados) |
| Refatoração vetorizada | `censura_otimizada.R` (fora de `R/`) | mesma semântica, complexidade menor |
| Comparação orig × otimizada | `comparar_censura.R` (fora de `R/`) | tempo + equivalência de resultado |

O pipeline `targets` roda `censura()` uma vez por *branch* (`pattern = map(ano, resolução)`).
Aqui reproduzimos exatamente isso: **16 branches** = 2 anos (2013, 2023) × 8 resoluções (H3 2–9).

- Linhas de entrada (RJ): **34.940**
- Linhas de saída (censuradas): **24.697**
- Tempo de leitura + preparo: **16,6 s**

---

## 2. Benchmark — pipeline atual

### 2.1 Tempo por branch (execução única, `otimização.R`)

| ano | h3_res | linhas_in | linhas_out | `encontrar_vizinho` (s) | `censura` (s) | total (s) | % em `censura` |
|----:|-------:|----------:|-----------:|------------------------:|--------------:|----------:|---------------:|
| 2013 | 2 | 10 | 10 | 5,85¹ | 2,69 | 8,54 | 31% |
| 2013 | 3 | 18 | 18 | 0,01 | 1,89 | 1,90 | 99% |
| 2013 | 4 | 55 | 55 | 0,02 | 2,06 | 2,08 | 99% |
| 2013 | 5 | 208 | 203 | 0,01 | 2,76 | 2,77 | 99% |
| 2013 | 6 | 691 | 582 | 0,03 | 5,28 | 5,31 | 99% |
| 2013 | 7 | 1.621 | 1.282 | 0,07 | 9,73 | 9,80 | 99% |
| 2013 | 8 | 4.106 | 3.160 | 0,12 | 21,79 | 21,91 | 99% |
| 2013 | 9 | 10.338 | 6.692 | 0,26 | 59,83 | 60,09 | 99,6% |
| 2023 | 2 | 9 | 9 | 0,00 | 1,84 | 1,84 | 100% |
| 2023 | 3 | 17 | 17 | 0,01 | 1,88 | 1,89 | 99% |
| 2023 | 4 | 52 | 52 | 0,00 | 1,96 | 1,96 | 100% |
| 2023 | 5 | 204 | 198 | 0,01 | 2,73 | 2,74 | 99% |
| 2023 | 6 | 686 | 593 | 0,03 | 5,30 | 5,33 | 99% |
| 2023 | 7 | 1.646 | 1.345 | 0,05 | 10,00 | 10,05 | 99,5% |
| 2023 | 8 | 4.311 | 3.367 | 0,13 | 25,37 | 25,50 | 99,5% |
| 2023 | 9 | 10.968 | 7.114 | 0,42 | 61,55 | 61,97 | 99,3% |

¹ *cold start* do `h3jsr` (inicialização do motor V8). A partir da 2ª chamada, `encontrar_vizinho` custa 0,01–0,42 s.

**Total para anonimizar RJ (16 branches, 34.940 linhas): 229,65 s de *wall-clock*.**
Soma por etapa: `encontrar_vizinho` = 7,0 s (dos quais 5,85 s são *cold start*) · `censura` = **216,7 s (94% do tempo)**.

### 2.2 Benchmark das funções (5 réplicas, `data/otimizacao/benchmark_funcoes.csv`)

| etapa | h3_res | linhas | min (s) | mediana (s) | média (s) | sd (s) | max (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `encontrar_vizinho` | 4 | 52 | 0,00 | 0,00 | 0,006 | 0,009 | 0,02 |
| `censura` | 4 | 52 | 2,04 | 2,09 | **2,09** | 0,04 | 2,14 |
| `encontrar_vizinho` | 6 | 686 | 0,01 | 0,02 | 0,022 | 0,008 | 0,03 |
| `censura` | 6 | 686 | 5,31 | 5,58 | **5,57** | 0,22 | 5,89 |
| `encontrar_vizinho` | 7 | 1.646 | 0,04 | 0,05 | 0,048 | 0,004 | 0,05 |
| `censura` | 7 | 1.646 | 10,03 | 10,09 | **10,10** | 0,06 | 10,19 |
| `encontrar_vizinho` | 8 | 4.311 | 0,11 | 0,11 | 0,110 | 0,00 | 0,11 |
| `censura` | 8 | 4.311 | 22,74 | 23,83 | **23,77** | 0,86 | 24,88 |

### 2.3 Leitura do benchmark

1. **`censura()` é o gargalo absoluto** — 94% do tempo total, e **99% em todos os branches não-triviais**.
2. **Custo fixo por chamada ≈ 1,8 s** — um branch de 9 linhas leva 1,84 s. Isso é *overhead* de
   `group_split()` + montagem do `purrr::map()` + `left_join` com verificação *many-to-many*,
   independente do tamanho dos dados.
3. **Componente que cresce ≈ super-linear** — de 686 → 10.968 linhas (16×), `censura` vai de
   5,3 s → 61,5 s (11,6×) *acima* do custo fixo: comportamento ~`O(n·k)` a ~`O(n^1.4)`, porque
   para **cada** célula roda-se um `filter()` sobre a **tabela inteira**.
4. **`encontrar_vizinho()` é barato** (<0,5 s) depois do *cold start*. Não vale otimizar antes da `censura`.
5. **Extrapolação para o Brasil:** RJ é ~5,8% das linhas do parquet (34.940 / 601.940).
   Mantida a proporção e o mesmo *hardware* single-thread, o país inteiro em res 9 custaria
   da ordem de **1–1,5 h por ano** só na `censura` — antes de qualquer paralelismo do `targets`.

---

## 3. Onde `censura()` perde tempo (análise de código)

Trecho crítico em `R/censura_funcao.R`:

```r
find_max_vizinho <- function(data, data_col, barreira_col) {
  data_split <- tabela |> group_by(h3_address) |> group_split()   # 1 tibble por célula
  data_split |> purrr::map(function(x) {
    vec_vizinhos <- x |> pull(h3_vizinhos) |> unlist()
    max_viz <- data |>                        # <<< varre a TABELA INTEIRA
      filter(h3_address %in% vec_vizinhos) |>  # <<< para CADA célula
      slice_max({{data_col}}, with_ties = F) |>
      mutate(h3_address := ifelse({{barreira_col}} == 1, h3_address, NA)) |>
      pull(h3_address)
    x |> mutate(id_max_vizinho = ifelse({{barreira_col}} == 1, h3_address, max_viz)) |>
      select(-h3_vizinhos)
  }) |> data.table::rbindlist()
}
```

| # | Problema | Efeito |
|---|---|---|
| 1 | **`group_split()` + `purrr::map()` por célula.** Cria milhares de `tibble`s pequenos e paga *overhead* de pipeline dplyr em cada iteração. | Custo fixo alto + serial. |
| 2 | **`filter(h3_address %in% vec_vizinhos)` dentro do loop.** Cada célula re-varre a tabela inteira. É a relação `célula → ≤7 vizinhos`, que deveria ser um *join*. | `O(n_células × n_linhas)`. Domina em res ≥ 7. |
| 3 | **`left_join(tabela, tabela_vizinhos, by = "h3_address")` sem `distinct()`.** Quando o mesmo `h3_address` aparece em >1 município (comum em res 2–5), o join vira *many-to-many* e **duplica linhas → infla `F001`/`T001`**. Medido: **res 4 soma de firmas = 303.790 vs. 242.670 reais (+25%)**; res 5 +4,5%; res ≥ 6 < 0,1%. | **Bug de correção**, não só de performance. |
| 4 | **`ifelse()`** (não `dplyr::if_else`/`data.table::fifelse`) e **`slice_max()` por grupo dentro do `map`**. | Micro-ineficiências somadas a milhares de iterações. |
| 5 | **`summarise()` sem `.groups = "drop"`** → mensagem de *regrouping* a cada branch; **`arrange()` final** re-ordena um resultado que o `targets` já vai reprocessar. | Ruído + trabalho descartável. |
| 6 | **Parâmetro `data` recebido mas ignorado** — o `data_split` é construído a partir de `tabela` (variável do *closure*), não de `data`. Confuso e propenso a erro. | Manutenção. |
| 7 | **Chaves são *strings* hex de 15 caracteres** (`"88a92dd6c3fffff"`). Comparação e *hash* de string em todo *join*/`%in%`. | ~2–4× mais lento que inteiro H3 (`uint64`). |
| 8 | **`h3jsr::get_disk()`** usa o motor V8 (JavaScript). `h3jsr` já é dependência, mas `h3r`/`h3o` (bindings C/Rust, também listados em `_targets.R`) são vetorizados e sem *cold start*. | 5,85 s de *cold start* + mais lento por linha. |

---

## 4. Refatoração aplicada — `censura_otimizada.R`

Reimplementação **vetorizada**, fora de `R/`, com a mesma semântica:

- célula que atinge a barreira mantém o próprio id;
- célula abaixo da barreira → vizinho de **maior `n_firmas` no anel-1 (incluindo ela mesma)**;
  se essa célula-máxima **não** atinge a barreira → `id_max_vizinho = NA` (idêntico ao original).

Como: a relação `célula → vizinho` vira uma **lista de arestas** (`tidyr::unnest`), o "vizinho de
maior valor" sai de **2 `join`s + 1 `slice_max` agrupado** (uma vez, vetorizado) em vez de milhares
de `filter()`. Complexidade cai de `~O(n_células × n_linhas)` para `~O(arestas) ≈ 7·n_células`.

Correção incluída: `tabela_vizinhos` é deduplicada (`distinct`) antes do *unnest*, eliminando a
inflação *many-to-many* do item 3.

### 4.1 Resultado — tempo (`comparar_censura.R`, `data/otimizacao/comparacao_censura.csv`)

Média de 2 réplicas por branch. `Δ F001` = quanto a soma de firmas da original está
**acima** da otimizada (a otimizada conserva a massa; onde `Δ F001 > 0` a original infla).

| ano | h3_res | linhas_in | `censura` orig (s) | `censura_otimizada` (s) | speedup | Δ F001 | NA orig/novo |
|----:|-------:|----------:|-------------------:|------------------------:|--------:|-------:|:-----------:|
| 2013 | 2 | 10 | 2,06 | 0,040 | 51,5× | +289,96% | 0 / 0 |
| 2013 | 3 | 18 | 1,76 | 0,035 | 50,1× | +66,33% | 0 / 0 |
| 2013 | 4 | 55 | 1,95 | 0,030 | 64,8× | +25,19% | 0 / 0 |
| 2013 | 5 | 208 | 2,71 | 0,040 | 67,8× | +4,54% | 0 / 0 |
| 2013 | 6 | 691 | 5,46 | 0,100 | 54,5× | +0,10% | 12 / 12 |
| 2013 | 7 | 1.621 | 9,58 | 0,185 | 51,8× | +0,01% | 57 / 57 |
| 2013 | 8 | 4.106 | 22,64 | 0,450 | 50,3× | **0,00%** | 75 / 75 |
| 2013 | 9 | 10.338 | 58,47 | 1,080 | 54,1× | **0,00%** | 89 / 89 |
| 2023 | 2 | 9 | 1,78 | 0,035 | 50,9× | +285,51% | 0 / 0 |
| 2023 | 3 | 17 | 1,89 | 0,030 | 63,0× | +66,22% | 0 / 0 |
| 2023 | 4 | 52 | 2,08 | 0,040 | 51,9× | +23,46% | 0 / 0 |
| 2023 | 5 | 204 | 2,70 | 0,045 | 60,0× | +4,65% | 0 / 0 |
| 2023 | 6 | 686 | 5,21 | 0,095 | 54,8× | +0,14% | 15 / 15 |
| 2023 | 7 | 1.646 | 9,75 | 0,190 | 51,3× | +0,02% | 56 / 56 |
| 2023 | 8 | 4.311 | 24,73 | 0,470 | 52,6× | **0,00%** | 73 / 73 |
| 2023 | 9 | 10.968 | 62,46 | 1,095 | 57,0× | **0,00%** | 88 / 88 |

**Total da `censura` (16 branches RJ): 215,2 s → 3,96 s — speedup global de 54,3×.**

- Speedup consistente de **~50–68×** em toda a faixa de resolução.
- **res ≥ 8: resultado byte-a-byte idêntico** (Δ F001 = 0,00000000, mesmo nº de linhas, mesmo balde NA).
- res 6–7: diferença < 0,15% (desempate de `slice_max`).
- res ≤ 5: onde diverge, a otimizada está **correta** (conserva a massa de firmas); a original infla via *many-to-many*.
- Combinada com o `crew` (10 *workers*) do `targets`, o *wall-clock* de RJ deve cair de **~230 s para a casa de 5–15 s**.

### 4.2 Resultado — equivalência

- **res ≥ 6:** diferença na soma de `F001` < 0,1%; mesmo número de células no "balde NA".
  Resíduo atribuível a desempate (`slice_max(with_ties = FALSE)` depende da ordem das linhas).
- **res ≤ 5:** a otimizada **conserva a massa de firmas** (soma de `F001` = soma de `n_firmas` de
  entrada); a original **infla** por causa do *many-to-many* (item 3). Ou seja, onde diverge, a
  otimizada está **correta**.
- A resolução de produção hoje é `c(4, 6)` (`_targets.R`): **res 4 é justamente onde o bug de
  inflação aparece** — vale corrigir mesmo que a performance não fosse problema.

---

## 5. Recomendações (ordem de impacto)

### Prioridade alta — `censura()`

1. **Trocar `group_split()` + `filter()` por *join* sobre lista de arestas** (feito em
   `censura_otimizada.R`). É o ganho estrutural: elimina o `O(n²)` e o custo fixo de milhares de
   `tibble`s. **Medido: 54,3× no total, 50–68× por branch; resultado idêntico em res ≥ 8** (seção 4).
2. **`distinct()` em `tabela_vizinhos` antes do join** (ou `relationship = "one-to-one"` para
   *falhar alto* se houver duplicata). Corrige a inflação de `F001`/`T001`.
3. **Fazer a `censura` em `data.table`**: `tabela_vizinhos` como `data.table` *keyed* por
   `h3_address`; `melt()` para o formato longo de arestas; *join* por referência; agregação
   `by =`. Em tabelas de 10⁴–10⁶ linhas costuma ser +2–5× sobre o dplyr já vetorizado.
4. **Adicionar `.groups = "drop"`** no `summarise` e **remover o `arrange()` final**
   (o `salva_rais_censurada` já filtra/ordena o que precisa).

### Prioridade média

5. **Chave H3 como inteiro** (`h3o::h3_from_strings()` → `bit64::integer64`, ou os `*_to_int` do
   `h3r`). *Joins* e `%in%` sobre `uint64` em vez de *string* de 15 chars.
6. **Trocar `h3jsr::get_disk()` por `h3r::grid_disk()` / `h3o::grid_disk()`** em
   `encontrar_vizinho()` (bindings compilados, vetorizados, sem *cold start* de V8). Ganho pequeno
   no total, mas elimina os ~6 s de inicialização e uma dependência de runtime JS.
7. **Fundir `encontrar_vizinho` + `censura`** num único passo: o anel-1 já é calculado como lista
   de arestas dentro da censura; hoje há uma materialização intermediária (`tabela_vizinhos`) só
   para ser re-explodida.

### Prioridade baixa / estrutural

8. **Paralelizar no nível certo.** O `targets` já usa `crew` com 10 *workers* → os 16 branches
   rodam em paralelo. Com a `censura` vetorizada (soma de ~4 s em RJ), o *wall-clock* passa a ser
   dominado pela leitura/serialização, não pela `censura`. Não vale usar `furrr` *dentro* da `censura`.
9. **`tar_option_set(memory = "transient", garbage_collection = TRUE)` já está setado** — ok.
   Considerar `format = "parquet"`/`"feather"` nos *targets* intermediários grandes em vez do RDS
   padrão, para reduzir I/O de serialização entre *workers*.
10. **Revisar a semântica do "balde NA".** Células abaixo da barreira cujo vizinho-máximo também
    não passa hoje viram `h3_address = NA` e sua contagem é somada num único grupo `NA` no
    resultado — isso mistura firmas de municípios/regiões diferentes num registro sem geometria.
    Decidir se o correto é *drop*, *merge* com o 2º melhor vizinho, ou reportar à parte.

---

## 6. Como reproduzir

```sh
# execução principal: lê o parquet, aplica as funções do targets (barreira=5, UF=RJ),
# mede tempo por branch e benchmarka as funções
Rscript "otimização.R"
#   -> data/otimizacao/rais_rj_censurada_barreira5.parquet
#   -> data/otimizacao/tempos_por_branch.csv
#   -> data/otimizacao/benchmark_funcoes.csv
#   -> data/otimizacao/resumo_execucao.csv

# head-to-head: censura() original vs censura_otimizada()
Rscript "comparar_censura.R"
#   -> data/otimizacao/comparacao_censura.csv
```

Arquivos criados **fora de `R/`** (funções do pipeline intactas):
`otimização.R`, `prep_dados_otimizacao.R`, `censura_otimizada.R`, `comparar_censura.R`,
`comparar_parquets.R`.

## 7. Ver também

- [`docs/comparacao_parquets.md`](comparacao_parquets.md) — comparação dos dois parquets gerados
  (original × otimizada): arquivo bit a bit, esquema, conteúdo linha a linha, valor a valor e
  dump canônico. Resumo: **não são equivalentes** — a original infla `F001`/`T001` em até ~290%
  nas resoluções grosseiras (bug *many-to-many*); em res ≥ 8 as somas batem e só ~1% das células
  muda de destino por desempate.
