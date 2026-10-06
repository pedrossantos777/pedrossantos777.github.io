library(arrow)
library(dplyr)
library(sf)
library(h3jsr)
library(freestiler)
library(purrr)

# ====================================================================
# NOVA ARQUITETURA — geometria e atributos separados
#
# Saída:
#   geometria.pmtiles                  -> geometria dos hexágonos, 1x
#   dados/hex_r04_2013.parquet ...      -> atributos por resolução x ano
#   dados/hex_r06_2013.parquet ...
#   dados/hex_r08_2013.parquet ...
# ====================================================================

# --------------------------------------------------------------------
# 0. Carregar a base (ajuste o caminho conforme o seu ambiente)
# --------------------------------------------------------------------
df <- arrow::open_dataset("./data/rais_test_20260727.parquet") |>
  collect()

resolucoes_alvo <- c(4, 6, 8)

if (!dir.exists("dados")) dir.create("dados")

# --------------------------------------------------------------------
# 1. GEOMETRIA — uma linha por hexágono, sem repetir por ano
#    (uf/code_intermediate/code_muni são atributos fixos no espaço,
#     por isso vão aqui e não no parquet de atributos)
# --------------------------------------------------------------------
preparar_geometria <- function(df, resolucao) {
  df |>
    filter(h3_res == resolucao) |>
    distinct(h3_address) |>
    mutate(geometry = cell_to_polygon(h3_address)) |>
    st_as_sf(crs = 4326)
}

# checagem de sanidade antes de gerar: um h3_address não pode ter mais
# de uma combinação de uf/code_intermediate/code_muni entre os anos
checar_duplicidade_geometria <- function(df, resolucao) {
  duplicados <- df |>
    filter(h3_res == resolucao) |>
    distinct(h3_address) |>
    count(h3_address) |>
    filter(n > 1)
  
  if (nrow(duplicados) > 0) {
    warning(sprintf(
      "Resolução %d: %d hexágono(s) com mais de uma combinação de uf/code_intermediate/code_muni entre os anos. Resolva antes de gerar a geometria.",
      resolucao, nrow(duplicados)
    ))
  }
  duplicados
}

for (res in resolucoes_alvo) {
  checar_duplicidade_geometria(df, res)
}

geometrias <- map(resolucoes_alvo, ~ preparar_geometria(df, .x))
names(geometrias) <- sprintf("h3_r%02d", resolucoes_alvo)

for (res in resolucoes_alvo) {
  cat(sprintf("Resolução %d: %d hexágonos únicos\n", res, nrow(geometrias[[sprintf("h3_r%02d", res)]])))
}

if (file.exists("geometria.pmtiles")) file.remove("geometria.pmtiles")

freestile(
  geometrias,
  "geometria.pmtiles",
  drop_rate = 2.5,
  coalesce = FALSE   # NUNCA TRUE aqui — coalesce fundiria hexágonos
  # adjacentes com atributos iguais, quebrando a
  # identidade individual de h3_address que o
  # feature-state no navegador precisa pra funcionar
)

cat("geometria.pmtiles gerado.\n")

# --------------------------------------------------------------------
# 2. ATRIBUTOS — um parquet por resolução x ano
#    (ano não vira coluna — vira parte do nome do arquivo)
# --------------------------------------------------------------------
preparar_atributos <- function(df, resolucao, ano_alvo) {
  df |>
    filter(h3_res == resolucao, ano == ano_alvo) |>
    group_by(h3_address) |>
    summarise(across(c(n_firmas, qt_vinc_ativos), ~sum(.x, na.rm = TRUE)), .groups = "drop")
}

anos_disponiveis <- sort(unique(df$ano))
cat(sprintf("Anos encontrados: %s\n", paste(anos_disponiveis, collapse = ", ")))

for (res in resolucoes_alvo) {
  for (ano_alvo in anos_disponiveis) {
    atributos <- preparar_atributos(df, res, ano_alvo)
    
    if (nrow(atributos) == 0) {
      warning(sprintf("Resolução %d, ano %d: 0 linhas — pulei a exportação.", res, ano_alvo))
      next
    }
    
    caminho <- sprintf("dados/hex_r%02d_%d.parquet", res, ano_alvo)
    write_parquet(atributos, caminho)
    cat(sprintf("%s (%d linhas)\n", caminho, nrow(atributos)))
  }
}

# --------------------------------------------------------------------
# 3. Conferência final antes de subir pro R2
# --------------------------------------------------------------------
cat("\n--- Resumo ---\n")
cat(sprintf("geometria.pmtiles: %.1f MB\n", file.size("geometria.pmtiles") / 1024^2))

arquivos_parquet <- list.files("dados", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Parquets gerados: %d arquivo(s)\n", length(arquivos_parquet)))
cat(sprintf("Tamanho total dos parquets: %.1f MB\n", sum(file.size(arquivos_parquet)) / 1024^2))

# esperado: 3 resoluções x N anos = length(resolucoes_alvo) * length(anos_disponiveis) arquivos
cat(sprintf("Esperado: %d arquivos (%d resoluções x %d anos)\n",
            length(resolucoes_alvo) * length(anos_disponiveis),
            length(resolucoes_alvo), length(anos_disponiveis)))

# --------------------------------------------------------------------
# 4. Próximo passo (fora do R): subir pro Cloudflare R2
# --------------------------------------------------------------------
# rclone copyto geometria.pmtiles minha-config:meu-bucket/geometria.pmtiles --progress
# rclone copy   dados/                minha-config:meu-bucket/dados/       --progress
#
# Confirme CORS do bucket liberando GET/HEAD com header Range, igual
# já configuramos antes para o hex_br.pmtiles.

uf_lookup <- bind_rows(
  geometrias[["h3_r04"]] |> st_drop_geometry() |> distinct(h3_address, uf) |> mutate(uf = purrr::map_chr(uf, 1)),
  geometrias[["h3_r06"]] |> st_drop_geometry() |> distinct(h3_address, uf) |> mutate(uf = purrr::map_chr(uf, 1)),
  geometrias[["h3_r08"]] |> st_drop_geometry() |> distinct(h3_address, uf) |> mutate(uf = purrr::map_chr(uf, 1))
)

write_parquet(uf_lookup, "uf_lookup.parquet")
