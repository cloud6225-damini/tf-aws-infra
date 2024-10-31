# Generate a random UUID for bucket naming
resource "random_uuid" "bucket_uuid" {}

# Private S3 Bucket with encryption and random UUID
resource "aws_s3_bucket" "private_bucket" {
  bucket        = "damini-profile-${random_uuid.bucket_uuid.result}"
  acl           = "private"
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "${var.vpc_name}-private-s3-bucket"
  }
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

# Output the generated bucket name to use it in other parts of Terraform or scripts
output "s3_bucket_name" {
  value = aws_s3_bucket.private_bucket.bucket
}

