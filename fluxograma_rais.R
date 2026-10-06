library(DiagrammeR)


codigo_fluxo <- "
digraph fluxo_basico_empregos_br {

  graph [layout = dot, rankdir = TB]

  node [shape = rectangle, style = filled, fontname = Helvetica]

  node [shape = oval, fillcolor = LightGreen]
  A [label = 'Inicio'] 
  X [label = 'Fim']
  
  node [shape = rectangle, fillcolor = LightBlue]
  B [label = 'Aplica os dados da RAIS \n aos dados de geolocalizacao']
  C [label = 'Distribui os dados \n em resolucoes H3']
  G [label = 'Publica a informacao']
  D [label = 'Determina a clausula de barreira']
  I [label = 'Anonimiza a informacao']
  H [label = 'Agrega os dados que nao cumprem a clausula \n do vizinho com mais empregos']

  node [shape = diamond, fillcolor = LightCoral]
  E [label = 'Cumpre a clausula?'] 
  F [label = 'Possui vizinhos \n com empregos?'] 
  

  A -> B
  B -> C
  C -> D 
  D -> E  
  E -> G [label = 'Sim'] 
  E -> F [label = 'Nao']
  F -> I [label = 'Nao']
  F -> H [label = 'Sim']
  H -> X
}
"

writeLines(codigo_fluxo, "meu_fluxo.gv")
grViz("meu_fluxo.gv")

