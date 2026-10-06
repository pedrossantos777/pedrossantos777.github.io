library(targets)
library(tarchetypes)
library(crew)

# ------------------------------------------------------------------------
# Opções do pipeline — mesmo padrão usado nos outros pipelines da equipe
# ------------------------------------------------------------------------
tar_option_set(
  memory = "transient",
  garbage_collection = TRUE,
  controller = crew_controller_local(
    workers = 6, # geometria/atributos por resolução x ano são independentes
    # entre si, então isso paraleliza bem — ajuste conforme
    # os núcleos disponíveis na máquina que for rodar
    options_local = crew_options_local(log_directory = "./logs/crew_workers")
  ),
  storage = "worker",
  retrieval = "worker",
  trust_timestamps = TRUE,
  error = "null",
  
  # package essentials -----------------------------------------------------
  packages = c(
    "arrow",
    "dplyr",
    "h3jsr",
    "purrr",
    "sf",
    "freestiler",
    "tarchetypes"
  )
)

# carrega as funções de R/funcoes_hex_pmtiles.R (e qualquer outra que
# você adicionar na pasta R/)
tar_source("./R")

# caminho do parquet de origem da RAIS — ajuste conforme seu ambiente
CAMINHO_RAIS <- "dados/rais_test_20260727.parquet"

# targets -----------------------------------------------------------------
list(
  
  # 1. Recebe os dados da RAIS -------------------------------------------
  
  # rastreia o arquivo de origem em si (format = "file") — se o parquet
  # bruto mudar (novo dump da RAIS), o targets detecta pela data de
  # modificação/hash e reprocessa tudo que depende dele a partir daqui
  tar_target(
    name = caminho_rais,
    command = CAMINHO_RAIS,
    format = "file"
  ),
  
  # carrega o parquet em memória — todo o resto do pipeline deriva
  # deste data.frame
  tar_target(
    name = rais_df,
    command = carregar_rais(caminho_rais)
  ),
  
  # detecta os anos disponíveis automaticamente a partir do dado —
  # evita hardcode de "2013:2023" que quebraria silenciosamente se
  # um ano novo entrar ou um antigo sair da base de origem
  tar_target(
    name = anos,
    command = sort(unique(rais_df$ano))
  ),
  
  # 2. Seleciona as resoluções dos hexágonos ------------------------------
  
  # único lugar do pipeline onde as resoluções são definidas — mudar
  # aqui propaga automaticamente para geometria, pmtiles e atributos,
  # sem precisar editar mais nada
  tar_target(
    name = resolucoes,
    command = c(4, 6, 8)
  ),
  
  # checagem informativa por resolução (ramifica em paralelo) — conta
  # quantos hexágonos tocam mais de uma UF (fronteira administrativa).
  # NÃO é usada para filtrar/alterar a geometria — é só um número para
  # você acompanhar; não bloqueia o pipeline
  tar_target(
    name = checagem_multi_uf,
    command = checar_hexagonos_multi_uf(rais_df, resolucoes),
    pattern = map(resolucoes)
  ),
  
  # gera a geometria de cada resolução em paralelo (uma branch por
  # resolução) — cada branch processa só a sua fatia do df, então o
  # crew consegue rodar as 3 resoluções ao mesmo tempo.
  # IMPORTANTE: a geometria carrega só h3_address (nenhuma coluna
  # administrativa) — ver a nota em preparar_geometria() no R/
  # sobre por que misturar uf aqui duplicava hexágonos no pmtiles
  tar_target(
    name = geometria_por_resolucao,
    command = preparar_geometria(rais_df, resolucoes),
    pattern = map(resolucoes),
    iteration = "list" # ESSENCIAL: sem isso, o targets combina as 3
    # geometrias num único objeto (comportamento
    # padrão de iteration="vector" para data.frame/sf)
    # em vez de manter uma lista separada — e
    # nomear_geometrias() precisa da lista separada
    # para nomear cada resolução individualmente
  ),
  
  # junta as branches acima numa lista nomeada (h3_r04/h3_r06/h3_r08)
  # — precisa ser um alvo "agregador" (sem pattern) porque o
  # freestile() espera receber a lista inteira de uma vez, não uma
  # geometria por vez
  tar_target(
    name = geometrias_nomeadas,
    command = nomear_geometrias(geometria_por_resolucao, resolucoes)
  ),
  
  # 3. Gera os PMTiles ------------------------------------------------------
  
  # gera geometria.pmtiles — UMA VEZ, não por ano (é esse o ponto
  # central da arquitetura: geometria não muda, só os atributos
  # mudam de ano para ano). format = "file" faz o targets rastrear o
  # arquivo de saída e só regenerar se as geometrias de entrada mudarem
  tar_target(
    name = geometria_pmtiles,
    command = gerar_pmtiles(geometrias_nomeadas, "geometria.pmtiles"),
    format = "file"
  ),
  
  # 4. Gera os parquets de atributos (resolução x ano) e o lookup de UF ----
  
  # ramificação cruzada: uma branch por combinação resolução x ano
  # (3 resoluções x N anos = 3N branches, cada uma gerando 1 arquivo).
  # format = "file" rastreia cada .parquet de saída individualmente —
  # se só um ano novo entrar na base, só as branches desse ano
  # reprocessam, as dos anos antigos ficam em cache
  tar_target(
    name = atributos_parquet,
    command = exportar_atributos_parquet(rais_df, resolucoes, anos, "dados"),
    pattern = cross(resolucoes, anos),
    format = "file"
  ),
  
  # lookup h3_address -> uf, usado pelo dashboard para filtrar por
  # estado/região via SQL (DuckDB-WASM) sem tocar na geometria.
  # Gerado DIRETO do rais_df (não da geometria — a geometria não
  # carrega mais uf, de propósito). Ramifica por resolução, igual à
  # geometria, mas são pipelines paralelos independentes: um hexágono
  # pode aparecer em mais de uma linha aqui (fronteira entre UFs) sem
  # que isso afete a geometria em nada
  tar_target(
    name = uf_lookup_por_resolucao,
    command = preparar_uf_lookup_parcial(rais_df, resolucoes),
    pattern = map(resolucoes)
  ),
  
  tar_target(
    name = uf_lookup_parquet,
    command = gerar_uf_lookup(uf_lookup_por_resolucao, "uf_lookup.parquet"),
    format = "file"
  )
)


