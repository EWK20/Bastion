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


#*Variables Section
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "internet_cidr_block" {
  type    = string
  default = "0.0.0.0/0"
}
variable "vpc_details" {
  type = map(any)
}
variable "private_subnet" {
  type = map(any)
}
variable "public_subnet" {
  type = map(any)
}
variable "authorized_ip" {
  type = list(string)
}
variable "instance_details" {
  type = map(any)
}


provider "aws" {
  region = var.region
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
  for_each             = var.vpc_details
  cidr_block           = each.value.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = each.value.name
  }
}

#* Create a private subnet
resource "aws_subnet" "private_subnet" {
  for_each          = var.private_subnet
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  tags = {
    Name = "${each.key}_subnet"
  }
}

#* Create a public subnet
resource "aws_subnet" "public_subnet" {
  for_each                = var.public_subnet
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = each.value.public
  availability_zone       = each.value.availability_zone
  tags = {
    Name = "${each.key}_subnet"
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
    cidr_block = var.internet_cidr_block
    gateway_id = aws_internet_gateway.custom_igw.id
  }

  tags = {
    Name = "custom-route-table"
  }
}

#* Associate new route table with public subnet
resource "aws_route_table_association" "public_rtb_association" {
  for_each       = var.public_subnet
  subnet_id      = aws_subnet.public_subnet[each.key].id
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
    cidr_blocks = var.authorized_ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
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
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow HTTP from internet"
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow ICMP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
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
    cidr_blocks = [var.internet_cidr_block]
  }

  tags = {
    Name = "Backend SG"
  }
}

resource "aws_instance" "instance_creation" {
  for_each        = var.instance_details
  ami             = each.value.ami
  instance_type   = each.value.instance_type
  key_name        = each.key == "Bastion" ? aws_key_pair.bastion_key_public.key_name : each.key == "WebServer" ? aws_key_pair.webserver_key_public.key_name : aws_key_pair.backend_key_public.key_name
  subnet_id       = each.key == "WebServer" || each.key == "Bastion" ? aws_subnet.public_subnet["public"].id : aws_subnet.private_subnet["private"].id
  security_groups = [each.key == "Bastion" ? aws_security_group.bastion_sg.id : each.key == "WebServer" ? aws_security_group.webserver_sg.id : aws_security_group.backend_sg.id]
  user_data       = each.value.user_data != "" ? file(each.value.user_data) : ""

  tags = {
    Name = each.value.name
  }
}


#* Allocate elastic ip
resource "aws_eip" "nat_ip" {}

#* Create NAT gateway
resource "aws_nat_gateway" "backend_nat" {
  for_each      = var.public_subnet
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public_subnet[each.key].id
}

resource "aws_default_route_table" "nat_association" {
  for_each               = aws_nat_gateway.backend_nat
  default_route_table_id = aws_vpc.custom_vpc.default_route_table_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.backend_nat[each.key].id
  }
}
