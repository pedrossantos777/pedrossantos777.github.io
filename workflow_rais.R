#fluxograma Rais

#montar um fluxograma para identificar as estratégias utilizadas para publicar espacialmente os dados da Rais

library(tidyverse)
library(tibble)
library(flowchart)

fluxo_rais <- tibble(
  
  
#  id = 1:8,

# nome = c("Coleta os dados da rais", "Agrega os dados de geolocalização", "Agrega os dados em resolução 7,8,9", "Determinar cláusula de barreira", 
#          "Cumpre a clausula?", "Possui vizinho que cumprem?", "Os vizinho possuem valores diferentes?", "Agrega os pontos ao vizinho de maior valor"),
# valor1 = c(TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE)

Coleta_os_dados_da_rais = c(TRUE, FALSE),
Agrega_os_dados_de_geolocalizacao = c(TRUE, FALSE),          
Agrega_os_dados_em_resolucao     = c(TRUE, FALSE),
Determinar_clausula_de_barreira   = c(TRUE, FALSE),
Cumpre_a_clausula   = c(TRUE, FALSE),
Possui_vizinho_que_cumprem  = c(TRUE, FALSE),
Os_vizinhos_possuem_valores_diferentes = c(TRUE, FALSE),
Agrega_ao_vizinho_de_maior_valor = c(TRUE, FALSE),
)




print(fluxo_rais)


#escreve a frase desejada
teste <-safo |> 
  flowchart::as_fc(label = "Workflow - anonimização e divulgação dos dados da Rais") 

step1 <-safo |> 
  flowchart::as_fc(label = "coleta os dados da Rais")

#printa a frase desejada 
teste |> 
  flowchart::fc_draw()

step1 |> 
  flowchart::fc_draw()


safo |> 
  as_fc(teste) |> 
  as_fc(step1) |> 
  fc_draw()
