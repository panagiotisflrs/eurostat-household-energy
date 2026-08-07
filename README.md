# Eurostat Household Energy Consumption — SQL Analysis

Analysis of household energy consumption across 30+ European countries from 2013 to 2024, using data sourced from [Eurostat](https://ec.europa.eu/eurostat).

---

## Dataset

| Property | Detail |
|---|---|
| Source | [Eurostat — Final Consumption, Households (FC_OTH_HH_E)](https://ec.europa.eu/eurostat) |
| File | `hh_energy_fuel.csv` |
| Period | 2013 – 2024 (annual) |
| Countries | 30+ European countries (ISO codes) |
| Fuel types | Natural gas, electricity, coal, heating oil, renewables/biomass, heat pumps, solar thermal, district heating, domestic heating oil, other petroleum products |
| Unit | Kilotonnes of oil equivalent (ktoe) |

---

## Files

| File | Description |
|---|---|
| `01_setup_and_cleaning.sql` | Database creation, data cleaning, column type fixes, NULL handling, SIEC code relabelling, and wide-to-long unpivoting |
| `02_analysis.sql` | 9 analytical challenges covering time-series analysis, anomaly detection, ranking, clustering, and growth rates |

> Run `01_setup_and_cleaning.sql` first. All queries in `02_analysis.sql` depend on the tables it creates.

---

## Analytical Questions

| # | Question | Techniques |
|---|---|---|
| 1 | Biggest single-year consumption drop per country and fuel type | `LAG()`, `DENSE_RANK()` |
| 2 | Rolling renewables share — cumulative "green progress" score per country | Conditional aggregation, `AVG()` with sliding window frame |
| 3.1 | Countries where the #1 ranked fuel changed between 2013 and 2024 | `DENSE_RANK()`, self-join |
| 3.2 | Full fuel ranking comparison across all countries, 2013 vs 2024 | `DENSE_RANK()`, self-join |
| 4 | Longest consecutive decline streak per country and fuel type | Gaps-and-islands, `ROW_NUMBER()` |
| 5 | COVID anomaly detection — 2020 values deviating >2 std dev from 2013–2019 baseline | `STDDEV_SAMP()`, threshold join |
| 6 | Fuel market share pivot — each fuel type as % of total energy per country per year | Conditional aggregation pivot |
| 7 | Country clustering by dominant fuel type in 2024 | `CASE` classification |
| 8 | CAGR (2013–2024) — top 5 fastest-growing and fastest-declining fuel combinations | `EXP()`, `LN()`, `ROW_NUMBER()` |
| 9.1 | Renewables crossover year — first year renewables exceeded natural gas per country | Conditional `MIN()` |
| 9.2 | Summary count: how many countries have crossed over vs. have not | Aggregation on CTE result |

---

## SQL Techniques Used

- Window functions: `LAG()`, `DENSE_RANK()`, `ROW_NUMBER()`, `AVG()` with custom frame (`ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`)
- Multi-step CTEs and CTE chaining
- Wide-to-long unpivoting via `UNION ALL`
- Conditional aggregation with `CASE WHEN` inside `MAX()` / `SUM()`
- Anomaly detection using `STDDEV_SAMP()`
- Compound Annual Growth Rate via `EXP(LN(end/start) / n)`
- Gaps-and-islands streak detection using dual `ROW_NUMBER()` differencing
- Self-joins for comparative ranking across time periods

---

## Tools

- MySQL

---

## Related Projects

SQL analysis of the same dataset:
[eu-household-energy-PowerBI](https://github.com/panagiotisflrs/eurostat-household-energy-PowerBi.git)
