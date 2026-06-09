/* ============================================================
   Eurostat Household Energy Consumption — SQL Analysis
   Dataset : Eurostat (hh_energy_fuel.csv), 2013–2024
   Scope   : 30+ European countries, 10 fuel types
   Author  : [Your Name]
   Tools   : MySQL 8.0
   Topics  : Data cleaning, window functions, CTEs, unpivoting,
             STDDEV anomaly detection, CAGR, gaps-and-islands
   ============================================================ */

/* =========================================
   DATABASE SETUP
========================================= */

create database energy_households;
use energy_households;

/* =========================================
   DATA CLEANING — HEADER ROW REMOVAL
========================================= */

-- The raw import included the header row as a data row. Remove it.
delete from hh_energy_fuel
where freq = 'freq';

/* =========================================
   DATA CLEANING — WORKING TABLE
========================================= */

-- All modifications are made on a duplicate table to preserve the raw import.
create table hh_fuel_dupl like hh_energy_fuel;
insert into hh_fuel_dupl select * from hh_energy_fuel;

/* =========================================
   DATA CLEANING — COLUMN TYPE FIX
========================================= */

-- The 2013 column was imported as text instead of double. Fix the type.
alter table hh_fuel_dupl
modify column `2013` double;

/* =========================================
   DATA CLEANING — NULL HANDLING
========================================= */

-- Certain countries have empty strings ('') instead of NULL values.
-- These represent reporting gaps, not zero consumption. Convert them to NULL.
update hh_fuel_dupl
set
    `2013` = nullif(`2013`, ''),
    `2014` = nullif(`2014`, ''),
    `2015` = nullif(`2015`, ''),
    `2016` = nullif(`2016`, ''),
    `2017` = nullif(`2017`, ''),
    `2018` = nullif(`2018`, ''),
    `2019` = nullif(`2019`, ''),
    `2020` = nullif(`2020`, ''),
    `2021` = nullif(`2021`, ''),
    `2022` = nullif(`2022`, ''),
    `2023` = nullif(`2023`, ''),
    `2024` = nullif(`2024`, '');

/* =========================================
   DATA CLEANING — REDUNDANT COLUMNS
========================================= */

/*
The following columns hold the same value for every row and add no
analytical value:
  freq    : always "A" (Annual)
  nrg_bal : always "FC_OTH_HH_E" (Final Consumption, Households)
  unit    : always kilotonnes of oil equivalent (ktoe)
They are dropped to keep the working table lean.
*/
alter table hh_fuel_dupl
drop column freq,
drop column nrg_bal,
drop column unit;

/* =========================================
   DATA CLEANING — SCOPE FILTER
========================================= */

-- Remove the EU27_2020 aggregate row; analysis focuses on individual countries.
delete from hh_fuel_dupl
where geo = 'EU27_2020';

/* =========================================
   DATA CLEANING — SIEC CODE LABELS
========================================= */

/*
The siec column uses Eurostat classification codes.
They are replaced with readable labels for clarity.
Verified distinct codes before mapping (10 fuel types + Total).
*/
update hh_fuel_dupl
    set siec = case siec
        when 'G3000'               then 'natural gas'
        when 'E7000'               then 'electricity'
        when 'C0000X0350-0370'     then 'coal'
        when 'O4630'               then 'heating oil'
        when 'R5110-5150_W6000RI'  then 'renewables/biomass'
        when 'RA600'               then 'heat pumps'
        when 'RA410'               then 'solar thermal'
        when 'H8000'               then 'district heating'
        when 'O4669'               then 'other petroleum products'
        when 'O4671XR5220B'        then 'domestic heating oil'
        else siec
    end;

/* =========================================
   DATA TRANSFORMATION — UNPIVOT YEAR COLUMNS
========================================= */

/*
The source table stores one year per column (wide format).
A long-format table is created here for use in all window function
and time-series queries that follow.
Each row in hh_fuel_long represents one country + fuel + year observation.
*/
create table hh_fuel_long (
    geo    text,
    siec   text,
    `year` year,
    `value` double
);

insert into hh_fuel_long
    select geo, siec, 2013, `2013` from hh_fuel_dupl union all
    select geo, siec, 2014, `2014` from hh_fuel_dupl union all
    select geo, siec, 2015, `2015` from hh_fuel_dupl union all
    select geo, siec, 2016, `2016` from hh_fuel_dupl union all
    select geo, siec, 2017, `2017` from hh_fuel_dupl union all
    select geo, siec, 2018, `2018` from hh_fuel_dupl union all
    select geo, siec, 2019, `2019` from hh_fuel_dupl union all
    select geo, siec, 2020, `2020` from hh_fuel_dupl union all
    select geo, siec, 2021, `2021` from hh_fuel_dupl union all
    select geo, siec, 2022, `2022` from hh_fuel_dupl union all
    select geo, siec, 2023, `2023` from hh_fuel_dupl union all
    select geo, siec, 2024, `2024` from hh_fuel_dupl;
