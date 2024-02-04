import os
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

from kafka import KafkaProducer
import time
import logging
import json
import numpy as np
import random




default_args = {
    'owner': 'ai_data_platform',
    'start_date': datetime(2023, 9, 3, 10, 00)
}

map_game_type = {
    0 : 'slots',
    1 : 'live_casino',
    2 : 'poker',
    3 : 'bingo',
    4 : 'roulette',
    5 : 'black_jack'
}


run_duration = 60*3

def get_casino_data():
    dt = datetime.now() - timedelta(days=random.randint(0,15))
    is_bonus = random.uniform(0,1) < 0.2
    is_win = random.uniform(0,1) < 0.15
    
    
    customer_id = random.randint(0,10000)
    activity_datetime  = dt.strftime('%Y-%m-%d %H:%M:%S')
    game_activity = dt.strftime('%Y%m%d%H%M%S%f')
    game_id = random.randint(0,1000)
    game_type = map_game_type[ game_id%6]
    bet_amount = np.round( np.abs(np.random.laplace(0, 20, 1)[0]), 4)
    win_amount = np.round(bet_amount * (np.abs(np.random.laplace(1, 5,1)[0]) +1), 4) if is_win else 0
    bonus_cost_amount = win_amount if is_bonus and is_win else 0

    
    
    casino_data = {
        'customer_id' : customer_id,
        'activity_datetime' : activity_datetime,
        'game_activity' : game_activity,
        'game_id' : game_id,
        'game_type': game_type,
        'bet_amount' : bet_amount,
        'win_amount' : win_amount,
        'bonus_amount' : bonus_cost_amount
    }
    
    return casino_data

    


def stream_data():
    producer = KafkaProducer(bootstrap_servers=['localhost:9092' if os.getenv("DEBUG", 'False') == 'True' else 'broker:29092'],
                             max_block_ms=5000)
    curr_time = time.time()

    while True:
        if time.time() > curr_time + run_duration:
            break
        res = get_casino_data()
            
        logging.info(f'Sending to kafka {res}')
        producer.send('game_v1', json.dumps(res).encode('utf-8'))
        time.sleep(0.1)

if os.getenv("DEBUG", 'False') == 'True':
    stream_data()
else:
    logging.info('Starting processing of DAG')
    with DAG('mock_data',
            default_args=default_args,
            schedule_interval='*/5 * * * *',
            catchup=False) as dag:

        streaming_task = PythonOperator(
            task_id='generate_casino_data',
            python_callable=stream_data
        )