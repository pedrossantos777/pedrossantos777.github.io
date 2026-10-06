library(ipeadatalake)
library(geobr)
library(sf)
library(mapview)
library(leafgl)
library(dplyr)
library(geoarrow)


mapview::mapviewOptions(platform = 'leafgl')
df <- "dados/rais_test_20260727.parquet"
dfrj <- "dados/rio_grade_09_rais2019_adaptado_censura.parquet"
dfrj <- arrow::open_dataset("dados/rio_grade_09_rais2019_adaptado_censura.parquet")|>
  collect()  
  
df1 <- arrow::open_dataset("dados/rais_test_20260727.parquet")|>
  collect()
  sf::st_as_sf()
names(df)
head(df) 
#encontrar os vizinhos de cada h3
df_vizinhos <- encontrar_vizinho(tabela_raw = dfrj, res = 'h3_res', id_hex = 'h3_address')

#df aplicado aos dados de censura
df_cens <- censura(tabela_raw = dfrj, tabela_vizinhos = df_vizinhos, barreira = 4, col_name = 'n_firmas', col_name2 = "qt_vinc_ativos")


summary(df$qt_firmas)
summary(df_cens$contagem)

density(df$qt_firmas) |> plot()
density(df_cens$contagem) |> plot()

head(df_cens)

temp <- df_cens |> sf::st_drop_geometry()
head(temp)

aaa <- left_join(df, temp, by = c('h3_address' = 'id_max_vizinho'))
  
aaa <- aaa |> mutate(diff_firmas = contagem_firmas - qt_firmas,
                     diff_empregos = contagem_empregos - qt_empregos)

aaa |> 
  arrange(desc(diff_firmas))
mapview(aaa,zcol='qt_firmas')

#firmas antes6666666666666666666666666666666666666666
aaa_before_firmas <- mapview(aaa,zcol='qt_firmas')
aaa_before_firmas
#depois666666666666666666666666666666666666666
aaa_after_firmas <- mapview(aaa,zcol='diff_firmas')
aaa_after_firmas
###############

#empregos antes6666666666666666666666666666666666666666
aaa_before_empregos <- mapview(aaa,zcol='qt_empregos')
aaa_before_empregos
#depois666666666666666666666666666666666666666
aaa_after_empregos <- mapview(aaa,zcol='diff_empregos')
aaa_after_empregos
###############
