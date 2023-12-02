provider "aws" {
  region = "us-west-2"  # Change this to your preferred region
}

# Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create public and private subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a" 
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-2b" 
}

# Create the web security group
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "web application security group"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
     security_groups = [aws_security_group.db_sg.id]
  }
}

# Create the db security group
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "db Security Group"

   ingress {
    from_port       = 3306  # MySQL Port
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
}

# Create a security group for the ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "ALB Security Group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a target group
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "main_vpc"  

  health_check {
    path     = "/"
    protocol = "HTTP"
  }
}

# Create an ALB
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = ["public-subnet-a", "public-subnet-b"]  

  enable_deletion_protection = true  

  enable_cross_zone_load_balancing = true

  enable_http2 = true  # 

  tags = {
    Name = "my-alb"
  }
}

# Create a listener with SSL termination
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-2016-08"  

  certificate_arn = "actul certificate arn" 

  default_action {
    target_group_arn = aws_lb_target_group.my_target_group.arn
    type             = "forward"
  }
}

# Add a rule to forward traffic to the target group
resource "aws_lb_listener_rule" "https_listener_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}


# Create an Auto Scaling Group
resource "aws_launch_configuration" "web_launch_config" {
  name = "web-launch-config"

  image_id = "ami-093467ec28ae4fe03" 
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.public_subnet.id]
  health_check_type    = "EC2"
  health_check_grace_period = 300  
  launch_configuration = aws_launch_configuration.web_launch_config.id
}

# Create an EC2 instance for the application server
resource "aws_instance" "app_server" {
  ami           = "ami-093467ec28ae4fe03"  
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
   security_groups  = [aws_security_group.web_sg.id]
  
}

resource "aws_db_instance" "mysql_db" {
  identifier            = "my-mysql-db"
  allocated_storage     = 150  
  storage_type          = "gp2"
  engine                = "mysql"
  engine_version        = "8.0" 
  instance_class        = "db.t3.medium"  
  username              = "admin"
  password              = "xxxxxxxxx"
  publicly_accessible   = false
  multi_az              = true  
  backup_retention_period = 14  
  storage_encrypted    = true
  ssl_enabled          = true  

  db_subnet_group_name  = "db-sg"
  vpc_security_group_ids = ["vpc security group"]  
}

# Create an S3 bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-access-logs-security"
  acl    = "private"  
 
 # Create a CloudWatch Logs Group for S3 bucket access logs
resource "aws_cloudwatch_log_group" "s3_access_logs" {
  name              = "/aws/s3/${var.s3_bucket_name}"
  retention_in_days = 90
}

# Configure S3 bucket logging
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.s3_bucket_name

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "your_kms_key_id"
      }
    }
  }

  logging {
    target_bucket = aws_s3_bucket.logs.bucket
    target_prefix = "s3-access-logs/"
  }
}

# Create a CloudWatch Logs Group for RDS database logs
resource "aws_cloudwatch_log_group" "rds_logs" {
  name              = "RDSOSMetrics/${var.db_instance_identifier}"
  retention_in_days = 90
}

# Configure RDS logging
resource "aws_db_instance" "my_db" {
  identifier             = var.db_instance_identifier
  // other RDS configurations

  logging {
    // Enable detailed RDS logs
    enabled = true
    types   = ["error", "general", "slowquery"]
  }
}

# Configure CloudWatch Alarms for S3 bucket events
resource "aws_cloudwatch_metric_alarm" "s3_bucket_acl_changed" {
  alarm_name          = "S3BucketAclChanged"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketLevelMetrics"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  dimensions = {
    BucketName = var.s3_bucket_name
  }

  alarm_actions = ["arn:aws:sns:us-west-2:128470766xxx:my-test-sns"]
}

# Configure CloudWatch Alarms for RDS security events
resource "aws_cloudwatch_metric_alarm" "rds_auth_failure" {
  alarm_name          = "RDSAuthFailure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedLoginAttempts"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = ["arn:aws:sns:arn:aws:sns:us-west-2:128470766xxx:my-test-sns"]
}

# Configure CloudWatch Alarms for EC2 web service access logs (example for HTTP 5xx errors)
resource "aws_cloudwatch_metric_alarm" "ec2_http_5xx_errors" {
  alarm_name          = "EC2HTTP5xxErrors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Backend_5XX"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  dimensions = {
    InstanceId = var.ec2_instance_id
  }

  alarm_actions = ["arn:aws:sns:us-west-2:128470766xxx:my-test-sns"]
}
}
# Output variables
output "alb_dns_name" {
  value = aws_lb.my_alb.dns_name
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.web_asg.name
}
