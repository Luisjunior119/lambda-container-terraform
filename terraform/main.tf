provider "aws" {
  region = var.aws_region
}

# Referencia bucket S3 existente
data "aws_s3_bucket" "data_bucket" {
  bucket = var.s3_bucket
}

# Referencia repositório ECR existente
data "aws_ecr_repository" "brazil-league" {
  name = "brazil-league"
}

# Barramento customizado EventBridge
resource "aws_cloudwatch_event_bus" "custom_bus" {
  name = "brazil-league-bus"
}

# Role da Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Políticas para Lambda (ECR, S3, logs)
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ],
        Resource = data.aws_ecr_repository.brazil-league.arn
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = "${data.aws_s3_bucket.data_bucket.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# Função Lambda com imagem do ECR
resource "aws_lambda_function" "lambda" {
  function_name = "brazil-league_lambda"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.brazil-league.repository_url}:latest"

  environment {
    variables = {
      GOOGLE_CREDENTIALS_JSON = var.google_credentials_json
      SHEET_ID                = var.sheet_id
      S3_BUCKET               = var.s3_bucket
    }
  }

  memory_size = 512
  timeout     = 300
}

# EventBridge Rule que aciona a Lambda com evento customizado (no barramento customizado)
resource "aws_cloudwatch_event_rule" "lambda_trigger" {
  name           = "trigger-brazil-league"
  description    = "Aciona a função Lambda com evento custom"
  event_pattern  = jsonencode({
    "source": ["custom.lambda.trigger"]
  })
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
}

# Target para a Lambda (no barramento customizado)
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule           = aws_cloudwatch_event_rule.lambda_trigger.name
  target_id      = "lambda"
  arn            = aws_lambda_function.lambda.arn
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
}

# Permissão para EventBridge invocar Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge-${random_id.unique_id.hex}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_trigger.arn
}

# Gerador de ID único para o statement_id
resource "random_id" "unique_id" {
  byte_length = 8
}

# Não consegui, estudar mais soluções...
# EventBridge Rule para detectar upload no S3 (pode ser no default, se preferir)
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "s3-object-created-rule"
  description = "Detecta upload no caminho parquet da lambda"
  event_pattern = jsonencode({
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
      "bucket": {
        "name": [var.s3_bucket]
      },
      "object": {
        "key": [{
          "prefix": "etl_docker_terraform/"
        }]
      }
    }
  })
}

# Não consegui, estudar mais soluções...
# Step Function Definition (simples)
data "aws_iam_policy_document" "step_function_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "step_function_role" {
  name               = "step-function-execution-role"
  assume_role_policy = data.aws_iam_policy_document.step_function_assume_role.json
}

resource "aws_iam_role_policy" "step_function_glue_policy" {
  name = "step-fn-glue"
  role = aws_iam_role.step_function_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["glue:StartJobRun"],
        Resource = var.glue_job_arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "trigger_glue" {
  name     = "step-trigger-glue"
  role_arn = aws_iam_role.step_function_role.arn
  definition = jsonencode({
    Comment = "Step que aciona Glue Job",
    StartAt = "StartGlue",
    States = {
      StartGlue = {
        Type = "Task",
        Resource = "arn:aws:states:::glue:startJobRun.sync",
        Parameters = {
          JobName = var.glue_job_name
        },
        End = true
      }
    }
  })
}

# Não consegui, estudar mais soluções...
# EventBridge Target -> Step Function
resource "aws_cloudwatch_event_target" "trigger_step_fn" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "step-fn"
  arn       = aws_sfn_state_machine.trigger_glue.arn
  role_arn  = aws_iam_role.step_function_role.arn
}

resource "aws_iam_role_policy" "glue_job_permissions" {
  name = "lambda-glue-permission"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "glue:StartJobRun"
        ],
        Resource = var.glue_job_arn
      }
    ]
  })
}