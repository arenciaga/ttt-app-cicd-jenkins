terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_default_subnet" "default_az1" {
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tech603-aryan-default-public-subnet-eu-west-1a"
  }
}

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "aryan_jenkins_job3_sg" {
  name        = "tech603-aryan-jenkins-job3-sg"
  description = "Security group for Aryan Jenkins Job 3 app EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from anywhere temporarily"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Node app port 3000 from anywhere"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tech603-aryan-jenkins-job3-sg"
  }
}

resource "aws_instance" "aryan_jenkins_job3" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = "t3.micro"
  key_name                    = "tech603-aryan-aws-key"
  subnet_id                   = aws_default_subnet.default_az1.id
  vpc_security_group_ids      = [aws_security_group.aryan_jenkins_job3_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y nodejs npm rsync
              npm install -g pm2
              mkdir -p /home/ubuntu/ttt-app
              chown -R ubuntu:ubuntu /home/ubuntu/ttt-app
              EOF

  tags = {
    Name = "tech603-aryan-jenkins-job3"
  }
}

output "app_instance_public_ip" {
  value = aws_instance.aryan_jenkins_job3.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/tech603-aryan-aws-key.pem ubuntu@${aws_instance.aryan_jenkins_job3.public_ip}"
}

output "app_url_port_3000" {
  value = "http://${aws_instance.aryan_jenkins_job3.public_ip}:3000"
}