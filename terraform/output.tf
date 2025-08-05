output "lambda_function_name" {
  value = aws_lambda_function.lambda.function_name
}

output "s3_bucket_name" {
  value = data.aws_s3_bucket.data_bucket.bucket
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.brazil-league.repository_url
}

output "eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.lambda_trigger.name
}
