library(arrow)
library(dplyr)
library(sf)
library(h3jsr)
library(freestiler)
library(sf)
library(httr)
library(jsonlite)


#rais completa em todas as resoluções
df <- arrow::open_dataset("./data/rais_test_20260727.parquet") |>  
  collect()

#666666666666666666666666666


preparar_hex <- function(caminho_parquet) {
  read_parquet(caminho_parquet) |>
    group_by(h3_address, year, h3_res) |>
    summarise(across(c(F001, T001), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
    as.data.frame() |>
    mutate(geometry = cell_to_polygon(h3_address)) |>
    st_as_sf(crs = 4326)
}

hex_res4 <- preparar_hex("./data/rais_h3_2022_4.parquet")
hex_res6 <- preparar_hex("./data/rais_h3_2022_6.parquet")
hex_res8 <- preparar_hex("./data/rais_h3_2022_8.parquet")



file.remove("hex.pmtiles") # garante que começa do zero

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

fill <- interpolate(
  column = "F001",
  values = c(0, 25, 50, 100, 200),   # ajuste com quantile(hex_res6$F001, ...)
  stops = viridisLite::viridis(5)
)

add_hex_layer <- function(map, info) {
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
    tooltip = "F001: {F001}<br>T001: {T001}"
  )
}

maplibre(bounds = hex_res6) |>
  add_pmtiles_source(id = "hex", url = "http://localhost:8080/hex.pmtiles") |>
  reduce(resolucoes, add_hex_layer, .init = _)

#66666666666666666

teste <- read_parquet("data/rais_h3_2023_6.parquet")
head(teste$h3_address)
class(teste$h3_address)
poly_teste <- cell_to_polygon(head(teste$h3_address))
poly_teste  # deve ser uma lista de POLYGON válidos, não NA/vazio
