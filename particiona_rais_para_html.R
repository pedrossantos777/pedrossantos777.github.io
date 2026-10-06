#carrega o parquet da rais e particiona por hexagonos para que sejam incluidos no html

caminho <- "dados/rais_test_20260727.parquet"

#rais completa Censurada em todas as resoluções


df <- arrow::open_dataset(caminho) |>  
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


#gerar os parquets para inserir no html
#uflookup -> gera os hexagonos de cada uf -> imutaveis
uf_lookup <- bind_rows(
  hex_res4 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res6 |> st_drop_geometry() |> distinct(h3_address, uf),
  hex_res8 |> st_drop_geometry() |> distinct(h3_address, uf)
)

#hex_resx -> escreve os parquets com as informações de cada resolucação

write_parquet(uf_lookup, "uf_lookup.parquet")
write_parquet(hex_res4, "hex_res4.parquet")
write_parquet(hex_res6, "hex_res6.parquet")
write_parquet(hex_res8, "hex_res8.parquet")
