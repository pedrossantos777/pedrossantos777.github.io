O site é alimentado principalmente por 3 arquivos principais: *
- PMTiles: Um tipo de arquivo vetorizado que possui os hexágonos conetados e permitem que a máquina faça o movimento de "zoom" à medida que os hexágonos surgem na tela.
- Os "tiles" nunca se alteram, os hexágonos sempre são os mesmos, logo são gerados apenas uma vez para a construção do site. Só é necessário gerar novos tiles caso deseje aumentar/diminuir a granularidade do zoom;
- Uflookup:: É um arquivo parquet que contém a lista de todos os hexágonos para cada UF. Esse arquivo permite que a máquina possa identificar a respectiva UF de cada hexágono na hora de azer os filtros; estes hexágonos
- também nunca se alteram, logo são gerados também apenas uma vez.
- H3_res4/h3_res6;h3_res8: Estes arquivos em parquet podem ser alterados, pois são os arquivos que contém as informações de cada hexágonos, ou seja, o número de firmas, trabalhadores, setor da economia, etc. Caso
- seja de interesse do autor o que representar em cada hexágono, esses arquivos devem ser alterados.
- Todos esses arquivos são gerados a partir dos scripts contidos da pasta "funcoes_principais".
