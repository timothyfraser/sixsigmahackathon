---
name: plumber-react-scaffold
description: Scaffold an R plumber backend with a React front end for a hackathon project - project shape, the four-script contract, roxygen-style route annotations, CORS filters, and separating analysis code from the API layer. Use when a team picks R for a REST API or a dashboard-style web app.
---

# plumber + React scaffold

Start from [`demos/plumber/`](../../../demos/plumber/) and
[`demos/reactfront/`](../../../demos/reactfront/). Copy them into your own repo
rather than editing them in place.

## Shape

```
yourproject/
  api/
    R/stats.R          <- your statistics. plain functions. no plumber.
    tests/test_stats.R <- verification against known cases. write this early.
    plumber.R          <- routes. thin. sources R/stats.R.
    testme.R manifestme.R deployme.R README.md
  web/
    src/               <- React app (Vite)
    testme.sh manifestme.sh deployme.sh README.md
```

**`R/stats.R` must not call plumber.** Keeping the statistics in ordinary
functions is what lets you check them in a console in ten seconds. See the
`stats-first-steering` skill.

## Routes

plumber uses roxygen-style `#*` comments above each function:

```r
source("R/stats.R")

#* @apiTitle Quality Control API

#* Control limits for an X-bar and R chart
#* @param subgroup_size Subgroup size n
#* @post /spc/xbar
function(req, subgroup_size = 5) {
  xbar_r_limits(req$body$values, as.numeric(subgroup_size))
}
```

plumber serves interactive Swagger docs at `/__docs__/`. That page is a demo
asset — if time runs short, it *is* your front end.

## CORS

A React front end on another origin needs a filter:

```r
#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$setHeader("Access-Control-Allow-Methods", "*")
    res$setHeader("Access-Control-Allow-Headers", "*")
    res$status <- 200
    return(list())
  }
  plumber::forward()
}
```

## Front end

Vite + React (see the `fastapi-react-scaffold` skill — the front end is
identical, only the base URL differs). Keep the API base URL in one file so the
localhost-to-Connect switch is a one-line edit.

## Dependencies

plumber deploys fail most often on unavailable packages. Keep the package list
short and mainstream, and regenerate `manifest.json` every time you add one.
`rsconnect::writeManifest()` scans your code for `library()` calls — if you load
a package dynamically, it will not be detected and the deploy will 500.

## Deploy

API and front end are two separate pieces of content on Connect. Deploy the API
first, wire its URL into the front end, rebuild, deploy the front end. See the
`connect-publish` skill.

## If you would rather use Shiny

[`demos/shinyapp/`](../../../demos/shinyapp/) is a working starter and is a
perfectly good choice — one deployable artifact instead of two, no CORS, no npm.
React buys you a nicer-looking front end; Shiny buys you two hours. Pick
deliberately.
