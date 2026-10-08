# library(targets)
# library(dplyr)
# library(ggplot2)
# library(h3jsr)
# 
# 
# #uma base só onde todas células h3 tenham pelo menos 2 escolas
# #identificar as células na escala 9 que tem menos de duas observações e nesses casos as escolas tem q ser agregadas na escala 7
# 
# tar_load(escolas_por_ano)
# # tar_load_h3 <-  count(escolas_por_ano, h3_res >= 2)
# 
# ######### 9999999999999999999999999999999999999999999999999999999999999999999
# # criar tabela na res maxima que cumprem criterio
# df09_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "9") |> 
#   filter(E001 >= 2) 
# 
# df09_NOT_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "9") |> 
#   filter_out(E001 >= 2) 
# 
# # vec de ids das celulas que NAO cumprem criterio
# h3_id_09_NOT_ok <- df09_NOT_ok$h3_address
# 
# #----------------------------------------------------------
# 
# 
# escolas_por_ano <- escolas_por_ano |>
#   filter(ano==2019 & h3_res == "9") |>
#   mutate(ok_09 = ifelse(E001>= 2, TRUE, FALSE))
# 
# 
# 
# 
# para quem ok = FALSE
#   detectar vizinho Ok com max value (h3jsr::get_disk('xxxxxxxxxxxffff', ring_size = 1))
#   se nao tiver - sem salvacao
#   se tiver - fazzer processo de relocalizacaorealocacao espacial
# 
# 
# 
# nrow(df09_NOT_ok)
# 
# 
# 
# df09_NOT_ok <- df09_NOT_ok |> 
#   mutate(  vizinhos = h3o::h3_from_strings(h3_address) |> h3o::grid_ring(k = 1)
#            )
# 
# i = 2
# temp_cell <- df09_NOT_ok[i,]
# 
# # checar
# # vec_vizinhos <- h3o::h3_from_strings(temp_cell$h3_address) |> h3o::grid_ring(k = 1)
# vec_vizinhos <- temp_cell$vizinhos #|> unlist()
# 
# # checa se viszinohs estao na base -  h3jsr::get_disk('xxxxxxxxxxxffff', ring_size = 1)
# cel_de_destino <- df09_ok |>
#   filter(h3_address %in% vec_vizinhos)
# 
# # checa qual vizinho tem  max value, essa celula é a celula de destino
# #quando todos os vizinho possuirem o mesmo valor? 
#   #- randomiza?
# # atualiza valores ("transfere o valor de uma ceclula para outra")
#   
# #-------------------------------------------------
# 
# # encontra os parents das ids q nao estao Ok
# h3_id_09_NOT_ok <- h3o::h3_from_strings(h3_id_09_NOT_ok)
# #h3 not ok sobre a res 9 -> encontre o parent na res 8
# h3_08_NOT_ok_at_09 <- h3o::get_parents(x = h3_id_09_NOT_ok, resolution = 8)
# 
# #nova coluna de parents H38
# #agrupa por h38 e indica quais estão atendendo ao criterio
# df_final09 <- df09_ok |>
#   mutate(
#     h3_obj = h3o::h3_from_strings(h3_address),
#     H38 = as.character(h3o::get_parents(h3_obj, resolution = 8))
#   ) |>
#   #agrupa por h38; indica e conta quantas celulas cumprem o critério
#   group_by(H38) |>
#   mutate(
#     n_ok = sum(E001<3)
#   ) |>
#   ungroup()
# 
# ######### 8888888888888888888888888888888888888888888888888888888888888888888888
# 
# # criar tabela na res maxima que cumprem criterio
# df08_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "8") |> 
#   filter(h3_address %in% h3_08_NOT_ok_at_09) |> 
#   filter(E001 >= 2) 
# 
# # vec de ids das celulas que NAO cumprem criterio
# h3_id_08_NOT_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "8") |> 
#   filter(E001 < 2) |> 
#   pull(h3_address)
# 
# # encontra os parents das ids q nao estao Ok
# h3_id_08_NOT_ok <- h3o::h3_from_strings(h3_id_08_NOT_ok)
# #h3 not ok sobre a res 8 -> encontre o parent na res 7
# h3_07_NOT_ok_at_08 <- h3o::get_parents(x = h3_id_09_NOT_ok, resolution = 7)
# 
# 
# 
# # remover duplicadas do nivel anterior
# id_08_ok <- unique(df08_ok$h3_address)
# id_08_ok <- h3o::h3_from_strings(id_08_ok)
# id_09_duplicados <- h3o::get_children(x = id_08_ok, resolution = 9)
# 
# 
# # converte em vetor
# id_09_duplicados <- unlist(id_09_duplicados) |> unlist()
# 
# # atualizada 09 ok removendo as duplicadas q estao na escala 08
# test <- df09_ok |> 
#   filter_out(h3_address %in% id_09_duplicados)
# 
# nrow(df09_ok)
# nrow(test)
# 
# ######### 777777777777777777777777777777777777777777777777777777777777777777777
# 
# 
# 
# df07_ok
# 
# # criar tabela na res maxima que cumprem criterio
# df07_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "7") |> 
#   filter(h3_address %in% h3_07_NOT_ok_at_08) |> 
#   filter(E001 >= 2) 
# 
# # vec de ids das celulas que NAO cumprem criterio
# h3_id_07_NOT_ok <- escolas_por_ano |> 
#   filter(ano==2019 & h3_res == "7") |> 
#   filter(E001 < 2) |> 
#   pull(h3_address)
# 
# # encontra os parents das ids q nao estao Ok
# h3_id_07_NOT_ok <- h3o::h3_from_strings(h3_id_08_NOT_ok)
# #h3 not ok sobre a res 7 -> encontre o parent na res 7
# h3_07_NOT_ok_at_09 <- h3o::get_parents(x = h3_id_09_NOT_ok, resolution = 7)
# 
# df07_ok
# 
# 
# #bind dos objetos
# df_ok <- dplyr::bind_rows(df07_ok, df08_ok, df09_ok)
# 
# 
# 
# # reomver duplicadas no nivel 9 SOMENTE quando houver um unico filho do 8 q nao ccumpre clausula minima
# # pq nesses casoss seria possivel "recuperar a info' fazendo calculo do residuo
# # MAS quanto tem pelo menos dois filhos problemativcos nao seria possivel recuperar a info