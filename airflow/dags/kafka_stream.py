import os
import re
import requests
import uuid
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import json
from uuid import UUID
import json
from kafka import KafkaProducer
import time
import logging

default_args = {
    'owner': 'ai_data_platform',
    'start_date': datetime(2023, 9, 3, 10, 00)
}



class UUIDEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, UUID):
            # if the obj is uuid, we simply return the value of uuid
            return obj.hex
        return json.JSONEncoder.default(self, obj)
    

def get_data():
    res = requests.get("https://randomuser.me/api/")
    res = res.json()
    res = res['results'][0]

    return res

def format_data(res):
    data = {}
    location = res['location']
    data['id'] = uuid.uuid4()
    data['first_name'] = res['name']['first']
    data['last_name'] = res['name']['last']
    data['gender'] = res['gender']
    data['address'] = f"{str(location['street']['number'])} {location['street']['name']}, " \
                      f"{location['city']}, {location['state']}, {location['country']}"
    data['post_code'] = location['postcode']
    data['email'] = res['email']
    data['username'] = res['login']['username']
    data['dob'] = res['dob']['date']
    data['registered_date'] = res['registered']['date']
    data['phone'] = res['phone']
    data['picture'] = res['picture']['medium']

    return data

def stream_data():
    producer = KafkaProducer(bootstrap_servers=['localhost:9092' if os.getenv("DEBUG", 'False') == 'True' else 'broker:29092'],
                             max_block_ms=5000)
    curr_time = time.time()

    while True:
        if time.time() > curr_time + 60: #1 minute
            break
        try:
            res = get_data()
            res = format_data(res)
            
            producer.send('users_created', json.dumps(res, cls=UUIDEncoder).encode('utf-8'))
            print(f'Sending data to kafka {res}')
        except Exception as e:
            logging.error(f'An error occured: {e}')
            continue

if os.getenv("DEBUG", 'False') == 'True':
    stream_data()
else:
    logging.info('Starting processing of DAG')
    with DAG('user_automation',
            default_args=default_args,
            schedule_interval='@daily',
            catchup=False) as dag:

        streaming_task = PythonOperator(
            task_id='stream_data_from_api',
            python_callable=stream_data
        )