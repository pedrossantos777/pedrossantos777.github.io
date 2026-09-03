# Comparação dos parquets censurados — original × otimizada

**Data:** 2026-09-01
**Gerado por:** `comparar_parquets.R` (fora de `R/`; nenhuma função do pipeline alterada)
**Entrada:** `data/rais_test_20260727.parquet`, filtrado para **UF = RJ**, **barreira = 5 firmas**,
16 branches (2 anos × 8 resoluções H3), mesma lógica do `pattern = map(ano, resolução)` do `_targets.R`.

| | A — original | B — otimizada |
|---|---|---|
| Função | `censura()` (`R/censura_funcao.R`) | `censura_otimizada()` (`censura_otimizada.R`) |
| Arquivo | `data/otimizacao/rais_rj_censurada_barreira5.parquet` | `data/otimizacao/rais_rj_censurada_barreira5_otimizada.parquet` |

**Veredito:** os dois parquets **não são equivalentes**. As diferenças são dominadas por um
**bug de join na `censura()` original** (relação *many-to-many*) que **infla** as contagens de
firmas/vínculos em até ~290% nas resoluções grosseiras e **~48% no total**. Onde o bug não é
acionado (res ≥ 8), as **somas batem exatamente** e apenas ~0,6–1,4% das células mudam de destino
por causa de desempate. O parquet **B conserva a massa de firmas** e é o mais correto dos dois.

---

## 1. Comparação de arquivo (bit a bit)

| | A (original) | B (otimizada) |
|---|---|---|
| Tamanho | **220.236 bytes** | **220.097 bytes** |
| MD5 | `2bd9c63638782bb6da42761b0a2f7469` | `cbc6fbfca5ec033d9a868e9e48acb7eb` |
| SHA-256 | `45cfe575032f059c057b8219006b3431df9d1be20d3ebb8ea281ae3ddfb1eaf7` | `232ba5e63cb566b82352027957cbd462768b1c7a4e9d34d508d4a87c855a6453` |
| Magic bytes | `50 41 52 31` (`PAR1`) início e fim | idem |

- **Byte-idênticos? NÃO.**
- `cmp` acusa a **primeira divergência no byte 67**; **202.512** bytes diferem (de ~220 k).
- Isso é **esperado** e por si só não diz nada: os dois arquivos têm conteúdo diferente, ordem de
  linhas diferente e o Parquet ainda aplica *dictionary/RLE encoding* e *layout* de *row group*
  próprios. A comparação que importa é a de **conteúdo** (seções 3–5).

---

## 2. Esquema

**Idêntico.** Ambos têm as 8 colunas, mesmos tipos:

```
year: double | abbrev_state: string | code_muni: double | code_immediate: double
h3_res: int32 | h3_address: string | F001: int32 | T001: int32
```

---

## 3. Comparação de conteúdo (linha a linha)

Chave usada no *full join*: `year, abbrev_state, code_muni, code_immediate, h3_res, h3_address`
(o `h3_address = NA` — "balde" das células que não acham vizinho válido — é tratado como um valor).

### 3.1 Global

| métrica | valor |
|---|---:|
| Linhas em A | 24.697 |
| Linhas em B | 24.693 |
| Chaves distintas (união) | 24.701 |
| Só em A | **8** |
| Só em B | **4** |
| Em ambas | 24.689 |
| Em ambas, `F001` igual | 24.256 |
| Em ambas, `F001` difere | **433** |
| Em ambas, `T001` igual | 24.254 |
| Em ambas, `T001` difere | **435** |
| Σ `F001` — A | **5.804.740** |
| Σ `F001` — B | **3.914.438** |
| Σ `T001` — A | **100.340.190** |
| Σ `T001` — B | **68.827.387** |
| Maior \|Δ\| de `F001` numa célula | 555.090 |
| Maior \|Δ\| de `T001` numa célula | 10.494.150 |

A soma de firmas de A está **48,3% acima** da de B; a de vínculos, **45,8% acima**.

### 3.2 Por branch — a divergência está toda nas resoluções grosseiras

| ano | res | linhas A | linhas B | só A | só B | células F001 ≠ | Σ F001 A | Σ F001 B | Δ Σ F001 | Δ % | max \|Δ\| F001 |
|----:|----:|---------:|---------:|-----:|-----:|---------------:|---------:|---------:|---------:|----:|---------------:|
| 2013 | 2 | 10 | 10 | 0 | 0 | 10 | 946.331 | 242.674 | +703.657 | **+289,96%** | 543.129 |
| 2013 | 3 | 18 | 18 | 1 | 1 | 13 | 403.634 | 242.673 | +160.961 | **+66,33%** | 29.582 |
| 2013 | 4 | 55 | 54 | 2 | 1 | 29 | 303.790 | 242.670 | +61.120 | **+25,19%** | 18.288 |
| 2013 | 5 | 203 | 200 | 3 | 0 | 39 | 253.664 | 242.647 | +11.017 | +4,54% | 4.498 |
| 2013 | 6 | 582 | 581 | 1 | 0 | 9 | 242.573 | 242.321 | +252 | +0,10% | 110 |
| 2013 | 7 | 1.282 | 1.283 | 0 | 1 | 11 | 241.233 | 241.197 | +36 | +0,015% | 18 |
| 2013 | 8 | 3.160 | 3.160 | 0 | 0 | 18 | 239.015 | 239.015 | **0** | **0,00%** | 4 |
| 2013 | 9 | 6.692 | 6.692 | 0 | 0 | 98 | 230.999 | 230.999 | **0** | **0,00%** | 10 |
| 2023 | 2 | 9 | 9 | 0 | 0 | 9 | 967.105 | 250.863 | +716.242 | **+285,51%** | 555.090 |
| 2023 | 3 | 17 | 17 | 0 | 0 | 13 | 416.990 | 250.862 | +166.128 | **+66,22%** | 33.096 |
| 2023 | 4 | 52 | 52 | 0 | 0 | 26 | 309.701 | 250.858 | +58.843 | **+23,46%** | 19.202 |
| 2023 | 5 | 198 | 198 | 0 | 0 | 34 | 262.497 | 250.831 | +11.666 | +4,65% | 4.138 |
| 2023 | 6 | 593 | 593 | 0 | 0 | 6 | 250.910 | 250.569 | +341 | +0,14% | 190 |
| 2023 | 7 | 1.345 | 1.345 | 0 | 0 | 6 | 249.614 | 249.575 | +39 | +0,016% | 17 |
| 2023 | 8 | 3.367 | 3.367 | 0 | 0 | 22 | 247.445 | 247.445 | **0** | **0,00%** | 8 |
| 2023 | 9 | 7.114 | 7.114 | 1 | 1 | 90 | 239.239 | 239.239 | **0** | **0,00%** | 8 |

Observação: a Σ `F001` de **B** é praticamente constante por ano (~242,6 k em 2013, ~250,8 k em
2023) e igual à soma de `n_firmas` da entrada — ou seja, **B conserva a massa de firmas**. A leve
queda de B nas resoluções finas (231 k em res 9/2013) é esperada: mais células isoladas caem no
"balde NA" e não no total geográfico.

### 3.3 Top-5 divergências de célula (todas em res 2–3, ano 2023/2013)

| ano | code_muni | res | h3_address | F001 A | F001 B | Δ F001 | T001 A | T001 B | Δ T001 |
|----:|----------:|----:|---|-------:|-------:|-------:|-------:|-------:|-------:|
| 2023 | 3304557 (Rio de Janeiro) | 2 | `82a8a7fffffffff` | 740.120 | 185.030 | **+555.090** | 13.992.200 | 3.498.050 | +10.494.150 |
| 2013 | 3304557 | 2 | `82a8a7fffffffff` | 724.172 | 181.043 | +543.129 | 13.813.304 | 3.453.326 | +10.359.978 |
| 2023 | 3300308 | 2 | `82a8a7fffffffff` | 61.188 | 15.297 | +45.891 | 828.688 | 207.172 | +621.516 |
| 2013 | 3300308 | 2 | `82a8a7fffffffff` | 58.200 | 14.550 | +43.650 | 854.304 | 213.576 | +640.728 |
| 2023 | 3303906 | 2 | `82a8a7fffffffff` | 54.380 | 13.595 | +40.785 | 595.288 | 148.822 | +446.466 |

`F001_A ≈ 4 × F001_B` no caso do Rio: a mesma célula H3 res 2 é compartilhada por vários
municípios, e o *left join* sem `distinct()` a multiplica.

---

## 4. Comparação valor a valor (bit a bit lógico)

Ordenando A e B pela chave e comparando célula a célula, **por resolução**:

| h3_res | chaves alinhadas | `F001` idêntico | `T001` idêntico | células `F001` ≠ | células `T001` ≠ |
|-------:|:---:|:---:|:---:|---:|---:|
| 2 | sim | não | não | 19 | 19 |
| 3 | **não** | — | — | — | — |
| 4 | **não** | — | — | — | — |
| 5 | **não** | — | — | — | — |
| 6 | **não** | — | — | — | — |
| 7 | **não** | — | — | — | — |
| 8 | sim | não | não | 40 | 40 |
| 9 | **não** | — | — | — | — |

- "chaves alinhadas = não" significa que o **conjunto de chaves** difere entre A e B nessa
  resolução (há linha só em A ou só em B) — não dá para parear célula a célula.
- Onde dá para parear (res 2 e res 8), **nenhuma coluna é idêntica**: 19 e 40 células divergem.

---

## 5. Dump canônico (conteúdo, sem a camada Parquet)

Dump das duas tabelas para CSV **ordenado pela chave + valores** e SHA-256 do resultado — igual
se, e somente se, o conteúdo for 100% idêntico:

| | SHA-256 do CSV canônico |
|---|---|
| A | `2b42015c628da1a4863a17144c4ea9f6cc43e1697d7011eded6b3c688cb5f955` |
| B | `861bbc4685a6c208c45fc92f2db0f2c7b9077aeaa2486ce7d76480731f0cc6dd` |

**Conteúdo 100% idêntico? NÃO.**

---

## 6. Por que os dois diferem

### 6.1 Causa das grandes diferenças (res 2–5) — *bug* na `censura()` original

`R/censura_funcao.R`:

```r
tabela <- left_join(tabela, tabela_vizinhos, by = 'h3_address')   # sem distinct()
```

`tabela_vizinhos` é derivada de `tabela_raw`, que tem **uma linha por (município, célula H3)**.
Em resolução grosseira, **uma célula H3 cobre vários municípios** → o mesmo `h3_address` aparece
em várias linhas → o *join* vira *many-to-many* e **duplica as linhas da célula**. No `summarise`
final, `sum(F001)` conta a mesma firma uma vez por duplicata → **inflação**.

- res 2: célula do Rio compartilhada por ~4 municípios → `F001_A ≈ 4 × F001_B` (+290%).
- res 4 (usada em produção): **+25%**.
- res 6 (usada em produção): +0,1%.
- res ≥ 8: praticamente sem municípios compartilhando célula → inflação ≈ 0.

`censura_otimizada()` faz `distinct(h3_address, h3_vizinhos)` antes de explodir a lista de
vizinhos, então **B conserva a massa** (Σ `F001` de B = Σ `n_firmas` da entrada).

### 6.2 Causa das diferenças residuais (res ≥ 6) — desempate

Mesmo sem a inflação, ~0,5–1,4% das células mudam de célula-destino. Motivo:
`slice_max(..., with_ties = FALSE)` escolhe **a primeira** linha em caso de empate no valor de
`n_firmas`, e a "primeira" depende da ordem das linhas — que é diferente no caminho
`group_split()` (original) e no caminho `unnest + join` (otimizada). A **soma é conservada**
(Δ Σ = 0 em res 8–9); o que muda é **para qual vizinho** algumas células abaixo da barreira são
realocadas, e se elas caem dentro ou fora do "balde NA" (daí as 8 linhas só em A e 4 só em B).

---

## 7. Conclusão

| Aspecto | Resultado |
|---|---|
| Arquivos byte-idênticos | **Não** (esperado) |
| Esquema | **Igual** |
| Conteúdo idêntico | **Não** |
| Natureza das diferenças | (a) inflação *many-to-many* da `censura()` original em res ≤ 5 (até +290%, +48% no total); (b) desempate em ~0,6–1,4% das células em res ≥ 6, com soma conservada |
| Qual está correto | **B (otimizada)** — conserva a massa de firmas; A superconta |
| Impacto em produção (`_targets.R` usa res `c(4, 6)`) | res 4: A infla **~24%**; res 6: diferença ~0,1% |

**Recomendação:** aplicar o `distinct()` no *join* de vizinhos da `censura()` (ou migrar para a
`censura_otimizada()`), e padronizar a ordenação antes do `slice_max` para tornar o desempate
determinístico.

---

## 8. Como reproduzir

```sh
Rscript comparar_parquets.R
#  gera:
#   data/otimizacao/rais_rj_censurada_barreira5.parquet            (A, original)
#   data/otimizacao/rais_rj_censurada_barreira5_otimizada.parquet  (B, otimizada)
#   data/otimizacao/comparacao_parquets_resumo.csv
#   data/otimizacao/comparacao_parquets_por_branch.csv
#   data/otimizacao/comparacao_parquets_valor.csv
#   data/otimizacao/comparacao_parquets_top20.csv
#   data/otimizacao/comparacao_parquets.rds
#   data/otimizacao/comparacao_parquets.log
```
