# Generate a random UUID for bucket naming
resource "random_uuid" "bucket_uuid" {}

# Create a KMS Key for S3 Bucket Encryption
resource "aws_kms_key" "s3_kms_key" {
  description              = "KMS Key for encrypting S3 bucket"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true

  tags = {
    Name = "S3-KMS-Key"
  }
}

# Define the Alias for S3 KMS Key
resource "aws_kms_alias" "s3_kms_alias" {
  name          = "alias/s3-bucket-key"
  target_key_id = aws_kms_key.s3_kms_key.id
}

# Private S3 Bucket with Random UUID
resource "aws_s3_bucket" "private_bucket" {
  bucket        = "damini-profile-${random_uuid.bucket_uuid.result}"
  acl           = "private"
  force_destroy = true

  tags = {
    Name = "${var.vpc_name}-private-s3-bucket"
  }
}

# Add Server-Side Encryption Configuration for S3 Bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "default_encryption" {
  bucket = aws_s3_bucket.private_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_alias.s3_kms_alias.arn
    }
  }
  depends_on = [aws_s3_bucket.private_bucket]
}

# Lifecycle configuration for the S3 bucket
resource "aws_s3_bucket_lifecycle_configuration" "private_bucket_lifecycle" {
  bucket = aws_s3_bucket.private_bucket.id

  rule {
    id     = "TransitionToIA"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Output the generated bucket name and KMS key ARN
output "s3_bucket_name" {
  value = aws_s3_bucket.private_bucket.bucket
}

output "s3_kms_key_arn" {
  value = aws_kms_key.s3_kms_key.arn
}


# Output the bucket encryption details
output "bucket_encryption" {
  value = aws_s3_bucket_server_side_encryption_configuration.default_encryption.rule
}
