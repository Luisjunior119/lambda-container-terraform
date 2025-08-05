variable "aws_region" {
  description = "A região onde os recursos serão criados"
  default     = "us-east-2"
}

variable "google_credentials_json" {
  description = "Credenciais do Google para a API Sheets"
  type        = string
}

variable "sheet_id" {
  description = "ID da planilha no Google Sheets"
  type        = string
}

variable "s3_bucket" {
  description = "Nome do bucket S3 existente"
  type        = string
}
variable "glue_job_arn" {
  description = "ARN do Glue Job que será acionado"
  type        = string
}

variable "glue_job_name" {
  description = "Nome do Glue Job"
  type        = string
}

