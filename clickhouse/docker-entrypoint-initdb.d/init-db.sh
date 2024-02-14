#!/bin/bash
set -e

clickhouse client -n <<-EOSQL

    CREATE DATABASE IF NOT EXISTS stage;
    CREATE DATABASE IF NOT EXISTS dwh;
    CREATE DATABASE IF NOT EXISTS marts;

    drop table if exists stage.mv_null_fact_game;
    drop table if exists stage.kafka_fact_game;
    drop table if exists stage.null_fact_game;

    drop table if exists dwh.mv_fact_game;
    drop table if exists dwh._fact_game;

    drop table if exists marts.mv_daily_fact_game;
    drop table if exists marts._daily_fact_game;
    drop table if exists marts.daily_fact_game;

    DROP TABLE IF EXISTS marts.mv_redis_daily_fact_game;
    DROP TABLE IF EXISTS marts.redis_daily_fact_game;
    
    -- stage
    CREATE TABLE IF NOT EXISTS stage.kafka_fact_game
    (
        customer_id       Int32,
        activity_datetime String,
        game_activity     String,
        game_id           Int32,
        game_type LowCardinality(String),
        bet_amount        Decimal(18, 4),
        win_amount        Decimal(18, 4),
        bonus_amount      Decimal(18, 4)
    )
        ENGINE = Kafka SETTINGS kafka_broker_list = 'broker:29092', kafka_topic_list = 'game_v1', kafka_group_name = 'ch_game_v1', kafka_format = 'JSONEachRow', kafka_row_delimiter = '\n', kafka_num_consumers = 1, kafka_skip_broken_messages = 1;


    CREATE TABLE IF NOT EXISTS stage.null_fact_game
    (
        customer_id       Int32,
        activity_datetime String,
        game_activity     String,
        game_id           Int32,
        game_type LowCardinality(String),
        bet_amount        Decimal(18, 4),
        win_amount        Decimal(18, 4),
        bonus_amount      Decimal(18, 4)
    ) ENGINE = Null();


    CREATE MATERIALIZED VIEW IF NOT EXISTS stage.mv_null_fact_game TO stage.null_fact_game AS
    SELECT customer_id, activity_datetime, game_activity, game_id, game_type, bet_amount, win_amount, bonus_amount
        FROM stage.kafka_fact_game;

    -- dwh
    CREATE TABLE IF NOT EXISTS dwh._fact_game
    (
        customer_id       Int32,
        activity_datetime DateTime,
        game_activity     String,
        game_id           Int32,
        game_type LowCardinality(String),
        bet_amount        Decimal(18, 4),
        win_amount        Decimal(18, 4),
        bonus_amount      Decimal(18, 4)
    ) ENGINE = MergeTree() PARTITION BY toYYYYMM(activity_datetime) ORDER BY (toYYYYMMDD(activity_datetime), customer_id) SETTINGS index_granularity = 8192;


    CREATE MATERIALIZED VIEW IF NOT EXISTS dwh.mv_fact_game TO dwh._fact_game AS
    SELECT
        customer_id
    , parseDateTimeBestEffortOrZero(nfg.activity_datetime) AS activity_datetime
    , game_activity
    , game_id
    , game_type
    , bet_amount
    , win_amount
    , bonus_amount
        FROM
            stage.null_fact_game AS nfg
        GROUP BY customer_id, nfg.activity_datetime, game_activity, game_id, game_type, bet_amount, win_amount, bonus_amount;

    -- marts
    CREATE TABLE IF NOT EXISTS marts._daily_fact_game
    (
        customer_id   Int32,
        activity_date Date,
        game_id       Int32,
        game_type LowCardinality(String),
        bet_amount    Decimal(18, 4),
        win_amount    Decimal(18, 4),
        bonus_amount  Decimal(18, 4)
    ) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(activity_date) ORDER BY (customer_id, activity_date, game_id, game_type) SETTINGS index_granularity = 8192;


    CREATE MATERIALIZED VIEW IF NOT EXISTS marts.mv_daily_fact_game TO marts._daily_fact_game AS
    SELECT
        customer_id
    , toDate(activity_datetime) AS activity_date
    , game_id
    , game_type
    , sum(bet_amount)           as bet_amount
    , sum(win_amount)           as win_amount
    , sum(bonus_amount)         as bonus_amount
        FROM
            dwh._fact_game AS fg
        GROUP BY customer_id, activity_date, game_id, game_type;


    CREATE VIEW IF NOT EXISTS marts.daily_fact_game AS
    SELECT
        customer_id
    , activity_date
    , game_id
    , game_type
    , sum(bet_amount)   as bet_amount
    , sum(win_amount)   as win_amount
    , sum(bonus_amount) as bonus_amount
        FROM
            marts._daily_fact_game
        GROUP BY customer_id, activity_date, game_id, game_type;

    CREATE TABLE if not exists marts.redis_daily_fact_game
    (
        key        String,
        customer_id  Int32,
        game_type LowCardinality(String),
        game_count   Decimal(18, 4),
        bet_amount   Decimal(18, 4),
        win_amount   Decimal(18, 4),
        bonus_amount Decimal(18, 4)
    ) ENGINE = Redis('redis:6379') PRIMARY KEY (key);

    CREATE MATERIALIZED VIEW IF NOT EXISTS marts.mv_redis_daily_fact_game TO marts.redis_table AS
    SELECT
        concat(customer_id, ':', game_type) as key
    , customer_id
    , game_type
    , count(game_id)                      as game_count
    , sum(bet_amount)                     as bet_amount
    , sum(win_amount)                     as win_amount
    , sum(bonus_amount)                   as bonus_amount
        FROM
            marts._daily_fact_game
        group by customer_id, game_type;
    
EOSQL