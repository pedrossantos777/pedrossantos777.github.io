#este script na verdade é para gerar uma nova censura com base na censura otimizada para efeitos de comparação.


library(arrow)
library(dplyr)
library(sf)
library(h3jsr)
library(freestiler)
library(sf)
library(httr)
library(jsonlite)
library(mapgl)
library(purrr)

source("encontrar_vizinho.R")
source("../R/censura_funcao.R")

#rais completa em todas as resoluções
caminho_parquet <- "dados/rais_test_20260727.parquet"

# encontrar_vizinho() e censura() fazem arrow::open_dataset(tabela_raw)
# por dentro, e essa função (na versão instalada do pacote arrow) só
# aceita uma string de caminho - um data.frame em memória dá
# "Error: x is not a character vector", mesmo sem colunas de lista.
# Por isso cada resolução é filtrada e gravada num parquet temporário,
# e é o CAMINHO desse arquivo que entra em encontrar_vizinho()/censura().
#
# censura() também exige uma única resolução por chamada
# (stop("Mais de uma resolução!") se houver mais de uma h3_res), o que
# reforça a necessidade de um arquivo por resolução.
preparar_hex_df <- function(caminho_parquet, resolucao, barreira = 4) {
  caminho_resolucao <- file.path(tempdir(), paste0("rais_h3_res", resolucao, ".parquet"))

  arrow::open_dataset(caminho_parquet) |>
    filter(h3_res == resolucao) |>
    arrow::write_parquet(caminho_resolucao)

  tabela_vizinho <- encontrar_vizinho(
    tabela_raw = caminho_resolucao,
    res = resolucao,
    id_hex = "h3_address"
  )

  df_censurado <- censura(
    tabela_raw = caminho_resolucao,
    tabela_vizinhos = tabela_vizinho,
    barreira = barreira,
    col_name = "n_firmas",
    col_name2 = "qt_vinc_ativos"
  )

  # censura() renomeia uf -> abbrev_state; o group_by anterior (só por
  # h3_address/year/h3_res) descartava essa coluna ao somar. Incluir
  # uf = abbrev_state na chave mantém a informação - se um hexágono
  # cruzar limite de estado (raro, mas possível em resoluções baixas),
  # ele vira uma linha por uf em vez de perder a informação.
  #
  # Rede de segurança: hexágonos que cruzam fronteira de uf/município têm,
  # dentro de censura(), uma checagem de barreira que usa o maior valor
  # entre as duplicatas do MESMO h3_address (de propósito, para casar com
  # o oráculo - ver R/censura_funcao.R e otimizacao/RELATORIO.md). Isso faz
  # uma fatia que não atinge a barreira "se aceitar" usando o valor da
  # OUTRA fatia (outra uf) do mesmo hexágono, sem de fato somar nada -
  # publicando um F001 abaixo da barreira. Descartar aqui, depois de somar
  # por uf, garante que nenhuma linha publicada fique abaixo da barreira.
  df_censurado |>
    group_by(h3_address, year, h3_res, uf = abbrev_state) |>
    summarise(across(c(F001, T001), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
    filter(F001 >= barreira) |>
    as.data.frame() |>
    mutate(geometry = cell_to_polygon(h3_address)) |>
    st_as_sf(crs = 4326)
}


#gerar a base censurada por resolucao 
hex_res4 <- preparar_hex_df(caminho_parquet, 4)
hex_res6 <- preparar_hex_df(caminho_parquet, 6)
hex_res8 <- preparar_hex_df(caminho_parquet, 8)

#unificar a base censurada
uf_lookup_cens4 <- bind_rows(
  hex_res4 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res6 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res8 |> st_drop_geometry() |> distinct(h3_address, uf)
)


write_parquet(uf_lookup_cens4, "uf_lookup_cens4.parquet")

write_parquet(hex_res4, "hex_res4_cens4.parquet")
write_parquet(hex_res6, "hex_res6_cens4.parquet")
write_parquet(hex_res8, "hex_res8_cens4.parquet")
#write_parquet(uf_lookup, "uf_lookup.parquet")
anos_disponiveis <- sort(unique(hex_res6$year))  # agora 2013:2023

write_parquet(uf_lookup, "uf_lookup.parquet")

