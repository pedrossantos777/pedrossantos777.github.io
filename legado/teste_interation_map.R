library(freestiler)
library(sf)
library(httr)
library(jsonlite)

url2 <- "https://energy.usgs.gov/api/uswtdb/v1/turbines?&case_id=eq.3038257"

turbines <- jsonlite::fromJSON(url2)
turbines$capacity_mw <- turbines$t_cap / 1000   # t_cap is in kilowatts

turbines <- st_as_sf(turbines, coords = c("xlong", "ylat"), crs = 4326)

freestile_h3(
  turbines,
  "turbines.pmtiles",
  min_zoom = 2,
  max_zoom = 12,
  base_zoom = 10
)


freestile_h3(turbines, "turbines.pmtiles", agg = "count")

freestile_h3(
  turbines, "turbines.pmtiles",
  agg = c(
    n        = "COUNT(*)",
    total_mw = "SUM(capacity_mw)",
    avg_mw   = "AVG(capacity_mw)"
  )
)


freestile_h3(
  turbines, "turbines.pmtiles",
  agg = list(
    n        = c("count", "*"),
    total_mw = c("sum",  "capacity_mw"),
    avg_mw   = c("mean", "capacity_mw")
  )
)

view_h3_tiles(
  "turbines.pmtiles",
  agg_column = "n",
  stops = list(
    values = c(1, 10, 100, 1000, 10000),
    colors = viridisLite::viridis(5)
  )
)



freestile(df_23_espacial, "hex.pmtiles", layer_name = "h3_r06")
serve_tiles(".", port = 8080)

maplibre(bounds = df_23_espacial) |>
  add_pmtiles_source(id = "hex", url = "http://localhost:8080/hex.pmtiles") |>
  add_fill_layer(
    id = "fill-hex",
    source = "hex",
    source_layer = "h3_r06",
    fill_color = interpolate(
      column = "F001",
      values = c(0, 25, 50, 100, 200),
      stops = viridisLite::viridis(5)
    ),
    fill_opacity = 0.85,
    fill_outline_color = "rgba(255,255,255,0.3)",
    tooltip = "F001: {F001}<br>T001: {T001}"
  )

