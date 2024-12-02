# Fetch availability zones dynamically for the chosen region
data "aws_availability_zones" "available" {
  state = "available"
}

# KMS Keys for encryption
resource "aws_kms_key" "ec2_key" {
  description             = "KMS Key for EC2"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags = {
    Name = "${var.vpc_name}-ec2-kms-key"
  }
}

resource "aws_kms_key" "rds_key" {
  description             = "KMS Key for RDS"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags = {
    Name = "${var.vpc_name}-rds-kms-key"
  }
}

resource "aws_kms_key" "secrets_manager_key" {
  description             = "KMS Key for Secrets Manager"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags = {
    Name = "${var.vpc_name}-secrets-manager-kms-key"
  }
}


# Secrets Manager for DB Credentials
resource "aws_secretsmanager_secret" "db_password" {
  name       = "data"
  kms_key_id = aws_kms_key.secrets_manager_key.id
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "csye6225"
    password = random_password.rds_password.result
  })
}


# Secrets Manager for Email Credentials
resource "aws_secretsmanager_secret" "email_service" {
  name       = "email_lambda"
  kms_key_id = aws_kms_key.secrets_manager_key.id
}

resource "aws_secretsmanager_secret_version" "email_service_version" {
  secret_id = aws_secretsmanager_secret.email_service.id
  secret_string = jsonencode({
    SENDGRID_API_KEY = var.sendgrid_api_key
  })
}

# VPC Resource
resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = min(3, length(data.aws_availability_zones.available.names))
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.vpc_name}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = min(3, length(data.aws_availability_zones.available.names))
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.vpc_name}-private-subnet-${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Route for Public Subnets
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_association" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Load Balancer Security Group
resource "aws_security_group" "lb_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "${var.vpc_name}-load-balancer-sg"

  ingress {
    description      = "Allow HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.vpc_name}-lb-sg"
  }
}

# Application Security Group - updated for restricted access
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "${var.vpc_name}-app-secgroup"

  ingress {
    description     = "Allow HTTP from Load Balancer"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  # ingress {
  #   description      = "Allow SSH"
  #   from_port        = 22
  #   to_port          = 22
  #   protocol         = "tcp"
  #   cidr_blocks      = ["0.0.0.0/0"]
  #   ipv6_cidr_blocks = ["::/0"]
  # }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.vpc_name}-app-sg"
  }
}

# MySQL Database Security Group
resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "${var.vpc_name}-db-sg"

  ingress {
    description     = "Allow MySQL traffic from the web server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_name}-db-sg"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "private_subnet_group" {
  name       = "${var.vpc_name}-rds-private-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.vpc_name}-rds-private-subnet-group"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "mysql_parameter_group" {
  name   = "csye6225-mysql-pg"
  family = "mysql8.0"

  tags = {
    Name = "${var.vpc_name}-mysql-pg"
  }
}

# MySQL RDS Instance
resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.private_subnet_group.name
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "csye6225"
  username               = "csye6225"
  password               = random_password.rds_password.result
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn
  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "${var.vpc_name}-mysql-rds"
  }
}


data "aws_caller_identity" "current" {}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "web_app_lt" {
  name          = "csye6225_asg"
  image_id      = var.custom_ami
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.cloudwatch_agent_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  #  block_device_mappings { //ec2 encryption
  #   device_name = "/dev/xvda" # Root volume
  #   ebs {
  #     volume_size           = 20 # Volume size in GiB
  #     volume_type           = "gp2"
  #     encrypted             = true
  #     kms_key_id            = aws_kms_key.ec2_key.arn # Use the EC2 encryption key
  #     delete_on_termination = true
  #   }
  # }

  user_data = base64encode(<<EOF
#!/bin/bash

# Redirect output to a log file for debugging
exec > /var/log/user-data.log 2>&1
set -x

# Update and install necessary packages
sudo apt-get update
sudo apt-get install -y jq wget unzip build-essential curl

# Install AWS CLI from Amazon's official source
echo "Installing AWS CLI..."
wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install Node.js and npm
echo "Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version
npm --version

# Define variables
AWS_REGION="ca-central-1"
DB_SECRET_ID="data"
EMAIL_SECRET_ID="email_lambda"

# Retrieve database credentials from Secrets Manager
echo "Retrieving database credentials..."
DB_SECRET=$(aws secretsmanager get-secret-value --secret-id $DB_SECRET_ID --query SecretString --output text --region $AWS_REGION)
if [ $? -ne 0 ]; then
    echo "Failed to retrieve database secret from Secrets Manager."
    exit 1
fi

DB_USERNAME=$(echo $DB_SECRET | jq -r '.username')
DB_PASSWORD=$(echo $DB_SECRET | jq -r '.password')

# Check if DB_USERNAME and DB_PASSWORD are populated
if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
    echo "Database username or password is missing!"
    exit 1
fi

# Retrieve email credentials from Secrets Manager
echo "Retrieving email service credentials..."
EMAIL_SECRET=$(aws secretsmanager get-secret-value --secret-id $EMAIL_SECRET_ID --query SecretString --output text --region $AWS_REGION)
if [ $? -ne 0 ]; then
    echo "Failed to retrieve email service secret from Secrets Manager."
    exit 1
fi

SENDGRID_API_KEY=$(echo $EMAIL_SECRET | jq -r '.SENDGRID_API_KEY')

# Check if SENDGRID_API_KEY is populated
if [ -z "$SENDGRID_API_KEY" ]; then
    echo "SendGrid API Key is missing!"
    exit 1
fi

# Generate .env file for the web application
echo "Creating .env file..."
rm -f /opt/webapp/.env
cat <<EOL > /opt/webapp/.env
DB_HOST=${aws_db_instance.mysql.address}
DB_PORT=3306
DB_USER=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD
DB_NAME=csye6225
DB_DIALECT=mysql
PORT=${var.app_port}
SENDGRID_API_KEY=$SENDGRID_API_KEY
S3_BUCKET_NAME=${aws_s3_bucket.private_bucket.bucket}
AWS_REGION=${var.aws_region}
SNS_TOPIC_ARN=${aws_sns_topic.email_verification_topic.arn}
SENDER_EMAIL=no-reply@demo.daminithorat.me
EOL

# Display the generated .env file for debugging
echo "Generated .env file:"
cat /opt/webapp/.env

# Ensure application directory exists
if [ ! -d "/opt/webapp/app" ]; then
    echo "Application directory /opt/webapp/app does not exist!"
    exit 1
fi

# Change to the application directory and install dependencies
echo "Installing application dependencies..."
cd /opt/webapp/app || exit 1
npm install

# Start the application server
echo "Starting the web application..."
node server.js > /var/log/webapp.log 2>&1 &

# Verify that the server started
echo "Application process:"
ps aux | grep "node server.js"

EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for EC2 Instances
# Filter subnets to only those in available zones (ca-central-1a and ca-central-1b)
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity = 1
  max_size         = 5
  min_size         = 1
  vpc_zone_identifier = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  health_check_grace_period = 300 # Increased to 10 minutes
  health_check_type         = "EC2"
  launch_template {
    id      = aws_launch_template.web_app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  tag {
    key                 = "Name"
    value               = "${var.vpc_name}-webapp-instance"
    propagate_at_launch = true
  }

  # Add Instance Refresh Trigger
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      instance_warmup        = 300
    }
  }
}


# Scale Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up_policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.web_asg.name

  metric_aggregation_type = "Average"
}

# Scale Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down_policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.web_asg.name

  metric_aggregation_type = "Average"
}

# Application Load Balancer
resource "aws_lb" "web_app_alb" {
  name               = "${var.vpc_name}-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.vpc_name}-app-lb"
  }
}

# ALB Listener for HTTP
# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.web_app_alb.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg.arn
#   }
# }

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.web_app_alb.arn # Update to the correct load balancer name
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:ca-central-1:831926588227:certificate/d790ed44-9ae3-403f-a118-306e71309e6d"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn # Update to the correct target group name
  }
}



# Target Group for Application Instances
resource "aws_lb_target_group" "app_tg" {
  name        = "${var.vpc_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/healthz"
    timeout             = 5
    unhealthy_threshold = 2
  }

}

# Route 53 A Record for Load Balancer DNS
resource "aws_route53_record" "web_app_alias" {
  zone_id = var.demo_hosted_id
  name    = var.a_record
  type    = "A"
  alias {
    name                   = aws_lb.web_app_alb.dns_name
    zone_id                = aws_lb.web_app_alb.zone_id
    evaluate_target_health = true
  }
}

# Scale-Up Alarm
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "scale_up_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alarm when CPU usage exceeds 75%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

# Scale-Down Alarm
resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "scale_down_alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Alarm when CPU usage is below 5%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}

# SNS Topic for User Verification
resource "aws_sns_topic" "email_verification_topic" {
  name = "${var.vpc_name}-email-verification"
}

output "sns_topic_arn" {
  value = aws_sns_topic.email_verification_topic.arn
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.vpc_name}-lambda-execution-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for Lambda
# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name = "${var.vpc_name}-lambda-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sns:Publish"
        ],
        "Resource" : aws_sns_topic.email_verification_topic.arn
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource" : [
          "${aws_secretsmanager_secret.email_service.arn}",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:emailsec"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt"
        ],
        "Resource" : "${aws_kms_key.secrets_manager_key.arn}" # Replace with your actual KMS key reference
      }
    ]
  })
}



# Attach IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Lambda Function for Email Verification
resource "aws_lambda_function" "email_verification_lambda" {
  function_name = "${var.vpc_name}-email-verification"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.handler"
  runtime       = "nodejs18.x"

  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)

  environment {
    variables = {
      SENDGRID_API_KEY = var.sendgrid_api_key
      SENDER_EMAIL     = "no-reply@demo.daminithorat.me"
      DB_HOST          = aws_db_instance.mysql.address
      DB_USER          = var.db_username
      DB_PASSWORD      = random_password.rds_password.result
      DB_NAME          = var.db_name
    }
  }

  tags = {
    Name = "${var.vpc_name}-lambda"
  }
}


# SNS Topic Subscription to Lambda
resource "aws_sns_topic_subscription" "lambda_sns_subscription" {
  topic_arn = aws_sns_topic.email_verification_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_verification_lambda.arn
}

# Allow SNS to Invoke Lambda
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowSNSInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_verification_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.email_verification_topic.arn
}

resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name = "LambdaCloudWatchLogsPolicy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

# IAM Policy for EC2 Role to Allow SNS Publish
resource "aws_iam_policy" "ec2_sns_publish_policy" {
  name = "${var.vpc_name}-ec2-sns-publish-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sns:Publish"
        ],
        "Resource" : aws_sns_topic.email_verification_topic.arn
      }
    ]
  })
}

# Attach the policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_sns_publish_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_sns_publish_policy.arn
}