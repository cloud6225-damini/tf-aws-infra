
# Fetch availability zones dynamically for the chosen region
data "aws_availability_zones" "available" {}

# VPC Resource
resource "asdsws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "MainVPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "MainIGW"
  }
}

# Create public subnets (maximum of 3) based on availability zones
resource "aws_subnet" "public" {
  count                   = min(3, length(data.aws_availability_zones.available.names))
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Create private subnets (maximum of 3) based on availability zones
resource "aws_subnet" "private" {
  count             = min(3, length(data.aws_availability_zones.available.names))
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "Public Route Table"
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
  count          = min(3, length(data.aws_availability_zones.available.names))
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "Private Route Table"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_association" {
  count          = min(3, length(data.aws_availability_zones.available.names))
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}
