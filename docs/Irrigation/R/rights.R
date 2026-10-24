#' Decreed use codes that count as irrigation
#'
#' 1 irrigation or X all beneficial uses. Used by `is_irrigation_use()`
#' everywhere a right is called irrigation.
irrigation_use_pattern <- "[1X]"

#' Public entities that may be named, with the label used in outputs
#'
#' Matched against upper-case contact or owner names only after the name
#' has been classed "public entity". Anything public but not listed here
#' keeps its class and loses its name.
public_entity_names <- tibble::tribble(
  ~pattern, ~label,
  "\\bASPEN\\b.*\\bCITY\\b|\\bCITY OF ASPEN\\b", "City of Aspen",
  "\\bCARBONDALE\\b.*\\bTOWN\\b|\\bTOWN OF CARBONDALE\\b", "Town of Carbondale",
  "\\bBASALT\\b.*\\b(TOWN|CITY)\\b|\\b(TOWN|CITY) OF BASALT\\b", "Town of Basalt",
  "SNOWMASS VILLAGE", "Town of Snowmass Village",
  "GLENWOOD SPRINGS", "City of Glenwood Springs",
  "\\bPITKIN\\b.*\\bCOUNTY\\b|COUNTY OF PITKIN", "Pitkin County",
  "\\bGARFIELD\\b.*\\bCOUNTY\\b|COUNTY OF GARFIELD", "Garfield County",
  "\\bEAGLE\\b.*\\bCOUNTY\\b|COUNTY OF EAGLE", "Eagle County",
  "BASALT WATER CONSERVANCY", "Basalt Water Conservancy District",
  "WEST DIVIDE WATER", "West Divide Water Conservancy District",
  "COLORADO RIVER WATER CONSERVATION|COLORADO RIVER DISTRICT", "Colorado River Water Conservation District",
  "COLORADO PARKS|DIVISION OF WILDLIFE|PARKS AND WILDLIFE", "Colorado Parks and Wildlife",
  "ASPEN SCHOOL DISTRICT", "Aspen School District RE-1",
  "ROARING FORK SCHOOL", "Roaring Fork School District RE-1",
  "STATE OF COLORADO|STATE BOARD OF LAND|STATE LAND BOARD", "State of Colorado",
  "UNITED STATES|\\bUSA\\b|FOREST SERVICE|BUREAU OF", "United States (federal)"
)

#' Sort a contact or owner name into an entity class
#'
#' Private markers are tested before public ones so that, for example,
#' "PITKIN COUNTY HOLDINGS LLC" is a private business. Ditch companies must
#' name a ditch, canal, reservoir, or irrigation company.
#'
#' @param x Character vector of names.
#' @return Character vector: none, public entity, ditch company, private business, individual.
classify_contact <- function(x) {
  u <- toupper(x)
  dplyr::case_when(
    is.na(x) | trimws(x) == "" ~ "none",
    grepl("ESTATE OF|HOMEOWNER|OWNERS ASS|PROPERTY OWNERS|\\bHOA\\b|\\bPOA\\b", u) ~ "private business",
    grepl("(DITCH|IRRIGATION|CANAL|RESERVOIR) (CO|COMPANY)\\b|DITCH ASS|WATER USERS|MUTUAL DITCH", u) ~
      "ditch company",
    grepl("\\b(LLC|L L C|INC|CORP|CORPORATION|LTD|LP|LLP|LLLP|TRUST|HOLDINGS|PARTNERS|PARTNERSHIP)\\b", u) ~
      "private business",
    grepl(paste(
      "CITY OF|TOWN OF|\\bCITY$|\\bTOWN$|COUNTY|DISTRICT|\\bWCD\\b",
      "^STATE OF|STATE OF COLORADO|COLORADO PARKS",
      "DIVISION OF WILDLIFE|UNITED STATES|BUREAU OF|FOREST SERVICE|AUTHORITY|CWCB|WATER CONSERVATION BOARD",
      sep = "|"
    ), u) ~ "public entity",
    grepl("\\bCO\\b|COMPANY|RANCH|CLUB|FARM|PROPERT|ASSOC|ESTATE|FAMILY", u) ~ "private business",
    TRUE ~ "individual"
  )
}

#' Name that may appear in outputs for a public entity or ditch company
#'
#' Public entities get a curated label from `public_entity_names`. Ditch
#' companies keep the company name up to "CO" or "COMPANY", after any
#' trailing ", <word>" or parenthetical person is removed. Every other
#' class returns NA, so no private name passes through.
#'
#' @param x Names.
#' @param class Classes from `classify_contact()`.
#' @return Character vector of public labels or NA.
public_name <- function(x, class) {
  u <- toupper(x) |>
    gsub(pattern = "\\s*\\(.*$|\\)", replacement = "") |>
    gsub(pattern = ",\\s*[A-Z]+\\.?$", replacement = "") |>
    trimws()
  curated <- vapply(u, \(n) {
    hit <- public_entity_names$label[vapply(public_entity_names$pattern, \(p) grepl(p, n), TRUE)]
    if (length(hit)) hit[1] else NA_character_
  }, "", USE.NAMES = FALSE)
  company <- stringr::str_extract(u, "^[A-Z0-9 &'.-]*(DITCH|IRRIGATION|CANAL|RESERVOIR) (CO|COMPANY)\\b")
  dplyr::case_when(
    class == "public entity" ~ curated,
    class == "ditch company" ~ company,
    TRUE ~ NA_character_
  )
}

#' Contacts on a structure, reduced to entity classes
#'
#' `associatedContacts` holds several contacts separated by `;`, often
#' with a person in parentheses after an organization. Only the classes
#' and curated public names are returned.
#'
#' @param x One `associatedContacts` string.
#' @return List: classes (sorted, comma-separated), public (public labels or NA).
summarise_contacts <- function(x) {
  parts <- trimws(strsplit(dplyr::coalesce(x, ""), ";")[[1]])
  parts <- trimws(gsub("\\s*\\(.*$|\\)", "", parts[parts != ""]))
  if (length(parts) == 0) return(list(classes = "none", public = NA_character_))
  cls <- classify_contact(parts)
  keep <- unique(stats::na.omit(public_name(parts, cls)))
  list(
    classes = paste(sort(unique(cls)), collapse = ", "),
    public = if (length(keep)) paste(keep, collapse = "; ") else NA_character_
  )
}

#' Structures in a water district, with contacts reduced to entity classes
#'
#' Raw contact names are never returned.
#'
#' @param water_district District number.
#' @param key CDSS API key.
#' @return Tibble: wdid, name, structure_type, ciu, water_source, county, stream_mile,
#'   contact_classes, contact_public, lat, lon.
fetch_structures_wd <- function(water_district = 38, key = cdss_key()) {
  x <- cdss_get("structures", waterDistrict = water_district, key = key)
  contacts <- lapply(x$associatedContacts, summarise_contacts)
  x |>
    dplyr::transmute(
      wdid, name = structureName, structure_type = structureType, ciu = ciuCode,
      water_source = waterSource, county, stream_mile = streamMile,
      contact_classes = vapply(contacts, `[[`, "", "classes"),
      contact_public = vapply(contacts, `[[`, "", "public"),
      lat = latdecdeg, lon = longdecdeg
    )
}

#' Net amount water rights for a water district
#'
#' @param water_district District number.
#' @param key CDSS API key.
#' @return Tibble: one row per net amount right.
fetch_net_rights <- function(water_district = 38, key = cdss_key()) {
  cdss_get("waterrights/netamount", waterDistrict = water_district, key = key) |>
    dplyr::transmute(
      wdid, structure_name = structureName, structure_type = structureType,
      water_source = waterSource,
      appropriation_date = as.Date(substr(appropriationDate, 1, 10)),
      adjudication_date = as.Date(substr(adjudicationDate, 1, 10)),
      admin_number = as.numeric(adminNumber),
      priority_number = priorityNumber,
      decreed_uses = decreedUses,
      net_absolute = as.numeric(netAbsolute),
      net_conditional = as.numeric(netConditional),
      decreed_units = decreedUnits,
      seasonal_limitation = seasonalLimitation
    )
}

#' Whether a decreed use string includes irrigation
#'
#' @param codes Concatenated decreed use codes such as `"18"`.
#' @return Logical.
is_irrigation_use <- function(codes) grepl(irrigation_use_pattern, dplyr::coalesce(codes, ""))

#' Label a decreed use code string such as `"18"`
#'
#' Uses `cdss_use_codes` from diversions.R.
#'
#' @param codes Character vector of concatenated codes.
#' @return Character vector of comma-separated labels.
decode_uses <- function(codes) {
  lookup <- rlang::set_names(cdss_use_codes$use, cdss_use_codes$code)
  vapply(strsplit(dplyr::coalesce(codes, ""), ""), \(ch) {
    paste(unique(stats::na.omit(lookup[ch])), collapse = ", ")
  }, "")
}

#' Absolute flow rights per ditch
#'
#' Counts cfs rights only (`decreed_units == "C"`). A right is irrigation
#' when `is_irrigation_use()` is TRUE.
#'
#' @param rights Tibble from `fetch_net_rights()`.
#' @return Tibble: wdid, n_rights, cfs_abs, cfs_irr, senior_admin, junior_admin, wmean_admin,
#'   first_approp, uses, nonirr_decree.
ditch_rights <- function(rights) {
  rights |>
    dplyr::filter(decreed_units == "C", net_absolute > 0) |>
    dplyr::mutate(irr = is_irrigation_use(decreed_uses)) |>
    dplyr::group_by(wdid) |>
    dplyr::summarise(
      n_rights = dplyr::n(),
      cfs_abs = sum(net_absolute),
      cfs_irr = sum(net_absolute[irr]),
      senior_admin = min(admin_number),
      junior_admin = max(admin_number),
      wmean_admin = stats::weighted.mean(admin_number, net_absolute),
      first_approp = min(appropriation_date, na.rm = TRUE),
      uses = decode_uses(paste(unique(decreed_uses), collapse = "")),
      nonirr_decree = any(!irr),
      .groups = "drop"
    )
}

#' Gini coefficient of a non-negative vector
#'
#' @param x Values (NAs dropped).
#' @return Gini, 0 (equal) to near 1 (one holder has everything).
gini <- function(x) {
  x <- sort(x[!is.na(x)])
  n <- length(x)
  if (n < 2 || sum(x) == 0) return(NA_real_)
  sum((2 * seq_len(n) - n - 1) * x) / (n * sum(x))
}

#' Share held by the largest holders
#'
#' @param x Values.
#' @param top Fraction of holders (e.g. 0.1) or, when >= 1, a count.
#' @return Share of the total held by the top holders.
top_share <- function(x, top = 0.1) {
  x <- sort(x[!is.na(x)], decreasing = TRUE)
  k <- if (top < 1) max(1, ceiling(top * length(x))) else min(top, length(x))
  sum(x[seq_len(k)]) / sum(x)
}

#' Lorenz curve points
#'
#' @param x Values.
#' @return Tibble: holders (cumulative share of holders), amount (cumulative share of the total).
lorenz <- function(x) {
  x <- sort(x[!is.na(x)])
  tibble::tibble(holders = c(0, seq_along(x) / length(x)), amount = c(0, cumsum(x) / sum(x)))
}

#' Concentration summary for one quantity across holders
#'
#' @param x Values, one per holder (NAs dropped).
#' @return Tibble: n, total, gini, top10pct_share, top10_share, holders_for_half.
concentration <- function(x) {
  x <- x[!is.na(x)]
  s <- sort(x, decreasing = TRUE)
  tibble::tibble(
    n = length(x),
    total = sum(x),
    gini = gini(x),
    top10pct_share = top_share(x, 0.1),
    top10_share = top_share(x, 10),
    holders_for_half = which(cumsum(s) >= sum(s) / 2)[1]
  )
}

#' Gini of a per-acre quantity across acres
#'
#' The population is acres, not holders: units are sorted by `amount / weight`
#' and the Lorenz curve runs over cumulative acres. 0 means every acre gets
#' the same depth of water.
#'
#' @param amount Quantity per unit (e.g. AF diverted).
#' @param weight Acres per unit.
#' @return Gini coefficient.
gini_per_acre <- function(amount, weight) {
  ok <- !is.na(amount) & !is.na(weight) & weight > 0
  o <- order(amount[ok] / weight[ok])
  a <- c(0, cumsum(weight[ok][o]) / sum(weight[ok]))
  w <- c(0, cumsum(amount[ok][o]) / sum(amount[ok]))
  1 - sum(diff(a) * (utils::head(w, -1) + utils::tail(w, -1)))
}

#' Group touching fields into blocks, a proxy for farm operations
#'
#' The field layer has no farm or owner ID (`FARM_UNIT` is empty and
#' `MASTER_ID` only tracks a field across years). Fields closer than
#' `gap_m` to each other are joined into one block.
#'
#' @param fields sf from `read_fields()` (EPSG 26913).
#' @param gap_m Gap in meters that still counts as touching.
#' @return Tibble: field_id, block_id.
field_blocks <- function(fields, gap_m = 10) {
  hit <- sf::st_is_within_distance(fields, fields, dist = gap_m)
  id <- seq_along(hit)
  repeat {
    new <- vapply(hit, \(i) min(id[i]), 1L)
    new <- new[new]
    if (identical(new, id)) break
    id <- new
  }
  tibble::tibble(field_id = fields$field_id, block_id = sprintf("B%03d", match(id, unique(id))))
}

#' Statewide OIT parcel composite query URL
oit_parcels_url <- paste0(
  "https://gis.colorado.gov/Public/rest/services/Address_and_Parcel/",
  "Colorado_Public_Parcels/MapServer/0/query"
)

#' Page through an envelope query on the OIT parcel composite
#'
#' Keeps requesting while the service sets `exceededTransferLimit`.
#'
#' @param bbox Numeric xmin, ymin, xmax, ymax in EPSG 4326.
#' @param out_fields Comma-separated field names.
#' @param geometry Return geometry (GeoJSON) or attributes only (JSON).
#' @param page Records per request (service cap 2000).
#' @return List of pages: sf (geometry) or tibbles (attributes).
oit_query_pages <- function(bbox, out_fields, geometry = TRUE, page = 2000) {
  get_page <- function(offset) {
    httr2::request(oit_parcels_url) |>
      httr2::req_url_query(
        where = "1=1", geometry = paste(bbox, collapse = ","), geometryType = "esriGeometryEnvelope",
        inSR = 4326, spatialRel = "esriSpatialRelIntersects", outFields = out_fields, outSR = 4326,
        returnGeometry = tolower(geometry), resultOffset = offset, resultRecordCount = page,
        orderByFields = "OBJECTID", f = if (geometry) "geojson" else "json"
      ) |>
      httr2::req_timeout(300) |>
      httr2::req_retry(
        max_tries = 5,
        is_transient = \(r) httr2::resp_status(r) %in% c(429, 500, 502, 503, 504)
      ) |>
      httr2::req_perform() |>
      httr2::resp_body_string()
  }
  out <- list()
  offset <- 0
  repeat {
    txt <- get_page(offset)
    j <- jsonlite::fromJSON(txt, simplifyVector = TRUE)
    more <- isTRUE(j$exceededTransferLimit) || isTRUE(j$properties$exceededTransferLimit)
    out[[length(out) + 1]] <- if (geometry) {
      sf::st_read(txt, quiet = TRUE)
    } else {
      tibble::as_tibble(j$features$attributes)
    }
    n <- nrow(out[[length(out)]])
    if (!more || n == 0) break
    offset <- offset + n
    Sys.sleep(0.3)
  }
  out
}

#' Statewide OIT parcels inside a bounding box, without owner fields
#'
#' Reads the Colorado Public Parcels composite (annual county submissions).
#' Owner name and address fields are deliberately not requested.
#'
#' @param bbox Numeric xmin, ymin, xmax, ymax in EPSG 4326.
#' @return sf of parcels: parcel_id, county, land_use, land_acres.
fetch_oit_parcels <- function(bbox) {
  oit_query_pages(bbox, "parcel_id,countyName,landUseDsc,landAcres", geometry = TRUE) |>
    dplyr::bind_rows() |>
    dplyr::transmute(
      parcel_id, county = countyName, land_use = landUseDsc, land_acres = as.numeric(landAcres)
    )
}

#' Overlay irrigated fields on tax parcels
#'
#' @param fields sf from `read_fields()` (EPSG 26913).
#' @param parcels sf from `fetch_oit_parcels()`.
#' @param min_acres Drop slivers smaller than this.
#' @return Tibble: field_id, parcel_id, county, land_use, land_acres, overlap_acres.
field_parcel_overlay <- function(fields, parcels, min_acres = 0.25) {
  parcels <- parcels |>
    sf::st_transform(26913) |>
    sf::st_make_valid() |>
    dplyr::filter(!sf::st_is_empty(geometry))
  sf::st_intersection(dplyr::select(fields, field_id), parcels) |>
    dplyr::mutate(overlap_acres = as.numeric(sf::st_area(geometry)) / 4046.873) |>
    sf::st_drop_geometry() |>
    tibble::as_tibble() |>
    dplyr::filter(overlap_acres >= min_acres)
}

#' Secret key for owner hashing
#'
#' Read from `OWNER_HASH_KEY` (set in `~/.Renviron`). The same key gives the
#' same owner IDs on every run, so names can be recovered by rerunning with
#' `reveal = TRUE`.
#'
#' @return The key as a string.
owner_hash_key <- function() {
  k <- Sys.getenv("OWNER_HASH_KEY")
  if (!nzchar(k)) {
    stop(
      "OWNER_HASH_KEY is not set. Add a line `OWNER_HASH_KEY=<64 hex characters>` to ~/.Renviron ",
      "(make one with `paste(openssl::rand_bytes(32), collapse = \"\")`), then restart R.",
      call. = FALSE
    )
  }
  k
}

#' Normalize an assessor owner name so one owner matches across parcels
#'
#' Upper case, `&` to AND, punctuation removed, and entity and trust
#' wording dropped (LLC, INC, TRUST, TRUSTEE, REVOCABLE, LIVING, ET AL,
#' JT TEN, a leading THE), so "SMITH JOHN REVOCABLE TRUST" and
#' "SMITH JOHN" become one owner.
#'
#' @param x Owner names.
#' @return Normalized names (NA when nothing is left).
normalize_owner <- function(x) {
  drop <- c("L L C", "LLC", "LLLP", "LLP", "LTD", "LP", "INC", "INCORPORATED", "CORPORATION", "CORP",
            "REVOCABLE", "IRREVOCABLE", "LIVING", "TRUSTEES", "TRUSTEE", "TRUST", "TRST", "TR",
            "ET AL", "ETAL", "ET UX", "JT TEN", "JTWROS", "C/O")
  y <- toupper(x) |>
    gsub(pattern = "&", replacement = " AND ", fixed = TRUE) |>
    gsub(pattern = "[^A-Z0-9/ ]", replacement = " ") |>
    gsub(pattern = paste0("\\b(", paste(drop, collapse = "|"), ")\\b"), replacement = " ") |>
    gsub(pattern = "^\\s*THE\\b", replacement = " ") |>
    gsub(pattern = "\\s+", replacement = " ") |>
    trimws() |>
    sub(pattern = "\\s+AND$", replacement = "")
  dplyr::na_if(y, "")
}

#' Owner strings that are placeholders, not names
#'
#' Eagle County submits "EAGLE COUNTY PROPERTY OWNER" for every parcel, so
#' those owners are withheld, not county land.
owner_placeholder_pattern <- "PROPERTY OWNER$|^OWNER$|CONFIDENTIAL|WITHHELD|UNKNOWN OWNER"

#' Keyed hash of a normalized owner name
#'
#' HMAC-SHA256 with `key`, shortened to 16 hex characters.
#'
#' @param x Normalized owner names.
#' @param key Secret from `owner_hash_key()`.
#' @return Owner IDs such as `"O3f9a..."` (NA for missing names).
hash_owner <- function(x, key = owner_hash_key()) {
  h <- as.character(openssl::sha256(dplyr::coalesce(x, ""), key = key))
  ifelse(is.na(x), NA_character_, paste0("O", substr(h, 1, 16)))
}

#' Owners of tax parcels, hashed
#'
#' Fetches `owner` from the OIT parcel composite, keeps the given parcels,
#' classes each owner from the raw name, then normalizes and hashes it.
#' Placeholder owners (`owner_placeholder_pattern`) are class "withheld"
#' with no ID.
#' Public entities and ditch companies keep a public label in
#' `owner_public`. Names are dropped unless `reveal = TRUE`, which returns
#' the normalized name in memory for a lookup; never cache a revealed
#' result.
#'
#' @param bbox Numeric xmin, ymin, xmax, ymax in EPSG 4326.
#' @param parcels Tibble with `parcel_id` and `county` to keep.
#' @param reveal Also return the normalized name (`owner_name`).
#' @param key Secret from `owner_hash_key()`.
#' @return Tibble: parcel_id, county, owner_id, owner_class, owner_public (and owner_name when revealed).
fetch_parcel_owners <- function(bbox, parcels, reveal = FALSE, key = owner_hash_key()) {
  x <- oit_query_pages(bbox, "parcel_id,countyName,owner", geometry = FALSE) |>
    dplyr::bind_rows() |>
    dplyr::transmute(parcel_id, county = countyName, owner) |>
    dplyr::semi_join(parcels, by = c("parcel_id", "county")) |>
    dplyr::distinct(parcel_id, county, .keep_all = TRUE) |>
    dplyr::mutate(
      withheld = grepl(owner_placeholder_pattern, toupper(dplyr::coalesce(owner, ""))),
      owner_name = ifelse(withheld, NA_character_, normalize_owner(owner)),
      owner_class = dplyr::case_when(
        withheld ~ "withheld",
        is.na(owner_name) ~ "missing",
        TRUE ~ classify_contact(owner)
      ),
      owner_public = public_name(owner, owner_class),
      owner_id = hash_owner(owner_name, key)
    ) |>
    dplyr::select(parcel_id, county, owner_id, owner_class, owner_public, owner_name)
  if (!reveal) x <- dplyr::select(x, -owner_name)
  x
}
