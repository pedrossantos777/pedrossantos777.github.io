library(ipeadatalake)
library(geobr)
library(sf)
library(mapview)
library(leafgl)
library(dplyr)
library(geoarrow)

mapview::mapviewOptions(platform = 'leafgl')


# baixa malha do rio -----------------------------------------------------------
geobr::lookup_muni(name_muni = 'rio de janeiro')

muni <- geobr::read_municipality(
  code_muni = 3304557, 
  year = 2022
  )


# mapview(muni)

# encontra hexagonos no rio -----------------------------------------------------------

# id dos hexagonos
# hex_ids <- h3o::sfc_to_cells(
#   x = sf::st_as_sfc(muni), 
#   resolution = 7
#   )
get_grid <- function(poly, res) {
  hex_ids <- h3jsr::polygon_to_cells(geometry = poly, res = res)
  grid <- h3jsr::cell_to_polygon(hex_ids, simple = F)
  return(grid)
}

grid7 <- get_grid(muni, 7)
grid8 <- get_grid(muni, 8)
grid9 <- get_grid(muni, 9)

# mapview(muni) + grid9 + grid8 + grid7

# dados da rais agregados -----------------------------------------------------------


  #le a base de dados
  df <- ipeadatalake::ler_rais(
    ano = 2019,
    base = "estab", 
  ) |> 
    dplyr::filter(codemun == 330455 & uf == "RJ") |> 
    dplyr::select(id_estab, cnpj_raiz, cei_vinc, qt_vinc_ativos) |> 
    collect()
  

  #mescla as tabelas de geolocalizacao e de do censo escolar:
  df_geo  <- arrow::open_dataset("path.parquet")
  
  df_geo  <- df_geo |> 
    filter(id_estab %in% df$id_estab) |> 
    filter(Addr_type %in% c('PointAddress','StreetAddress')) |> 
    collect()
  
  df2 <- left_join(df, df_geo, by = 'id_estab')
  
  
df7 <- df2 |> 
  group_by(h3_res7) |> 
  summarise(qt_firmas = n(),
            qt_empregos = sum(qt_vinc_ativos)) |> 
  filter(qt_firmas>0)

df8 <- df2 |> 
  group_by(h3_res8) |> 
  summarise(qt_firmas = n(),
            qt_empregos = sum(qt_vinc_ativos)) |> 
  filter(qt_firmas>0)

df9 <- df2 |> 
  group_by(h3_res9) |> 
  summarise(qt_firmas = n(),
            qt_empregos = sum(qt_vinc_ativos)) |> 
  filter(qt_firmas>0)

df7_sf <- left_join(grid7, df7, by=c('h3_address' = 'h3_res7')) |> 
  mutate(qt_firmas= ifelse(is.na(qt_firmas), 0, qt_firmas),
         qt_empregos= ifelse(is.na(qt_empregos), 0, qt_empregos),
         )

df8_sf <- left_join(grid8, df8, by=c('h3_address' = 'h3_res8')) |> 
  mutate(qt_firmas= ifelse(is.na(qt_firmas), 0, qt_firmas),
         qt_empregos= ifelse(is.na(qt_empregos), 0, qt_empregos),
  )

df9_sf <- left_join(grid9, df9, by=c('h3_address' = 'h3_res9')) |> 
  mutate(qt_firmas= ifelse(is.na(qt_firmas), 0, qt_firmas),
         qt_empregos= ifelse(is.na(qt_empregos), 0, qt_empregos),
  )

arrow::write_parquet(df7_sf, './data/rio_grade_07_rais2019.parquet')
arrow::write_parquet(df8_sf, './data/rio_grade_08_rais2019.parquet')
arrow::write_parquet(df9_sf, './data/rio_grade_09_rais2019.parquet')


test <- arrow::open_dataset('./data/rio_grade_09_rais2019.parquet') |> 
  sf::st_as_sf()



