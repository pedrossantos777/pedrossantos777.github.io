library(arrow)
library(dplyr)
library(sf)
library(h3jsr)
library(freestiler)
library(mapgl)
library(purrr)
library(httr)
library(jsonlite)

#teste <- read_parquet("dados/rais_test_20260727.parquet")

preparar_hex <- function(caminho_parquet) {
  read_parquet(caminho_parquet) |>
    group_by(h3_address, year, h3_res) |>
    summarise(across(c(F001, T001), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
    as.data.frame() |>
    mutate(geometry = cell_to_polygon(h3_address)) |>
    st_as_sf(crs = 4326)
}

# um bind por resolução, juntando os anos 2022 e 2023
hex_res4 <- map(
  c("./data/rais_h3_2022_4.parquet", "./data/rais_h3_2023_4.parquet"),
  preparar_hex
) |> bind_rows()

hex_res6 <- map(
  c("./data/rais_h3_2022_6.parquet", "./data/rais_h3_2023_6.parquet"),
  preparar_hex
) |> bind_rows()

hex_res8 <- map(
  c("./data/rais_h3_2022_8.parquet", "./data/rais_h3_2023_8.parquet"),
  preparar_hex
) |> bind_rows()

anos_disponiveis <- sort(unique(hex_res6$year))  # 2022, 2023

if (file.exists("hex.pmtiles")) file.remove("hex.pmtiles") # garante que começa do zero

freestile(
  list(
    h3_r04 = hex_res4,
    h3_r06 = hex_res6,
    h3_r08 = hex_res8
  ),
  "hex.pmtiles"
)

serve_tiles(".", port = 8080)

resolucoes <- list(
  list(res = 4, min_zoom = 0, max_zoom = 7),
  list(res = 6, min_zoom = 7, max_zoom = 10),
  list(res = 8, min_zoom = 10, max_zoom = 14)
)


ano_filtro <- max(2023)  # troque aqui pra testar 2022 vs 2023 localmente

build_fill <- function(coluna, valores) {
  interpolate(
    column = coluna,
    values = valores,
    stops = viridisLite::viridis(5)
  )
}

fill_f001 <- build_fill("F001", c(0, 25, 50, 100, 200))
fill_t001 <- build_fill("T001", c(0, 50, 150, 400, 1000))  # ajuste com quantile()


add_hex_layer <- function(map, info, fill, ano_filtro) {
  add_fill_layer(
    map,
    id = sprintf("fill-h3-r%02d", info$res),
    source = "hex",
    source_layer = sprintf("h3_r%02d", info$res),
    fill_color = fill,
    fill_opacity = 0.85,
    fill_outline_color = "rgba(255,255,255,0.3)",
    min_zoom = info$min_zoom,
    max_zoom = info$max_zoom,
    filter = list("==", "year", ano_filtro),
    tooltip = "F001: {F001}<br>T001: {T001}<br>Ano: {year}"
  )
}


# pra testar F001:
# maplibre(bounds = hex_res6) |>
#   add_pmtiles_source(id = "hex", url = "http://localhost:8080/hex.pmtiles") |>
#   reduce(resolucoes, ~ add_hex_layer(.x, .y, fill_f001, max(anos_disponiveis)), .init = _)

# pra testar T001, troque fill_f001 por fill_t001 na linha acima
