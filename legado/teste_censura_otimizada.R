library(arrow)
library(dplyr)
library(sf)
library(h3jsr)
library(mapview)
library(mapgl)
library(htmlwidgets)

source("encontrar_vizinho.R")
source("censura_rapida.R")

res <- 8

df <- read_parquet("../../dados/hex_ipea_brasilia.parquet") %>%
  mutate(geometry = cell_to_polygon(h3_res8)) %>%
  st_as_sf(crs = 4326)

# encontrar_vizinho() e censura() so aceitam um caminho de parquet
# (repassado a arrow::open_dataset), e censura() tambem exige as colunas
# ano/uf/code_muni/code_intermediate para agrupar no final. hex_ipea_brasilia
# vem com schema cru (h3_res8, empregos, firmas), entao preparamos uma copia
# no schema esperado antes de chamar as funcoes; ano/uf/code_muni/
# code_intermediate sao fixos (Brasilia-DF) so pra a funcao ter o que agrupar.
hex_brasilia_prep <- read_parquet("../../dados/hex_ipea_brasilia.parquet") %>%
  rename(h3_address = h3_res8) %>%
  mutate(
    h3_res = res,
    ano = 2022,
    uf = "DF",
    code_muni = 5300108,
    code_intermediate = 5301
  )

hex_brasilia_prep_path <- "dados/hex_ipea_brasilia_prep.parquet"
write_parquet(hex_brasilia_prep, hex_brasilia_prep_path)

df_vizinhos <- encontrar_vizinho(tabela_raw = hex_brasilia_prep_path, res = res, id_hex = "h3_address")

df_cens <- censura_rapida(tabela_raw = hex_brasilia_prep_path, tabela_vizinhos = df_vizinhos, barreira = 100, col_name = "firmas", col_name2 = "empregos")

# tabela comparando firmas antes (df) e depois (df_cens) da censura; NA em
# firmas_depois = hexagono foi censurado e fundido no vizinho
tabela_comparacao <- df %>%
  st_drop_geometry() %>%
  select(h3_address = h3_res8, firmas_antes = firmas) %>%
  full_join(df_cens %>% select(h3_address, firmas_depois = F001), by = "h3_address") %>%
  arrange(desc(firmas_antes))

print(tabela_comparacao, n = Inf)
write.csv(tabela_comparacao, "dados/tabela_comparacao_censura_otimizada.csv", row.names = FALSE)

# reconstroi a geometria dos hexagonos sobreviventes (df_cens nao tem
# geometria) para o mapa "depois"
df_cens_sf <- df %>%
  select(h3_address = h3_res8, geometry) %>%
  inner_join(df_cens, by = "h3_address")

# mesma escala de cores nos dois mapas para a comparacao ser justa
escala_firmas <- range(c(df$firmas, df_cens$F001))
# 
# mapa_antes <- maplibre(bounds = st_bbox(df)) %>%
#   add_fill_layer(
#     id = "antes",
#     source = df,
#     fill_color = interpolate(column = "firmas", values = escala_firmas, stops = c("lightyellow", "darkred")),
#     fill_opacity = 0.85,
#     tooltip = "firmas"
#   )
# 
# mapa_depois <- maplibre(bounds = st_bbox(df)) %>%
#   add_fill_layer(
#     id = "depois",
#     source = df_cens_sf,
#     fill_color = interpolate(column = "F001", values = escala_firmas, stops = c("lightyellow", "darkred")),
#     fill_opacity = 0.85,
#     tooltip = "F001"
#   )
# 
# mapa_comparado <- compare(mapa_antes, mapa_depois, mode = "swipe")
# saveWidget(mapa_comparado, file.path(normalizePath("dados"), "comparacao_censura_otimizada.html"), selfcontained = TRUE)

# rotulo com o valor de cada hexagono)
mapa_depois_estatico <- ggplot(df_cens_sf) +
  geom_sf(aes(fill = F001), color = "white", linewidth = 0.1) +
  geom_sf_text(aes(label = F001), size = 2.5) +
  scale_fill_viridis_c(option = "magma", name = "Firmas", limits = escala_firmas) +
  labs(title = "Hexágonos apos censura antiga (df_cens), barreira = 3") +
  theme_minimal() +
  theme(axis.text = element_blank(), axis.ticks = element_blank())

print(mapa_depois_estatico)
ggsave("dados/mapa_dados_aleatorios_censura_antiga_barreira_3.png", mapa_depois_estatico, width = 8, height = 8, dpi = 150)
