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
#' repetir por ano e SEM nenhuma coluna administrativa (uf/
#' code_intermediate/code_muni). Isso é proposital: um hexágono pode
#' tocar mais de uma UF/município (fronteira administrativa cruzando o
#' hexágono), e se essas colunas entrassem no distinct() aqui, cada
#' combinação extra geraria uma LINHA DE GEOMETRIA DUPLICADA — ou
#' seja, o mesmo hexágono desenhado mais de uma vez dentro do
#' geometria.pmtiles, causando artefato visual no mapa (foi
#' exatamente isso que aconteceu numa versão anterior desta função).
#' Informações administrativas (uf) vivem só no uf_lookup.parquet,
#' à parte — ver preparar_uf_lookup_parcial()/gerar_uf_lookup().
preparar_geometria <- function(df, resolucao) {
  df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::distinct(h3_address) |>
    dplyr::mutate(geometry = h3jsr::cell_to_polygon(h3_address)) |>
    sf::st_as_sf(crs = 4326)
}

#' Informativo (não bloqueia o pipeline): conta quantos hexágonos de
#' uma resolução tocam mais de uma UF — isto é, quantos vão aparecer
#' em mais de uma linha no uf_lookup.parquet. Isso é ESPERADO em
#' hexágonos de fronteira (mais comum na resolução 4, que é maior) e
#' já é tratado no lado do dashboard (subquery de existência, não
#' JOIN, para nunca duplicar o hexágono na hora de filtrar/classificar).
#' Serve só para você acompanhar a magnitude do fenômeno por resolução.
checar_hexagonos_multi_uf <- function(df, resolucao) {
  contagem <- df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::distinct(h3_address, uf) |>
    dplyr::mutate(uf = purrr::map_chr(uf, 1)) |>
    dplyr::count(h3_address) |>
    dplyr::filter(n > 1)
  
  message(sprintf(
    "Resolução %d: %d hexágono(s) tocam mais de uma UF (informativo).",
    resolucao, nrow(contagem)
  ))
  contagem
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

#' Gera o lookup h3_address -> uf de UMA resolução, direto do df bruto
#' (não da geometria — a geometria não carrega mais uf, ver nota em
#' preparar_geometria()). Achata a coluna uf (list-column -> string
#' simples) aqui, já que é aqui que ela é lida pela primeira vez para
#' esse fim.
preparar_uf_lookup_parcial <- function(df, resolucao) {
  df |>
    dplyr::filter(h3_res == resolucao) |>
    dplyr::distinct(h3_address, uf) |>
    dplyr::mutate(uf = purrr::map_chr(uf, 1))
}

#' Junta os lookups parciais (um por resolução) num único
#' uf_lookup.parquet. Pode conter mais de uma linha por h3_address —
#' isso é esperado (hexágono de fronteira entre UFs) e é responsabilidade
#' do consumidor (dashboard) lidar com isso via subquery de existência,
#' não JOIN direto, para não duplicar o hexágono na hora de usar.
gerar_uf_lookup <- function(lista_uf_por_resolucao, caminho_saida = "uf_lookup.parquet") {
  uf_lookup <- dplyr::bind_rows(lista_uf_por_resolucao)
  arrow::write_parquet(uf_lookup, caminho_saida)
  caminho_saida
}