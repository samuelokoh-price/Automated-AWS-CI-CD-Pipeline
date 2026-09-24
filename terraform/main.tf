# =================================================================
# 0. TERRAFORM CONFIGURATION & REMOTE BACKEND
# =================================================================
terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    bucket         = "my-calculator-tfstate-storage" # FIXED: Matches the auto-creation script name
    key            = "calculator/production.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}

# =================================================================
# 1. NETWORKING SETUP
# =================================================================

resource "aws_vpc" "web_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = { Name = "web-vpc" }
}

resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id
  
  tags = { Name = "web-igw" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  
  tags = { Name = "public-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.web_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }
  
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# =================================================================
# 2. SECURITY GROUP (FIREWALL WITH HTTP & SSH OPENED)
# =================================================================

resource "aws_security_group" "web_sg" {
  name        = "webapp-security-group"
  description = "Allow inbound HTTP web traffic and SSH management access"
  vpc_id      = aws_vpc.web_vpc.id

  # Inbound HTTP Web Traffic (For Nginx)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana Dashboard
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Prometheus Telemetry
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Inbound SSH Terminal Access (For Ansible)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Traffic (Allows server to download packages/updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =================================================================
# 3. UBUNTU IMAGE DYNAMIC DETECTOR
# =================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =================================================================
# 4. EC2 COMPUTE INSTANCE WITH KEY PAIR (CLEANED)
# =================================================================

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.ubuntu.id 
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  key_name               = "dev-prctcs"

  tags = {
    Name = "MyWebAppInstance"
  }
}

# =================================================================
# 5. OUTPUTS
# =================================================================

output "webapp_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "The public IP address of the web application server."
}

# =================================================================
# 6. AUTOMATED ANSIBLE INVENTORY GENERATION
# =================================================================

resource "local_file" "ansible_inventory" {
  content  = <<EOT
[webservers]
${aws_instance.web_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
EOT

  # Drops the file automatically into ansible directory
  filename = "${path.module}/../ansible/hosts.ini"
}
