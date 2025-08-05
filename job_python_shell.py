import boto3
import pandas as pd
import pyarrow.parquet as pq
import time
from io import BytesIO
import os

# Definir os detalhes da tabela e do banco de dados
database_name = "default"
table_name = "glue_shell"
s3_input_path = "s3://databets-project/etl_docker_terraform/"  # Caminho para o diretório com os dados de entrada
s3_output_path = "s3://databets-project/glue_shell/output_data/"  # Caminho de saída onde os dados processados serão armazenados
athena_results_bucket = "s3://databets-project/athena-query-results/"  # Bucket para armazenar os resultados das consultas

# Criar o cliente do boto3 para acessar o Athena e o S3
athena_client = boto3.client('athena', region_name='us-east-2')  # Substitua pela sua região AWS
s3_client = boto3.client('s3')

# Função para ler o arquivo Parquet do S3 e retornar um DataFrame do Pandas
def read_parquet_from_s3(s3_path):
    bucket_name = s3_path.split('/')[2]
    object_key = '/'.join(s3_path.split('/')[3:])
    
    s3_object = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    parquet_data = s3_object['Body'].read()
    
    # Usando pyarrow para ler o arquivo Parquet
    table = pq.read_table(source=BytesIO(parquet_data))
    
    # Convertendo a tabela para um DataFrame do Pandas
    df = table.to_pandas()
    return df

# Função para gravar os dados no S3 (gerando o arquivo Parquet no diretório de saída)
def write_data_to_s3(df, s3_output_path):
    # Definindo o caminho completo para onde os dados serão gravados
    output_path = s3_output_path + "output_data.parquet"
    
    # Gravando os dados Parquet corretamente, usando pyarrow
    df.to_parquet(output_path, engine="pyarrow", compression="snappy")
    print(f"Dados gravados em {output_path}")

# Função para criar a tabela no Athena (sem particionamento)
def create_table_in_athena():
    create_table_sql = f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.{table_name} (
        place int,
        team string,
        points int,
        played int,
        won int,
        draw int,
        loss int,
        goals int,
        goals_taken int,
        goals_diff int
    )
    STORED AS PARQUET
    LOCATION '{s3_output_path}'  -- Caminho para o diretório onde os arquivos Parquet processados estão localizados
    TBLPROPERTIES ('has_encrypted_data'='false')
    """
    query_response = athena_client.start_query_execution(
        QueryString=create_table_sql,
        QueryExecutionContext={'Database': database_name},
        ResultConfiguration={'OutputLocation': athena_results_bucket}
    )
    return query_response

# Função para verificar o status da execução da consulta
def check_query_status(query_execution_id):
    while True:
        status = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        state = status['QueryExecution']['Status']['State']
        if state in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
            print(f"Query state: {state}")
            if state == 'SUCCEEDED':
                print("Athena table created successfully.")
            else:
                print(f"Table creation failed with state: {state}")
            break
        time.sleep(5)

# Carregar os dados do Parquet
df = read_parquet_from_s3(s3_input_path + "tbl_refinada.parquet")

# Gravar os dados sem particionamento no diretório de saída
write_data_to_s3(df, s3_output_path)

# Executar a criação da tabela no Athena
query_response = create_table_in_athena()
query_execution_id = query_response['QueryExecutionId']
check_query_status(query_execution_id)
