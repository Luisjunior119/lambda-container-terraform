import os
import json
import boto3
import pandas as pd
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

def lambda_handler(event, context):
    print("📌 Iniciando lambda_handler")

    # Carrega variável de ambiente com JSON das credenciais
    creds_json = os.environ.get("GOOGLE_CREDENTIALS_JSON")
    if not creds_json:
        return {'statusCode': 500, 'body': 'Variável GOOGLE_CREDENTIALS_JSON não definida.'}

    try:
        creds_dict = json.loads(creds_json)
        creds_dict["private_key"] = creds_dict["private_key"].replace("\\n", "\n")

        creds = Credentials.from_service_account_info(
            creds_dict,
            scopes=["https://www.googleapis.com/auth/spreadsheets.readonly"]
        )
        service = build("sheets", "v4", credentials=creds)
        print("🛂 Autenticado com sucesso no Google Sheets")

    except Exception as e:
        return {'statusCode': 500, 'body': f'Erro ao carregar credenciais: {e}'}

    # Carrega dados da planilha
    sheet_id = os.environ["SHEET_ID"]
    range_name = "sheet1!A1:K451"
    try:
        sheet = service.spreadsheets()
        result = sheet.values().get(spreadsheetId=sheet_id, range=range_name).execute()
        values = result.get("values", [])
        print("📥 Dados carregados do Google Sheets")
    except Exception as e:
        return {'statusCode': 500, 'body': f'Erro ao acessar planilha: {e}'}

    # Converte em DataFrame
    if not values:
        return {'statusCode': 400, 'body': 'Planilha vazia.'}

    df = pd.DataFrame(values[1:], columns=values[0])
    print("🔍 Colunas carregadas:", df.columns.tolist())

    

    # Tipagem e transformações
    df['season'] = df['season'].astype(int)
    df['place'] = df['place'].astype(int)
    df['team'] = df['team'].astype(str)
    df['points'] = df['points'].astype(int)
    df['played'] = df['played'].astype(int)
    df['won'] = df['won'].astype(int)
    df['draw'] = df['draw'].astype(int)
    df['loss'] = df['loss'].astype(int)
    df['goals'] = df['goals'].astype(int)
    df['goals_taken'] = df['goals_taken'].astype(int)
    df['goals_diff'] = df['goals_diff'].astype(int)

    # Salvar como Parquet
    output_path = "/tmp/etl_docker_terraform.parquet"
    df.to_parquet(output_path, engine='fastparquet', index=False)
    print(f"💾 Arquivo Parquet salvo em {output_path}")

    # Enviar para S3
    s3 = boto3.client("s3")
    bucket = os.environ["S3_BUCKET"]
    s3.upload_file(output_path, bucket, "etl_docker_terraform/tbl_refinada.parquet")
    print(f"✅ Enviado para o S3: s3://{bucket}/etl_docker_terraform/tbl_refinada.parquet")

    return {
        'statusCode': 200,
        'body': 'Base tratada, convertida para Parquet e enviada ao S3 com sucesso.'
    }



