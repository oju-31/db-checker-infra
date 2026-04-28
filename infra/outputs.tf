output "test_bucket_name" {
  value = aws_s3_bucket.test.bucket
}

output "test_bucket_arn" {
  value = aws_s3_bucket.test.arn
}
