# library(sf)
# library(mapview)
# library(leafgl)
# library(dplyr)
# library(geoarrow)
# 
# mapview::mapviewOptions(platform = 'leafgl')
# 
# df <- arrow::open_dataset("./data/rio_grade_07_rais2019 1.parquet") |> 
#   sf::st_as_sf()
# 
# h3jsr::get_disk(c("87a8a02f6ffffff", "87a8a0390ffffff")) |> unlist() |> unique() |> dput()
# 
# tabela_raw = df |> 
#   filter(h3_address %in% c(
#     "87a8a02f6ffffff", "87a8a0390ffffff",
#     "87a8a02f6ffffff", "87a8a02abffffff", "87a8a028dffffff", "87a8a02f2ffffff", 
#     "87a8a02f0ffffff", "87a8a02f4ffffff", "87a8a02a9ffffff", "87a8a0390ffffff", 
#     "87a8a0396ffffff", "87a8a0392ffffff", "87a8a0393ffffff", "87a8a0391ffffff", 
#     "87a8a0395ffffff", "87a8a0394ffffff"
#     ))
# 
# barreira = 3
# id_hex = 'h3_address'
# col_name = 'qt_firmas'

censura <-  function(tabela_raw, barreira, id_hex, col_name){
  
  id_hex <- rlang::sym(id_hex)
  col_name <- rlang::sym(col_name)
  
  # encontrar todos vizinhos -------------------------------------------------------------
  
  tabela <- tabela_raw |> 
    sf::st_drop_geometry() |> 
    mutate(
      atinge_barreira = if_else(!!enquo(col_name) > barreira, 1, 0),
      vizinhos = h3jsr::get_disk(h3_address = {{id_hex}}, ring_size = 1)
    )
  
  
  
  # encontrar o vizinho de maior count 
  #vizinhos <- coluna com a lista de vizinhos
  #all cells <-  vetor com o id(hex_id) das celulas
  #col <-  coluna com o valor de n valores
  #barreira <-  parametro para barrar
  # DIDATICA
  # vetor <- c("a","b","c","d","e")
  # names(vetor) <-  c("pedro", "arthur", "rafa", "luiz", "mario")
  # vetor[2] == "b"
  # vetor == "b"
  # vetor[vetor == "b"]
  # vetor[vetor %in% c("a", "f")]
  
  # encontra o id do vizinho que possui maio valor na coluna col
  find_max_vizinho <- function(vizinhos, all_cells, col, barreira){
    
    vizinhos_encontrados <- all_cells[all_cells %in% vizinhos[[1]]]
    
    values <- col[all_cells %in% vizinhos_encontrados]
    names(values) <- vizinhos_encontrados
    values <- values[values > barreira]
    
    if(length(values) == 0) {
      return(NA)
    }
    
    max_value <- values[which.max(values)]
    
    return(names(max_value[1]))
  }
  
  find_max_vizinho_2 <- function(data, id_hex, vizinhos, data_col, barreira_col) {
    data_split <- tabela |> 
      group_by({{id_hex}}) |> 
      group_split()
    
    data_split |> 
      purrr::map(
        function(x) {
          vec_vizinhos <- x |> 
            pull({{vizinhos}}) |> 
            unlist()
          
          max_viz <- data |> 
            filter({{id_hex}} %in% vec_vizinhos) |> 
            slice_max({{data_col}}, with_ties = F) |>
            mutate({{id_hex}} := ifelse({{barreira_col}} == 1, {{id_hex}}, NA)) |> 
            pull({{id_hex}})
          
          df <- x |> 
            mutate(id_max_vizinho = ifelse({{barreira_col}} == 1, {{id_hex}}, max_viz))
          
          return(df)
        }
      ) |> 
      data.table::rbindlist()
  }
  
  tabela <- find_max_vizinho_2(
    data = tabela, 
    id_hex = {{id_hex}}, 
    vizinhos = vizinhos, 
    data_col = {{col_name}}, 
    barreira_col = atinge_barreira
    )
  
  # find_max_vizinho(vizinhos = vizinhos, all_cells = all_cells, col = col, barreira = barr)
  
  # tabela <- tabela |> 
  #   group_by({{id_hex}}) |>
  #   mutate(
  #     id_max_vizinho = find_max_vizinho(
  #       vizinhos = vizinhos, 
  #       all_cells = {{id_hex}}, 
  #       col = {{col_name}}, 
  #       barreira = barreira
  #     )
  #   ) |>
  #   # adiciona q uma celula pode ser vizinha de se propria se ela cumpre barreira
  #   mutate(id_max_vizinho = ifelse(atinge_barreira == 1, {{id_hex}}, id_max_vizinho)) #|> 
  # # select(-vizinhos)
  
  
  # transfusao de valores
  # tabela <- sf::st_drop_geometry(tabela)
  tabela <- tabela |> 
    group_by(id_max_vizinho) |> 
    summarise(contagem = sum({{ col_name }}))
  
  
  #curly curly linhas 58, 63 e 73
  
  return(tabela)
}


#que m eh o  max vizi nho de 87a8a0390ffffff


