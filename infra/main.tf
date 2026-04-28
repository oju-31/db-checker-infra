locals {
  tags = merge(var.COMMON_TAGS, {
    ResourceType = "STORAGE"
  })
}

resource "aws_s3_bucket" "test" {
  bucket_prefix = "${var.RESOURCE_PREFIX}-test-"
  force_destroy = var.ENV != "prod"

  tags = local.tags
}

resource "aws_s3_bucket_ownership_controls" "test" {
  bucket = aws_s3_bucket.test.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "test" {
  bucket = aws_s3_bucket.test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
