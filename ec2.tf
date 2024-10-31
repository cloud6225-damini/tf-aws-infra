# IAM Role for EC2 with permissions for S3 and CloudWatch access
resource "aws_iam_role" "ec2_role" {
  name               = "${var.vpc_name}-ec2-role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2 to access S3 bucket, CloudWatch logs, metrics, and EC2 tags
resource "aws_iam_policy" "ec2_s3_cloudwatch_policy" {
  name = "${var.vpc_name}-ec2-s3-cloudwatch-policy"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"  # Allow deletion to ensure bucket can be emptied
        ],
        "Resource": [
          "${aws_s3_bucket.private_bucket.arn}",
          "${aws_s3_bucket.private_bucket.arn}/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "cloudwatch:PutMetricData",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeTags"  # Allows CloudWatch Agent to retrieve EC2 tags for the instance
        ],
        "Resource": "*"
      }
    ]
  })
}

# Attach the policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_s3_cloudwatch_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_cloudwatch_policy.arn
}

# IAM Instance Profile for EC2 with CloudWatch Agent Role
resource "aws_iam_instance_profile" "cloudwatch_agent_instance_profile" {
  name = "${var.vpc_name}-cloudwatch-agent-instance-profile"
  role = aws_iam_role.ec2_role.name
}
