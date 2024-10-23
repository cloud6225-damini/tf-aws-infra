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

# Create public subnets dynamically based on VPC CIDR and availability zones
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

# Create private subnets dynamically based on VPC CIDR and availability zones
resource "aws_subnet" "private" {
  count             = min(3, length(data.aws_availability_zones.available.names))
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # Offset for private subnets
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

# Application Security Group
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "${var.vpc_name}-app-secgroup"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  ingress {
    description = "Allow Application Specific Port"
    from_port   = var.app_port
    to_port     = var.app_port
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

# Database Security Group
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

# RDS Subnet Group for Private Subnets
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

# RDS Instance
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

# EC2 Instance for Web Application
resource "aws_instance" "web_server" {
  ami                         = var.custom_ami
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  # User data script
  user_data = <<-EOF
              #!/bin/bash
              rm -f /opt/webapp/.env  # Delete the existing .env file if it exists
              echo "DB_HOST=${aws_db_instance.mysql.address}" > /opt/webapp/.env
              echo "DB_PORT=3306" >> /opt/webapp/.env  
              echo "DB_USER=csye6225" >> /opt/webapp/.env
              echo "DB_PASSWORD=${var.db_password}" >> /opt/webapp/.env
              echo "DB_NAME=csye6225" >> /opt/webapp/.env
              echo "DB_DIALECT=mysql" >> /opt/webapp/.env
              echo "PORT=${var.app_port}" >> /opt/webapp/.env
              sudo systemctl restart webapp.service
              EOF

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false

  tags = {
    Name = "${var.vpc_name}-webapp-instance"
  }
}
