#gerar pmtiles  



#rais completa Censurada em todas as resoluções
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



#gerar os parquets para inserir no html

uf_lookup <- bind_rows(
  hex_res4 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res6 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res8 |> st_drop_geometry() |> distinct(h3_address, uf)
)

write_parquet(uf_lookup, "uf_lookup.parquet")
write_parquet(hex_res4, "hex_res4_cens4.parquet")
write_parquet(hex_res6, "hex_res6_cens4.parquet")
write_parquet(hex_res8, "hex_res8_cens4.parquet")


