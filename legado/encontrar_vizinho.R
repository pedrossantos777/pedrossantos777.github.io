#criar coluna de encontrar vizinho

# library(dplyr)
# tabela_raw <- targets::tar_read(rais_agregada_em_h3, branches = 1)
# res <- targets::tar_read(resolucao)[1]
#vizinhos = h3jsr::get_disk(h3_address = {{id_hex}}, ring_size = 1)

encontrar_vizinho <- function(tabela_raw, res, id_hex = "h3_address") {
  tabela_raw <- arrow::open_dataset(tabela_raw)
  
  id_hex <- rlang::sym(id_hex)
  
  tabela_vizinhos <- tabela_raw |>
    filter(h3_res == !!res) |>
    distinct({{ id_hex }}) |>
    collect()
  
  tabela_vizinhos <- tabela_vizinhos |>
    mutate(
      h3_vizinhos = h3r::gridDisk({{ id_hex }}, rep(1, nrow(tabela_vizinhos)))
    ) |>
    select({{ id_hex }}, h3_vizinhos)
  
  return(tabela_vizinhos)
}

#criar coluna de encontrar vizinho



