library(dplyr)
library(geobr)


df <- arrow::open_dataset("./data/rais_h3_2023_8.parquet")  |> 
  collect()

res <- 8

rio <- geobr::read_state(2020, 33, cache = FALSE)

hex_rio <- h3o::sfc_to_cells(x = rio$geometry, resolution = res) |> 
  h3o::flatten_h3()

df_h6 <- df_h6 |> 
  filter(h3_res == res) |> 
  collect()

rio_h3 <- tibble(
  h3_address = as.character(hex_rio), geometry = st_as_sfc(hex_rio)
) |> 
  left_join(df_h6) |> 
  st_as_sf()

# summary(rio_h3$F001)
library(freestiler)

serve_tiles(".", port = 8080)  # este servidor suporta Range requests

maplibre(bounds = hex_res6) |>
  add_pmtiles_source(id = "hex", url = "http://localhost:8080/www/hex.pmtiles") |>
  add_fill_layer(
    id = "teste",
    source = "hex",
    source_layer = "h3_r06",
    fill_color = "red",
    fill_opacity = 1
  )
