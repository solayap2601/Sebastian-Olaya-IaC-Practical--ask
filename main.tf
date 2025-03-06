terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.79.0"
    }
  }
}

module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  name            = "my-vpc"
  cidr            = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_instance" "private_instances" {
  count         = 2
  ami           = "ami-0440d3b780d96b29d"
  instance_type = "t2.micro"
  subnet_id     = module.vpc.private_subnets[count.index]
  tags = {
    Name        = "Private-Instance-${count.index + 1}"
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_lb" "app_lb" {
  name               = "my-application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name        = "my-application-lb"
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "my-target-group"
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_lb_target_group_attachment" "app_tg_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.private_instances[count.index].id
  port             = 80
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "alb-security-group"
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_security_group" "private_sg" {
  name        = "private-instance-sg"
  description = "Security group for private instances"
  vpc_id      = module.vpc.vpc_id 

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "private-instances-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.app_lb.dns_name
}
