# IAM Role for EC2 with permissions for S3, CloudWatch, Secrets Manager, and KMS
resource "aws_iam_role" "ec2_role" {
  name = "${var.vpc_name}-ec2-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2 to access S3 bucket, CloudWatch logs, metrics, EC2 tags, and Secrets Manager
resource "aws_iam_policy" "ec2_s3_cloudwatch_secrets_policy" {
  name = "${var.vpc_name}-ec2-s3-cloudwatch-secrets-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.private_bucket.arn}",
          "${aws_s3_bucket.private_bucket.arn}/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "cloudwatch:PutMetricData",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeTags"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource" : [
          "${aws_secretsmanager_secret.db_password.arn}",
          "${aws_secretsmanager_secret.email_service.arn}"
        ]
      }
    ]
  })
}

# IAM Policy for KMS Decryption
resource "aws_iam_policy" "ec2_kms_policy" {
  name = "${var.vpc_name}-ec2-kms-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt"
        ],
        "Resource" : [
          "${aws_kms_key.secrets_manager_key.arn}" # Replace <kms_key_id> with your actual KMS key ID
        ]
      }
    ]
  })
}

# Attach the combined S3, CloudWatch, and Secrets Manager policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_s3_cloudwatch_secrets_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_cloudwatch_secrets_policy.arn
}

# Attach the KMS policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_kms_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_kms_policy.arn
}

# IAM Instance Profile for EC2 with the updated role
resource "aws_iam_instance_profile" "cloudwatch_agent_instance_profile" {
  name = "${var.vpc_name}-cloudwatch-agent-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "random_password" "rds_password" {
  length           = 16
  special          = true
  override_special = "!#$%&()*+-.:;<=>?[]^_{|}~" # Exclude problematic characters
}
