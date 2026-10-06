# ======================================================================
# R/funcoes_hex_pmtiles.R
#
# Funções usadas pelo pipeline _targets.R que gera:
#   - geometria.pmtiles          (geometria dos hexágonos, 1x)
#   - dados/hex_rXX_ANO.parquet  (atributos por resolução x ano)
#   - uf_lookup.parquet          (h3_address -> uf, para filtro no dashboard)
#
# Carregadas via tar_source("./R") no _targets.R.
# ======================================================================

# ----------------------------------------------------------------------
# 1. Recebe os dados da RAIS
# ----------------------------------------------------------------------

#' Lê o parquet bruto da RAIS (já agregado em H3, multi-resolução) e
#' coleta em memória. Usada 1x no início do pipeline — os targets
#' seguintes derivam tudo a partir do df retornado aqui.
carregar_rais <- function(caminho_parquet) {
  arrow::open_dataset(caminho_parquet) |>
    dplyr::collect()
}

# ----------------------------------------------------------------------
# 2. Seleciona as resoluções dos hexágonos (geometria)
# ----------------------------------------------------------------------

#' Gera a geometria de UMA resolução — uma linha por hexágono, sem
#' repetir por ano. uf/code_intermediate/code_muni são atributos fixos
#' no espaço (um hexágono não muda de estado/município entre anos),
#' por isso entram aqui, e não no parquet de atributos por ano.
#'
#' IMPORTANTE: uf/code_intermediate/code_muni às vezes chegam como
#' list-column (arrow_list) dependendo de como o parquet de origem foi
#' gravado — isso quebra silenciosamente consultas SQL no DuckDB-WASM
#' mais tarde (Binder Error: upper(VARCHAR[])). Por isso já achatamos
#' com purrr::map_chr(coluna, 1) aqui, na origem, em vez de deixar
#' para corrigir no dashboard depois.
preparar_geometria <- function(df, resolucao) {
  df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::distinct(h3_address, uf, code_intermediate, code_muni) |>
    dplyr::mutate(
      uf = purrr::map_chr(uf, 1),
      code_intermediate = purrr::map_chr(code_intermediate, 1),
      code_muni = purrr::map_chr(code_muni, 1)
    ) |>
    dplyr::mutate(geometry = h3jsr::cell_to_polygon(h3_address)) |>
    sf::st_as_sf(crs = 4326)
}

#' Checagem de sanidade por resolução: um h3_address não pode ter mais
#' de uma combinação de uf/code_intermediate/code_muni entre os anos
#' (um hexágono não deveria "trocar" de estado). Só avisa (warning),
#' não interrompe o pipeline — decisão de desempate fica para quem
#' rodar, caso apareça.
checar_duplicidade_geometria <- function(df, resolucao) {
  duplicados <- df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::distinct(h3_address, uf, code_intermediate, code_muni) |>
    dplyr::count(h3_address) |>
    dplyr::filter(n > 1)
  
  if (nrow(duplicados) > 0) {
    warning(sprintf(
      "Resolução %d: %d hexágono(s) com mais de uma combinação de uf/code_intermediate/code_muni entre os anos.",
      resolucao, nrow(duplicados)
    ))
  }
  duplicados
}

#' Junta a lista de geometrias (uma por ramificação de resolução) num
#' único objeto nomeado no padrão h3_r04/h3_r06/h3_r08 — é esse nome
#' que o freestile() usa como nome de CAMADA dentro do pmtiles, e que
#' o dashboard espera (sourceLayer: "h3_r04", etc.).
nomear_geometrias <- function(lista_geometrias, resolucoes_alvo) {
  stats::setNames(lista_geometrias, sprintf("h3_r%02d", resolucoes_alvo))
}

# ----------------------------------------------------------------------
# 3. Gera os PMTiles (geometria, uma vez só — não repete por ano)
# ----------------------------------------------------------------------

#' Empacota as geometrias nomeadas num único geometria.pmtiles, uma
#' camada por resolução. coalesce = FALSE é OBRIGATÓRIO: TRUE fundiria
#' hexágonos adjacentes com atributos iguais, destruindo a identidade
#' individual de h3_address que o feature-state no navegador precisa
#' para colar o valor certo no hexágono certo.
gerar_pmtiles <- function(geometrias_nomeadas, caminho_saida) {
  if (file.exists(caminho_saida)) file.remove(caminho_saida)
  
  freestiler::freestile(
    geometrias_nomeadas,
    caminho_saida,
    drop_rate = 2.5,
    coalesce = FALSE
  )
  
  caminho_saida
}

# ----------------------------------------------------------------------
# 4. Gera os parquets de atributos (resolução x ano) e o lookup de UF
# ----------------------------------------------------------------------

#' Agrega n_firmas/qt_vinc_ativos por hexágono, para UMA combinação
#' resolução x ano. O "ano" não vira coluna no arquivo final — vira
#' parte do nome do arquivo (ver exportar_atributos_parquet()).
preparar_atributos <- function(df, resolucao, ano_alvo) {
  df |>
    dplyr::filter(h3_res == resolucao, ano == ano_alvo) |>
    dplyr::group_by(h3_address) |>
    dplyr::summarise(
      dplyr::across(c(n_firmas, qt_vinc_ativos), ~ sum(.x, na.rm = TRUE)),
      .groups = "drop"
    )
}

#' Agrega e grava o parquet de UMA combinação resolução x ano em
#' dados/hex_rXX_ANO.parquet. Retorna o caminho do arquivo — é esse
#' retorno que o target usa com format = "file" para rastrear se o
#' arquivo mudou entre execuções.
exportar_atributos_parquet <- function(df, resolucao, ano_alvo, diretorio_saida = "dados") {
  if (!dir.exists(diretorio_saida)) dir.create(diretorio_saida, recursive = TRUE)
  
  atributos <- preparar_atributos(df, resolucao, ano_alvo)
  
  if (nrow(atributos) == 0) {
    warning(sprintf("Resolução %d, ano %d: 0 linhas — nada para exportar.", resolucao, ano_alvo))
    return(NA_character_)
  }
  
  caminho <- file.path(diretorio_saida, sprintf("hex_r%02d_%d.parquet", resolucao, ano_alvo))
  arrow::write_parquet(atributos, caminho)
  caminho
}

#' Gera o lookup h3_address -> uf, combinando as resoluções — é o
#' arquivo que o dashboard consulta via DuckDB-WASM (JOIN/subquery)
#' para filtrar por estado/região, sem precisar reprocessar geometria.
#' uf já vem achatada (purrr::map_chr) desde preparar_geometria(), não
#' precisa tratar de novo aqui.
gerar_uf_lookup <- function(geometrias_nomeadas, caminho_saida = "uf_lookup.parquet") {
  uf_lookup <- purrr::map_dfr(
    geometrias_nomeadas,
    ~ sf::st_drop_geometry(.x) |> dplyr::distinct(h3_address, uf)
  )
  
  arrow::write_parquet(uf_lookup, caminho_saida)
  caminho_saida
}
