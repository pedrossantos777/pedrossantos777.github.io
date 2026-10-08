# censura_rapida(): reimplementacao vetorizada da logica de censura,
# validada contra o oraculo (otimizacao/censura_oraculo.R::censura_oraculo_v2).
# Criada FORA de R/ - R/censura_funcao.R nao e tocado.
#
# Ideia: em vez de, para CADA celula abaixo da barreira, filtrar a tabela
# inteira em busca dos seus vizinhos (custo ~ n_celulas_abaixo x n_linhas,
# feito hoje via group_split()+furrr::future_map()), resolve-se tudo em
# 2 joins:
#   1 valor+status de cada h3_address (1 linha por hexagono)
#   2 lista de arestas centro->vizinho (unnest da tabela_vizinhos)
#   3 join arestas x valores, slice_max por centro -> melhor vizinho de cada
#     hexagono (isso e o "encontra vizinho de maior valor", O(arestas)).
# custo ~ O(n_arestas) = O(7 x n_celulas), sem parelelismo/IPC.
#
# Semantica (igual a censura_oraculo_v2, a versao com a regressao do merge
# censura_v2 corrigida - ver RELATORIO.md):
#   - celula que atinge a barreira -> mantem o proprio id.
#   - celula abaixo -> vai para a celula de maior valor no seu anel-1
#     (incl. ela mesma); se essa celula-maxima nao atinge a barreira,
#     NA (descartada: "quem perdeu, perdeu").
#   - F001/T001 somados por (year, uf, code_muni, code_intermediate,
#     h3_res, h3_address de destino).

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(rlang)
})

censura_rapida <- function(tabela_raw, tabela_vizinhos, barreira, col_name, col_name2) {
  col  <- rlang::sym(col_name)
  col2 <- rlang::sym(col_name2)
  
  # NOTA: usa >= (nao > como o original em R/censura_funcao.R) - divergencia
  # DELIBERADA a pedido do usuario: celula com valor == barreira deve ser
  # tratada como segura para publicar. Isso faz censura_rapida() divergir do
  # oraculo (censura_oraculo.R, que replica o `> barreira` do original de
  # proposito) exatamente nas celulas cujo valor == barreira. RELATORIO.md/
  # DIFERENCAS.md e as comparacoes ja geradas (comparacao_*.csv) ainda
  # descrevem o comportamento antigo (`>`) e precisam ser revalidados.
  base <- arrow::open_dataset(tabela_raw) |>
    collect() |>
    mutate(atinge_barreira = as.integer(!!col >= barreira))
  
  if (n_distinct(base$h3_res) != 1) stop("Mais de uma resolucao!")
  # res > 8 foi validado (RJ/2023/res9: 236.109/239.239 = 98,7% preservado,
  # ver conversa em RELATORIO.md) e integrado em R/censura_funcao.R - o
  # guard que existia aqui foi removido.
  
  arestas <- tabela_vizinhos |>
    tidyr::unnest(h3_vizinhos) |>
    rename(viz = h3_vizinhos)
  
  # h3_address duplicado (hexagono cruza limite de municipio) pode ter
  # valores DIFERENTES em col_name entre as duplicatas (confirmado nos
  # dados de teste - ver RELATORIO.md). O original avalia TODAS as
  # duplicatas na busca por vizinho e fica com o maior valor entre elas;
  # aqui usamos max() para reproduzir exatamente isso (first() estava
  # errado e podia trocar o vizinho vencedor).
  valor_hex <- base |>
    group_by(h3_address) |>
    summarise(val = max(!!col), .groups = "drop") |>
    mutate(barr = as.integer(val >= barreira)) |>  # >= (ver nota acima)
    rename(viz = h3_address)
  
  # Empate de valor entre 2+ vizinhos: o original usa slice_max(with_ties=F)
  # sem regra de desempate documentada (ordem de linha incidental). Aqui o
  # desempate e explicito e deterministico (menor h3_address do vizinho),
  # para que o resultado nao dependa da ordem interna do join - ver
  # RELATORIO.md ("empates") sobre por que isso pode nao bater 1-a-1 com o
  # original em resolucoes finas mesmo com a soma F001/T001 identica.
  destino <- arestas |>
    inner_join(valor_hex, by = "viz") |>
    arrange(h3_address, desc(val), viz) |>
    group_by(h3_address) |>
    slice(1) |>
    ungroup() |>
    transmute(h3_address, viz_max = viz, viz_max_ok = barr == 1L)
  
  base |>
    left_join(destino, by = "h3_address") |>
    mutate(
      id_max_vizinho = case_when(
        atinge_barreira == 1L ~ h3_address,      # ja passa -> mantem
        viz_max_ok             ~ viz_max,         # abaixo, vizinho serve
        TRUE                   ~ NA_character_    # abaixo, ninguem serve
      )
    ) |>
    filter(!is.na(id_max_vizinho)) |>
    group_by(ano, uf, code_muni, code_intermediate, h3_res, id_max_vizinho) |>
    summarise(F001 = sum(!!col), T001 = sum(!!col2), .groups = "drop") |>
    rename(year = ano, abbrev_state = uf, h3_address = id_max_vizinho) |>
    arrange(abbrev_state, code_muni, code_intermediate)
}
