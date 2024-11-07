# Fetch availability zones dynamically for the chosen region
data "aws_availability_zones" "available" {
  state = "available"
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
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  password               = var.db_password
  parameter_group_name   = aws_db_parameter_group.mysql_parameter_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "${var.vpc_name}-mysql-rds"
  }
}

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

  user_data = base64encode(<<EOF
#!/bin/bash
rm -f /opt/webapp/.env
echo "DB_HOST=${aws_db_instance.mysql.address}" > /opt/webapp/.env
echo "DB_PORT=3306" >> /opt/webapp/.env
echo "DB_USER=csye6225" >> /opt/webapp/.env
echo "DB_PASSWORD=${var.db_password}" >> /opt/webapp/.env
echo "DB_NAME=csye6225" >> /opt/webapp/.env
echo "DB_DIALECT=mysql" >> /opt/webapp/.env
echo "PORT=${var.app_port}" >> /opt/webapp/.env
echo "SENDGRID_API_KEY=${var.sendgrid_api_key}" >> /opt/webapp/.env
echo "S3_BUCKET_NAME=${aws_s3_bucket.private_bucket.bucket}" >> /opt/webapp/.env
echo "AWS_REGION=${var.aws_region}" >> /opt/webapp/.env

# Ensure the log file exists with correct permissions
sudo touch /var/log/webapp.log
sudo chown csye6225:csye6225 /var/log/webapp.log
sudo chmod 664 /var/log/webapp.log

# Install CloudWatch Agent if it's not already installed
if [ ! -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  sudo dpkg -i amazon-cloudwatch-agent.deb
fi

# Start CloudWatch Agent with specified configuration
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Install and start the web application
cd /opt/webapp/app
npm install
node server.js &
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
    aws_subnet.public[0].id, # Assuming this is in ca-central-1a
    aws_subnet.public[1].id  # Assuming this is in ca-central-1b
  ]
  launch_template {
    id      = aws_launch_template.web_app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn] # Attach ASG to target group

  tag {
    key                 = "Name"
    value               = "${var.vpc_name}-webapp-instance"
    propagate_at_launch = true
  }

  health_check_grace_period = 300
  health_check_type         = "EC2"
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
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
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
  threshold           = 8
  alarm_description   = "Alarm when CPU usage exceeds 8%"
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
  threshold           = 7
  alarm_description   = "Alarm when CPU usage is below 7%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}

