/* ============================================================
   Eurostat Household Energy Consumption — SQL Analysis
   Dataset : Eurostat (hh_energy_fuel.csv), 2013–2024
   Scope   : 30+ European countries, 10 fuel types
   Author  : [Your Name]
   Tools   : MySQL 8.0
   Topics  : Window functions, CTEs, STDDEV anomaly detection,
             CAGR, gaps-and-islands, conditional aggregation
   ============================================================ */

use energy_households;

/* =========================================
   ANALYSIS 1 — BIGGEST SINGLE-YEAR DROP
   Per country and fuel type, find the year
   where consumption fell the most compared
   to the previous year.
========================================= */

with lag_val as (
    select
        geo,
        siec,
        `year`,
        `value`,
        lag(`value`) over (partition by geo, siec order by `year`) as previous_year_value
    from hh_fuel_long
),
rounded_lag_val as (
    select
        geo,
        siec,
        `year`,
        `value`,
        round(`value` - previous_year_value, 3) as diff
    from lag_val
),
biggest_drop as (
    select
        *,
        dense_rank() over (partition by geo, siec order by diff) as drnk
    from rounded_lag_val
    where diff is not null
      and siec != 'Total'
)
select
    geo,
    siec,
    `year`,
    diff as `biggest drop`
from biggest_drop
where drnk = 1
  and diff < 0
order by geo, `year`;

/*
Alternative approach — returns each year's delta without ranking,
useful if you want to inspect the full year-over-year series:

with with_diff as (
    select
        geo,
        siec,
        `year`,
        `value`,
        lag(`value`) over (partition by geo, siec order by `year`) as prev_value,
        `value` - lag(`value`) over (partition by geo, siec order by `year`) as diff
    from hh_fuel_long
)
select
    geo,
    siec,
    `year`,
    round(prev_value, 3) as prev_year_value,
    round(`value`, 3)    as current_value,
    round(diff, 3)       as `change`
from with_diff
where diff is not null
  and round(prev_value, 3) != 0
order by geo, siec;
*/

-- To return the top 10 sharpest drops overall, replace the final
-- ORDER BY / WHERE with:
--   order by `biggest drop`
--   limit 10;


/* =========================================
   ANALYSIS 2 — ROLLING RENEWABLES SHARE
   For each country, calculate renewables as
   a % of total energy per year, then show a
   cumulative average — a rolling "green
   progress" score from 2013 to 2024.
========================================= */

with helper_col as (
    select
        geo,
        `year`,
        sum(case when siec = 'renewables/biomass' then `value` end) as renewable_biomass,
        sum(case when siec = 'Total'              then `value` end) as total
    from hh_fuel_long
    where siec in ('Total', 'renewables/biomass')
    group by geo, `year`
),
perc_col as (
    select
        *,
        round((renewable_biomass / total) * 100, 3) as percentage
    from helper_col
    where total != 0
),
final_cte as (
    select
        *,
        avg(percentage) over (
            partition by geo
            order by `year`
            rows between unbounded preceding and current row
        ) as cumulative_per
    from perc_col
)
select
    geo,
    `year`,
    renewable_biomass,
    total,
    percentage,
    round(cumulative_per, 3) as green_progress
from final_cte
order by geo, `year`;

/*
Alternative approach — uses a self-join instead of conditional
aggregation to separate renewables from total:

with helper_col as (
    select
        a.geo,
        a.`year`,
        a.`value` as renewable_biomass,
        b.`value` as total
    from hh_fuel_long a
    join hh_fuel_long b
        on  a.geo    = b.geo
        and a.`year` = b.`year`
    where a.siec = 'renewables/biomass'
      and b.siec = 'Total'
),
perc_col as (
    select
        *,
        round((renewable_biomass / total) * 100, 3) as percentage
    from helper_col
    where total != 0
),
final_cte as (
    select
        *,
        avg(percentage) over (
            partition by geo
            order by `year`
            rows between unbounded preceding and current row
        ) as cumulative_per
    from perc_col
)
select
    geo,
    `year`,
    renewable_biomass,
    total,
    percentage,
    round(cumulative_per, 3) as green_progress
from final_cte
order by geo, `year`;
*/


/* =========================================
   ANALYSIS 3.1 — FUEL DOMINANCE SHIFT
   Find countries where the #1 ranked fuel
   changed between 2013 and 2024, and show
   what replaced it.
========================================= */

with ranking_cte as (
    select
        siec,
        geo,
        dense_rank() over (partition by geo order by `2013` desc) as ranking_2013,
        dense_rank() over (partition by geo order by `2024` desc) as ranking_2024
    from hh_fuel_dupl
    where siec != 'Total'
),
cte_2013 as (
    select siec, geo, ranking_2013
    from ranking_cte
    where ranking_2013 = 1
),
cte_2024 as (
    select siec, geo, ranking_2024
    from ranking_cte
    where ranking_2024 = 1
)
select
    a.geo,
    a.siec       as siec_2013,
    a.ranking_2013,
    b.siec       as siec_2024,
    b.ranking_2024
from cte_2013 a
join cte_2024 b
    on a.geo = b.geo
where a.siec != b.siec
order by geo;


/* =========================================
   ANALYSIS 3.2 — FULL RANK COMPARISON
   For each country, rank all fuel types by
   consumption in 2013 and again in 2024 to
   show the complete shift in rankings.
========================================= */

with rank_cte as (
    select
        siec,
        geo,
        `2013`,
        dense_rank() over (partition by geo order by `2013` desc) as ranking_2013,
        `2024`,
        dense_rank() over (partition by geo order by `2024` desc) as ranking_2024
    from hh_fuel_dupl
    where siec  != 'Total'
      and `2013` is not null
      and `2024` is not null
)
select
    a.geo,
    a.siec,
    a.ranking_2013,
    b.ranking_2024
from rank_cte a
join rank_cte b
    on  a.geo  = b.geo
    and a.siec = b.siec
order by geo, siec;


/* =========================================
   ANALYSIS 4 — LONGEST CONSECUTIVE DECLINE
   For each country + fuel type, find the
   longest streak of consecutive years where
   consumption decreased year-over-year.
   Uses a gaps-and-islands approach.
========================================= */

with lag_cte as (
    select
        siec,
        geo,
        lag(`year`)  over (partition by geo, siec order by `year`) as previous_year,
        lag(`value`) over (partition by geo, siec order by `year`) as previous_year_value,
        `year`,
        `value` as current_year_value
    from hh_fuel_long
),
null_filter as (
    select *
    from lag_cte
    where previous_year_value is not null
      and current_year_value  is not null
),
change_cte as (
    select
        *,
        round(current_year_value - previous_year_value, 3) as change_of_value
    from null_filter
),
decline_cte as (
    select
        *,
        case when change_of_value < 0 then 1 else 0 end as is_dropping
    from change_cte
),
row_num as (
    select
        *,
        row_number() over (partition by geo, siec                  order by `year`) as rn1,
        row_number() over (partition by geo, siec, is_dropping     order by `year`) as rn2
    from decline_cte
),
same_group_cte as (
    select
        *,
        rn1 - rn2 as same_group
    from row_num
    where is_dropping = 1
)
select
    geo,
    siec,
    max(streak) as longest_streak
from (
    select
        geo,
        siec,
        same_group,
        count(*) as streak
    from same_group_cte
    group by geo, siec, same_group
) as streaks
group by geo, siec
order by longest_streak desc;


/* =========================================
   ANALYSIS 5 — COVID ANOMALY DETECTION
   For each country and fuel type, flag 2020
   consumption values that deviate more than
   2 standard deviations from the country's
   own 2013–2019 baseline average.
========================================= */

with outliers_cte as (
    select
        geo,
        siec,
        round(avg(`value`) + 2 * stddev_samp(`value`), 5) as h_thres,
        round(avg(`value`) - 2 * stddev_samp(`value`), 5) as l_thres
    from hh_fuel_long
    where siec  != 'Total'
      and `year` between 2013 and 2019
    group by geo, siec
)
select
    a.geo,
    a.siec,
    b.`value`,
    a.l_thres,
    a.h_thres,
    case
        when b.`value` >= a.h_thres then 'high anomaly'
        when b.`value` <= a.l_thres then 'low anomaly'
    end as anomaly_type
from outliers_cte a
join hh_fuel_long b
    on  a.geo  = b.geo
    and a.siec = b.siec
where b.`year` = 2020
  and (b.`value` >= a.h_thres or b.`value` <= a.l_thres)
order by geo, siec;

/*
Alternative — separate queries for high and low anomalies,
useful when you want to filter or style each direction independently:

-- High anomalies only
with h_outlier_cte as (
    select
        geo,
        siec,
        round(avg(`value`) + 2 * stddev_samp(`value`), 5) as h_thres
    from hh_fuel_long
    where siec != 'Total' and `year` between 2013 and 2019
    group by geo, siec
)
select a.geo, a.siec, b.`value`, a.h_thres
from h_outlier_cte a
join hh_fuel_long b on a.geo = b.geo and a.siec = b.siec
where b.`year` = 2020 and b.`value` >= a.h_thres
order by geo, siec;

-- Low anomalies only
with l_outlier_cte as (
    select
        geo,
        siec,
        round(avg(`value`) - 2 * stddev_samp(`value`), 5) as l_thres
    from hh_fuel_long
    where siec != 'Total' and `year` between 2013 and 2019
    group by geo, siec
)
select a.geo, a.siec, b.`value`, a.l_thres
from l_outlier_cte a
join hh_fuel_long b on a.geo = b.geo and a.siec = b.siec
where b.`year` = 2020 and b.`value` <= a.l_thres
order by geo, siec;
*/


/* =========================================
   ANALYSIS 6 — FUEL MARKET SHARE PIVOT
   For each country and year, calculate every
   fuel type's share (%) of total household
   energy consumption.
========================================= */

with no_total_fuel as (
    select * from hh_fuel_long
    where siec != 'Total'
),
total_fuel as (
    select * from hh_fuel_long
    where siec    =  'Total'
      and `value` != 0
      and `value` is not null
),
join_cte as (
    select
        a.geo,
        a.siec,
        a.`year`,
        round((a.`value` / b.`value`) * 100, 4) as fuel_percentage
    from no_total_fuel a
    join total_fuel b
        on  a.geo    = b.geo
        and a.`year` = b.`year`
)
select
    geo,
    `year`,
    max(case when siec = 'coal'                     then fuel_percentage end) as coal,
    max(case when siec = 'district heating'         then fuel_percentage end) as district_heating,
    max(case when siec = 'domestic heating oil'     then fuel_percentage end) as domestic_heating_oil,
    max(case when siec = 'electricity'              then fuel_percentage end) as electricity,
    max(case when siec = 'heat pumps'               then fuel_percentage end) as heat_pumps,
    max(case when siec = 'heating oil'              then fuel_percentage end) as heating_oil,
    max(case when siec = 'natural gas'              then fuel_percentage end) as natural_gas,
    max(case when siec = 'other petroleum products' then fuel_percentage end) as other_petroleum_products,
    max(case when siec = 'renewables/biomass'       then fuel_percentage end) as renewables_biomass,
    max(case when siec = 'solar thermal'            then fuel_percentage end) as solar_thermal
from join_cte
group by geo, `year`;


/* =========================================
   ANALYSIS 7 — COUNTRY ENERGY PROFILE
   Cluster countries by their dominant fuel
   type in 2024: gas-heavy, electric-heavy,
   renewables-heavy, etc.
========================================= */

with max_value as (
    select
        geo,
        max(`value`) as max_value
    from hh_fuel_long
    where `year`   =  2024
      and `value`  is not null
      and siec     != 'Total'
    group by geo
),
max_value_fuel as (
    select
        a.geo,
        b.siec,
        a.max_value
    from max_value a
    join hh_fuel_long b
        on  a.geo       = b.geo
        and a.max_value = b.`value`
)
select
    geo,
    siec,
    max_value,
    case
        when siec = 'electricity'                                                    then 'electric-heavy'
        when siec = 'natural gas'                                                    then 'gas-heavy'
        when siec in ('renewables/biomass', 'solar thermal', 'heat pumps')           then 'renewables-heavy'
        when siec = 'coal'                                                           then 'solid-fuel-heavy'
        when siec = 'district heating'                                               then 'district-heating-heavy'
        else                                                                              'oil-heavy'
    end as dominance
from max_value_fuel
order by geo;


/* =========================================
   ANALYSIS 8 — CAGR (2013–2024)
   Calculate the compound annual growth rate
   for each country + fuel combination.
   Surface the top 5 fastest-growing and
   top 5 fastest-declining across all countries.
========================================= */

with cagr_cte as (
    select
        geo,
        siec,
        `2013`,
        `2024`,
        round(exp(ln(`2024` / `2013`) / 11) - 1, 4) as cagr
    from hh_fuel_dupl
    where siec   != 'Total'
      and `2013`  != 0
      and `2024`  != 0
      and `2013`  is not null
      and `2024`  is not null
),
change_cte as (
    select
        *,
        case when cagr > 0 then 0 else 1 end as is_dropping
    from cagr_cte
),
row_help as (
    select
        geo,
        siec,
        `2013`       as value_2013,
        `2024`       as value_2024,
        cagr,
        is_dropping,
        row_number() over (order by cagr)      as decline_rank,
        row_number() over (order by cagr desc) as growth_rank
    from change_cte
)
select
    geo,
    siec,
    value_2013,
    value_2024,
    cagr,
    case
        when decline_rank <= 5 then 'Fastest Declining'
        when growth_rank  <= 5 then 'Fastest Growing'
    end as category
from row_help
where decline_rank <= 5
   or growth_rank  <= 5
order by cagr;

/*
To find the top 5 fastest-growing and fastest-declining fuel types
for each individual country instead of globally, replace the row_help
CTE with:

row_help as (
    select
        geo,
        siec,
        cagr,
        is_dropping,
        row_number() over (partition by geo, is_dropping order by cagr) as counter
    from change_cte
)
select
    *,
    case
        when is_dropping = 1 and counter <= 5 then 'Fastest Declining'
        when is_dropping = 0 and counter <= 5 then 'Fastest Growing'
    end as category
from row_help
where counter <= 5
order by geo, cagr;
*/


/* =========================================
   ANALYSIS 9.1 — RENEWABLES CROSSOVER YEAR
   For each country, find the first year when
   renewables/biomass consumption exceeded
   natural gas. Countries that never crossed
   over appear as NULL.
========================================= */

with fuels_as_col as (
    select
        geo,
        `year`,
        max(case when siec = 'natural gas'        then `value` end) as natural_gas,
        max(case when siec = 'renewables/biomass' then `value` end) as renewables_biomass
    from hh_fuel_long
    group by geo, `year`
)
select
    geo,
    min(case when renewables_biomass > natural_gas then `year` end) as crossover_year
from fuels_as_col
where natural_gas       is not null
  and renewables_biomass is not null
group by geo
order by geo;


/* =========================================
   ANALYSIS 9.2 — CROSSOVER SUMMARY
   Count how many countries have crossed over
   from natural gas to renewables vs. how many
   have not.
========================================= */

with fuels_as_col as (
    select
        geo,
        `year`,
        max(case when siec = 'natural gas'        then `value` end) as natural_gas,
        max(case when siec = 'renewables/biomass' then `value` end) as renewables_biomass
    from hh_fuel_long
    group by geo, `year`
),
crossover_cte as (
    select
        geo,
        min(case when renewables_biomass > natural_gas then `year` end) as crossover_year
    from fuels_as_col
    where natural_gas       is not null
      and renewables_biomass is not null
    group by geo
)
select
    count(crossover_year)            as crossed_over,
    count(*) - count(crossover_year) as never_crossed
from crossover_cte;
