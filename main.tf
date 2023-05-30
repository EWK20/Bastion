terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region     = "us-east-1"
  access_key = var.ACCESS_KEY
  secret_key = var.SECRET_KEY
}

#* Create an SSH key for bastion servers
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#* Save bastion SSH private key in local file
resource "local_file" "bastion_key_private" {
  content         = tls_private_key.bastion_key.private_key_pem
  filename        = "Bastion_Key.pem"
  file_permission = "0400"
}

#* Register bastion public key with AWS
resource "aws_key_pair" "bastion_key_public" {
  key_name   = "Bastion_KP"
  public_key = tls_private_key.bastion_key.public_key_openssh
}


#* Create an SSH key for web servers
resource "tls_private_key" "webserver_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#* Save webserver SSH private key in local file
resource "local_file" "webserver_key_private" {
  content         = tls_private_key.webserver_key.private_key_pem
  filename        = "WebServer_Key.pem"
  file_permission = "0400"
}

#* Register webserver public key with AWS
resource "aws_key_pair" "webserver_key_public" {
  key_name   = "WebServer_KP"
  public_key = tls_private_key.webserver_key.public_key_openssh
}


#* Create an SSH key for backend servers
resource "tls_private_key" "backend_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#* Save backend SSH private key in local file
resource "local_file" "backend_key_private" {
  content         = tls_private_key.backend_key.private_key_pem
  filename        = "Backend_Key.pem"
  file_permission = "0400"
}

#* Register backend public key with AWS
resource "aws_key_pair" "backend_key_public" {
  key_name   = "Backend_KP"
  public_key = tls_private_key.backend_key.public_key_openssh
}


#* Create virtual network (VPC)
resource "aws_vpc" "custom_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "custom_vpc"
  }
}

#* Create a private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private_subnet"
  }
}

#* Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "public_subnet"
  }
}

#* Create internet gateway (IGW)
resource "aws_internet_gateway" "custom_igw" {
  vpc_id = aws_vpc.custom_vpc.id
}

#* Create new route table and add route for igw to internet
resource "aws_route_table" "custom_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom_igw.id
  }

  tags = {
    Name = "custom-route-table"
  }
}

#* Associate new route table with public subnet
resource "aws_route_table_association" "public_rtb_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.custom_route_table.id
}

#* Create security group for bastion server group
resource "aws_security_group" "bastion_sg" {
  name        = "Bastion_SG"
  description = "Allows bastion servers to be accessed by an authorized ip"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["79.69.78.28/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Bastion SG"
  }
}

#* Create security group for web server group
resource "aws_security_group" "webserver_sg" {
  name        = "WebServer_SG"
  description = "Allows web servers to be accessed"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow SSH from bastion servers"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow ICMP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServer SG"
  }
}

#* Create security group for backend server group
resource "aws_security_group" "backend_sg" {
  name        = "Backend_SG"
  description = "Allows backend servers to be accessed"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow SSH from bastion servers"
  }
  ingress {
    from_port       = 1024
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.webserver_sg.id]
    description     = "Allow TCP on ephemeral ports from web servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Backend SG"
  }
}

#* Create bastion server
resource "aws_instance" "bastion" {
  ami             = "ami-0889a44b331db0194"
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.bastion_key_public.key_name
  subnet_id       = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "Bastion Server"
  }
}

#* Create web server
resource "aws_instance" "web_server" {
  ami             = "ami-0889a44b331db0194"
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.webserver_key_public.key_name
  subnet_id       = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.webserver_sg.id]
  user_data       = file("WebServerData.txt")

  tags = {
    Name = "Web Server"
  }
}

#* Create backend server
resource "aws_instance" "backend_server" {
  ami             = "ami-0889a44b331db0194"
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.backend_key_public.key_name
  subnet_id       = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.backend_sg.id]

  tags = {
    Name = "Backend Server"
  }
}

#* Allocate elastic ip
resource "aws_eip" "nat_ip" {}

#* Create NAT gateway
resource "aws_nat_gateway" "backend_nat" {
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public_subnet.id
}

resource "aws_default_route_table" "nat_association" {
  default_route_table_id = aws_vpc.custom_vpc.default_route_table_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.backend_nat.id
  }
}
