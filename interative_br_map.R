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



#rais completa em todas as resoluções
df <- arrow::open_dataset("./data/rais_test_20260727.parquet") |>  
  collect()

#666666666666666666666666666

# ------------------------------------------------------------------
preparar_hex_df <- function(df, resolucao) {
  df |>
    filter(h3_res == resolucao) |>
    group_by(h3_address, ano, h3_res) |>
    summarise(across(c(n_firmas, qt_vinc_ativos), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
    as.data.frame() |>
    mutate(geometry = cell_to_polygon(h3_address)) |>
    st_as_sf(crs = 4326)
}

hex_res4 <- preparar_hex_df(df, 4)
hex_res6 <- preparar_hex_df(df, 6)
hex_res8 <- preparar_hex_df(df, 8)

anos_disponiveis <- sort(unique(hex_res6$ano))  # agora 2013:2023

 # ------------------------------------------------------------------
# 3. Tilagem (igual ao que já funcionava)
# ------------------------------------------------------------------
if (file.exists("hex.pmtiles_br")) file.remove("hex.pmtiles_br")

freestile(
  list(
    h3_r04 = hex_res4,
    h3_r06 = hex_res6,
    h3_r08 = hex_res8
  ),
  "hex.pmtiles_br",
  drop_rate = 2.5,
  coalesce = TRUE
)

serve_tiles(".", port = 8080)

resolucoes <- list(
  list(res = 4, min_zoom = 0, max_zoom = 7),
  list(res = 6, min_zoom = 7, max_zoom = 10),
  list(res = 8, min_zoom = 10, max_zoom = 14)
)


## ------------------------------------------------------------------
# 3. Paletas de cores — troque PALETA_ATIVA para testar cada uma
# ------------------------------------------------------------------
paletas <- list(
  viridis = viridisLite::viridis(5),
  cividis = viridisLite::cividis(5),
  blues   = RColorBrewer::brewer.pal(5, "Blues"),
  greens  = RColorBrewer::brewer.pal(5, "Greens")
)

paleta_ativa <- "viridis"   # troque para "cividis", "blues" ou "greens"
cores_ativas <- paletas[[paleta_ativa]]

# quantile(hex_res6$n_firmas, probs = c(0, .25, .5, .75, 1), na.rm = TRUE)
# quantile(hex_res6$qt_vinc_ativos, probs = c(0, .25, .5, .75, 1), na.rm = TRUE)

fill_firmas <- interpolate(
  column = "n_firmas",
  values = c(0, 25, 50, 100, 200),   # ajuste com quantile(hex_res6$n_firmas, ...)
  stops = cores_ativas
)

fill_vinc <- interpolate(
  column = "qt_vinc_ativos",
  values = c(0, 25, 50, 100, 200),   # ajuste com quantile(hex_res6$qt_vinc_ativos, ...)
  stops = cores_ativas
)

fill_ativo <- fill_firmas   # troque para fill_vinc para visualizar vínculos ativos
ano_filtro <- max(anos_disponiveis)

add_hex_layer <- function(map, info) {
  add_fill_layer(
    map,
    id = sprintf("fill-h3-r%02d", info$res),
    source = "hex",
    source_layer = sprintf("h3_r%02d", info$res),
    fill_color = fill_ativo,
    fill_opacity = 0.85,
    fill_outline_color = "rgba(255,255,255,0.3)",
    min_zoom = info$min_zoom,
    max_zoom = info$max_zoom,
    filter = list("==", "ano", ano_filtro),
    tooltip = "Firmas: {n_firmas}<br>Trabalhadores: {qt_vinc_ativos}<br>Ano: {ano}"
  )
}

# ------------------------------------------------------------------
# 4. Fundo do mapa — troque FUNDO_ATIVO para testar cada um
#    (todos gratuitos, sem chave de API)
# ------------------------------------------------------------------
basemaps <- list(
  osm = list(
    version = 8,
    sources = list(
      basemap = list(
        type = "raster",
        tiles = list("https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
        tileSize = 256,
        attribution = "&copy; OpenStreetMap contributors"
      )
    ),
    layers = list(list(id = "basemap", type = "raster", source = "basemap"))
  ),
  satelite = list(
    version = 8,
    sources = list(
      basemap = list(
        type = "raster",
        tiles = list("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"),
        tileSize = 256,
        attribution = "Esri, Maxar, Earthstar Geographics"
      )
    ),
    layers = list(list(id = "basemap", type = "raster", source = "basemap"))
  ),
  relevo = list(
    version = 8,
    sources = list(
      basemap = list(
        type = "raster",
        tiles = list("https://tile.opentopomap.org/{z}/{x}/{y}.png"),
        tileSize = 256,
        attribution = "&copy; OpenStreetMap contributors, SRTM | Map style: &copy; OpenTopoMap"
      )
    ),
    layers = list(list(id = "basemap", type = "raster", source = "basemap"))
  )
)

fundo_ativo <- "osm"   # troque para "satelite" ou "relevo"

# ------------------------------------------------------------------
# 5. Montagem do mapa
# ------------------------------------------------------------------
mapa <- add_pmtiles_source(
  maplibre(style = basemaps[[fundo_ativo]], bounds = hex_res6),
  id = "hex",
  url = "http://localhost:8080/hex.pmtiles_br"
)

for (info in resolucoes) {
  mapa <- add_hex_layer(mapa, info)
}

mapa
# 
# filtro espacial de estados - html
# escolher paleta de cores
# escolher tipo de fundo do mapa (se imagem de satelite, openstreetmap, relevo
#                                 escolher se usa a legenda do mapa com escala continua, ou escala discreta (quantis, e jenks) onde a a pessoa escolhe quantas categorias visualizar entre 4 e 8


uf_lookup <- bind_rows(
  hex_res4 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res6 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res8 |> st_drop_geometry() |> distinct(h3_address, uf)
)

write_parquet(uf_lookup, "uf_lookup.parquet")
write_parquet(hex_res4, "hex_res4.parquet")
write_parquet(hex_res6, "hex_res6.parquet")

write_parquet(hex_res8, "hex_res8.parquet")



