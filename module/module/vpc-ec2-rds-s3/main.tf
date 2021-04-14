# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true

  tags = merge({
    Name = var.product_name
  }, var.tags)
}

locals {
  vpc_mask = element(split("/", var.cidr_block), 1)
}

# Create public subnet
resource "aws_subnet" "pub_sub" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.pub_subnet_mask - local.vpc_mask,
    count.index,
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.product_name}-pub-sub-${element(var.azs, count.index)}"
    Tier = "public"
  }, var.tags, var.add_eks_tags ? { "kubernetes.io/role/elb" : "1" } : {})
}

# Create private subnet
resource "aws_subnet" "pvt_sub" {
  count  = length(var.azs)
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.pvt_subnet_mask - local.vpc_mask,
    count.index + length(var.azs),
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.product_name}-pvt-sub-${element(var.azs, count.index)}"
    Tier = "private"
  }, var.tags, var.add_eks_tags ? { "kubernetes.io/role/internal-elb" : "1" } : {})
}

# Create data subnet
resource "aws_subnet" "data_sub" {
  count  = length(var.azs)
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.data_subnet_mask - local.vpc_mask,
    count.index + length(var.azs) * 2,
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.product_name}-data-sub-${element(var.azs, count.index)}"
    Tier = "private"
  }, var.tags)
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.product_name}-igw"
  }, var.tags)
}

# Create public route table
resource "aws_route_table" "pub_rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge({
    Name = "${var.product_name}-pub-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "pub_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pub_sub[count.index].id
  route_table_id = aws_route_table.pub_rtb.id
}

# Create EIP for private NAT gateway
resource "aws_eip" "nat_eip" {
  count = var.create_pvt_nat || var.create_data_nat ? 1 : 0
  vpc   = true

  tags = merge({
    Name = "${var.product_name}-nat-eip"
  }, var.tags)
}

# Create NAT gateway for private subnet
resource "aws_nat_gateway" "nat_gw" {
  count         = var.create_pvt_nat ? 1 : 0
  subnet_id     = aws_subnet.pub_sub[0].id
  allocation_id = join(", ", aws_eip.nat_eip.*.id)

  tags = merge({
    Name = "${var.product_name}-pvt-nat-gw"
  }, var.tags)
}

# Create private route table
resource "aws_route_table" "pvt_rtb" {
  count  = var.create_pvt_nat == false ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.product_name}-pvt-rtb"
  }, var.tags)
}

resource "aws_route_table" "pvt_nat_rtb" {
  count  = var.create_pvt_nat ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = join(", ", aws_nat_gateway.nat_gw.*.id)
  }

  tags = merge({
    Name = "${var.product_name}-pvt-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "pvt_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pvt_sub[count.index].id
  route_table_id = var.create_pvt_nat ? join(", ", aws_route_table.pvt_nat_rtb.*.id) : join(", ", aws_route_table.pvt_rtb.*.id)
}

# Create EIP for data NAT gateway
resource "aws_eip" "data_nat_eip" {
  count = var.create_data_nat ? 1 : 0
  vpc   = true

  tags = merge({
    Name = "${var.product_name}-data-nat-eip"
  }, var.tags)
}

# Create NAT gateway for data subnet
resource "aws_nat_gateway" "data_nat_gw" {
  count         = var.create_data_nat ? 1 : 0
  subnet_id     = aws_subnet.pub_sub[1].id
  allocation_id = join(", ", aws_eip.data_nat_eip.*.id)

  tags = merge({
    Name = "${var.product_name}-data-nat-gw"
  }, var.tags)
}

# Create data route table
resource "aws_route_table" "data_rtb" {
  count  = var.create_data_nat == false ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.product_name}-data-rtb"
  }, var.tags)
}

resource "aws_route_table" "data_nat_rtb" {
  count  = var.create_data_nat ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = join(", ", aws_nat_gateway.data_nat_gw.*.id)
  }

  tags = merge({
    Name = "${var.product_name}-data-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "data_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.data_sub[count.index].id
  route_table_id = var.create_data_nat ? join(", ", aws_route_table.data_nat_rtb.*.id) : join(", ", aws_route_table.data_rtb.*.id)
}

# Create public NACL
resource "aws_network_acl" "pub_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pub_sub.*.id

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 999
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 999
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = merge({
    Name = "${var.product_name}-pub-nacl"
  }, var.tags)
}

# Create private NACL
resource "aws_network_acl" "pvt_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pvt_sub.*.id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge({
    Name = "${var.product_name}-pvt-nacl"
  }, var.tags)
}

# Create data NACL
resource "aws_network_acl" "data_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.data_sub.*.id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge({
    Name = "${var.product_name}-data-nacl"
  }, var.tags)
}

# Create security group for internal communication
resource "aws_security_group" "int_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.product_name}-internal-sg"
  description = "Security group allowing communication internally within the VPC"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.product_name}-internal-sg"
  }, var.tags)
}

# Create security group for accepting only SSH connection
resource "aws_security_group" "ssh_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.product_name}-ssh-sg"
  description = "Security group allowing only SSH connections"

  ingress {
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

  tags = merge({
    Name = "${var.product_name}-ssh-sg"
  }, var.tags)
}

# Create security group for public facing web servers or load balancer
resource "aws_security_group" "pub_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.product_name}-pub-web-sg"
  description = "Security group allowing 80 and 443 from outer world"

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.product_name}-pub-web-sg"
  }, var.tags)
}

# Create security group for internal web/app servers
resource "aws_security_group" "pvt_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.product_name}-pvt-web-sg"
  description = "Security group allowing 22, 80 and 443 internally for instances"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.product_name}-pvt-web-sg"
  }, var.tags)
}

# Create cloudwatch log group for vpc flow logs
resource "aws_cloudwatch_log_group" "cw_log_group" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.product_name}-flow-logs-group"

  tags = merge({
    Name = "${var.product_name}-flow-logs-group"
  }, var.tags)
}

# Create IAM role for VPC flow logs
resource "aws_iam_role" "flow_logs_role" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.product_name}-flow-logs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = merge({
    Name = "${var.product_name}-flow-logs-role"
  }, var.tags)
}

# Create IAM policy for VPC flow logs role
resource "aws_iam_role_policy" "flow_logs_policy" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.product_name}-flow-logs-policy"
  role  = aws_iam_role.flow_logs_role[0].id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "random_id" "id" {
  byte_length = 8
}

# Create S3 bucket for flow logs storage
resource "aws_s3_bucket" "flow_logs_bucket" {
  count  = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket = "${var.product_name}-flow-logs-${random_id.id.hex}"

  tags = merge({
    Name = "${var.product_name}-flow-logs-${random_id.id.hex}"
  }, var.tags)
}

locals {
  flow_logs_log_group_arn = var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? aws_cloudwatch_log_group.cw_log_group[0].arn : var.flow_logs_cw_log_group_arn
  flow_logs_bucket_arn    = var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? aws_s3_bucket.flow_logs_bucket[0].arn : var.flow_logs_bucket_arn
}

# Create VPC flow logs
resource "aws_flow_log" "flow_logs" {
  count                = var.create_flow_logs ? 1 : 0
  iam_role_arn         = var.flow_logs_destination == "cloud-watch-logs" ? aws_iam_role.flow_logs_role[0].arn : ""
  log_destination      = var.flow_logs_destination == "cloud-watch-logs" ? local.flow_logs_log_group_arn : local.flow_logs_bucket_arn
  log_destination_type = var.flow_logs_destination
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.product_name}-flow-logs"
  }, var.tags)
}

# Create a public load balancer

resource "aws_lb_target_group" "this-tg" {
  name     = "${var.product_name}-tg"
  port     = var.nlb_to_application_port
  protocol = "HTTP"
	deregistration_delay = var.tg_deregistration_delay
  vpc_id   = aws_vpc.vpc.id
	health_check {
			enabled             = true
			healthy_threshold   = 5
			interval            = var.tg_health_check_interval
			matcher             = var.tg_health_check_matcher
			path                = var.tg_health_check_path
			port                = "traffic-port"
			protocol            = "HTTP"
			timeout             = var.tg_health_check_timeout
			unhealthy_threshold = 2
	}
}

resource "aws_lb_listener" "this-frontend" {
  load_balancer_arn = aws_lb.this-nlb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this-tg.arn
  }
}

resource "aws_autoscaling_attachment" "this-asg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.this-asg.id
  alb_target_group_arn   = aws_lb_target_group.this-tg.arn
}

resource "aws_security_group" "this-nlb-sg" {
  name_prefix = var.product_name
  description = "Security rules for NLB instances"
  vpc_id      = aws_vpc.vpc.id
  lifecycle {
    create_before_destroy = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "nlb-public-inbound" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = -1
  cidr_blocks              = var.nlb_public_inbound_cidr
  security_group_id        = aws_security_group.this-rds-sg.id
}
resource "aws_lb" "this-nlb" {
  name               = "${var.product_name}-nlb"
  internal           = false
  load_balancer_type = "application"
	security_groups = [aws_security_group.this-nlb-sg.id]
  subnets            = aws_subnet.pub_sub.*.id

  enable_deletion_protection = false

  tags = merge({
    Name = var.product_name
  }, var.tags)
}

# Create a ASG

resource "aws_launch_template" "this-template" {
  name                   = "this-launch-template"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.this-sg.id]
  # iam_instance_profile {
  #   name = aws_iam_instance_profile.this-instance-profile.name
  # }
  user_data = filebase64(var.user_data_path)
  tag_specifications {
    resource_type = "instance"
    tags = merge({
      Name = var.product_name
    }, var.tags)
  }
}

resource "aws_autoscaling_group" "this-asg" {
  name                = "${var.product_name}-asg"
  max_size            = var.asg_max_capacity
  min_size            = var.asg_min_capacity
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.pvt_sub.*.id
  launch_template {
    id      = aws_launch_template.this-template.id
    version = "$Latest"
  }
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

resource "aws_security_group" "this-sg" {
  name_prefix = var.product_name
  description = "Security rules for ec2 instances"
  vpc_id      = aws_vpc.vpc.id
  lifecycle {
    create_before_destroy = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "nlb-inbound" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = -1
  source_security_group_id = aws_security_group.this-nlb-sg.id
  security_group_id        = aws_security_group.this-sg.id
}

# Create a RDS instance for ASG

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 2.0"
  identifier = var.rds_identifier

  engine            = var.rds_engine
  engine_version    = var.rds_engine_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage

  name     = var.product_name
  username = var.rds_master_username
  password = var.rds_master_password
  port     = var.rds_port

  iam_database_authentication_enabled = var.rds_auth_enabled

  vpc_security_group_ids = [aws_security_group.this-rds-sg.id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # Enhanced Monitoring - see example for details on how to create the role
  # by yourself, in case you don't want to create it automatically
  monitoring_interval = "30"
  monitoring_role_name = "${var.product_name}-monitoring-role"
  create_monitoring_role = true

  tags = merge({
    Name = var.product_name
  }, var.tags)

  # DB subnet group
  subnet_ids = aws_subnet.pvt_sub.*.id
  # DB parameter group
  family = var.rds_family
  # DB option group
  major_engine_version = var.rds_major_engine_version
  # Database Deletion Protection
  deletion_protection = true
  parameters = var.rds_parameters
  options = var.rds_options
}

resource "aws_security_group" "this-rds-sg" {
  name_prefix = var.product_name
  description = "Security rules for RDS instances"
  vpc_id      = aws_vpc.vpc.id
  lifecycle {
    create_before_destroy = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ec2-rds-inbound" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = -1
  source_security_group_id = aws_security_group.this-sg.id
  security_group_id        = aws_security_group.this-rds-sg.id
}

# Create a S3 bucket

resource "aws_s3_bucket" "this" {
  count = var.create_bucket ? 1 : 0

  bucket        = var.bucket
  bucket_prefix = var.bucket_prefix

  # hack when `null` value can't be used (eg, from terragrunt, https://github.com/gruntwork-io/terragrunt/pull/1367)
  acl = var.acl != "null" ? var.acl : null

  tags = merge({
    Name = var.product_name
  }, var.tags)
  force_destroy       = var.force_destroy
  acceleration_status = var.acceleration_status
  request_payer       = var.request_payer

  dynamic "website" {
    for_each = length(keys(var.website)) == 0 ? [] : [var.website]

    content {
      index_document           = lookup(website.value, "index_document", null)
      error_document           = lookup(website.value, "error_document", null)
      redirect_all_requests_to = lookup(website.value, "redirect_all_requests_to", null)
      routing_rules            = lookup(website.value, "routing_rules", null)
    }
  }

  dynamic "cors_rule" {
    for_each = try(jsondecode(var.cors_rule), var.cors_rule)

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }

  dynamic "versioning" {
    for_each = length(keys(var.versioning)) == 0 ? [] : [var.versioning]

    content {
      enabled    = lookup(versioning.value, "enabled", null)
      mfa_delete = lookup(versioning.value, "mfa_delete", null)
    }
  }

  dynamic "logging" {
    for_each = length(keys(var.logging)) == 0 ? [] : [var.logging]

    content {
      target_bucket = logging.value.target_bucket
      target_prefix = lookup(logging.value, "target_prefix", null)
    }
  }

  dynamic "grant" {
    for_each = try(jsondecode(var.grant), var.grant)

    content {
      id          = lookup(grant.value, "id", null)
      type        = grant.value.type
      permissions = grant.value.permissions
      uri         = lookup(grant.value, "uri", null)
    }
  }

  dynamic "lifecycle_rule" {
    for_each = try(jsondecode(var.lifecycle_rule), var.lifecycle_rule)

    content {
      id                                     = lookup(lifecycle_rule.value, "id", null)
      prefix                                 = lookup(lifecycle_rule.value, "prefix", null)
      tags                                   = lookup(lifecycle_rule.value, "tags", null)
      abort_incomplete_multipart_upload_days = lookup(lifecycle_rule.value, "abort_incomplete_multipart_upload_days", null)
      enabled                                = lifecycle_rule.value.enabled

      # Max 1 block - expiration
      dynamic "expiration" {
        for_each = length(keys(lookup(lifecycle_rule.value, "expiration", {}))) == 0 ? [] : [lookup(lifecycle_rule.value, "expiration", {})]

        content {
          date                         = lookup(expiration.value, "date", null)
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      # Several blocks - transition
      dynamic "transition" {
        for_each = lookup(lifecycle_rule.value, "transition", [])

        content {
          date          = lookup(transition.value, "date", null)
          days          = lookup(transition.value, "days", null)
          storage_class = transition.value.storage_class
        }
      }

      # Max 1 block - noncurrent_version_expiration
      dynamic "noncurrent_version_expiration" {
        for_each = length(keys(lookup(lifecycle_rule.value, "noncurrent_version_expiration", {}))) == 0 ? [] : [lookup(lifecycle_rule.value, "noncurrent_version_expiration", {})]

        content {
          days = lookup(noncurrent_version_expiration.value, "days", null)
        }
      }

      # Several blocks - noncurrent_version_transition
      dynamic "noncurrent_version_transition" {
        for_each = lookup(lifecycle_rule.value, "noncurrent_version_transition", [])

        content {
          days          = lookup(noncurrent_version_transition.value, "days", null)
          storage_class = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  # Max 1 block - replication_configuration
  dynamic "replication_configuration" {
    for_each = length(keys(var.replication_configuration)) == 0 ? [] : [var.replication_configuration]

    content {
      role = replication_configuration.value.role

      dynamic "rules" {
        for_each = replication_configuration.value.rules

        content {
          id       = lookup(rules.value, "id", null)
          priority = lookup(rules.value, "priority", null)
          prefix   = lookup(rules.value, "prefix", null)
          status   = rules.value.status

          dynamic "destination" {
            for_each = length(keys(lookup(rules.value, "destination", {}))) == 0 ? [] : [lookup(rules.value, "destination", {})]

            content {
              bucket             = destination.value.bucket
              storage_class      = lookup(destination.value, "storage_class", null)
              replica_kms_key_id = lookup(destination.value, "replica_kms_key_id", null)
              account_id         = lookup(destination.value, "account_id", null)

              dynamic "access_control_translation" {
                for_each = length(keys(lookup(destination.value, "access_control_translation", {}))) == 0 ? [] : [lookup(destination.value, "access_control_translation", {})]

                content {
                  owner = access_control_translation.value.owner
                }
              }
            }
          }

          dynamic "source_selection_criteria" {
            for_each = length(keys(lookup(rules.value, "source_selection_criteria", {}))) == 0 ? [] : [lookup(rules.value, "source_selection_criteria", {})]

            content {

              dynamic "sse_kms_encrypted_objects" {
                for_each = length(keys(lookup(source_selection_criteria.value, "sse_kms_encrypted_objects", {}))) == 0 ? [] : [lookup(source_selection_criteria.value, "sse_kms_encrypted_objects", {})]

                content {

                  enabled = sse_kms_encrypted_objects.value.enabled
                }
              }
            }
          }

          dynamic "filter" {
            for_each = length(keys(lookup(rules.value, "filter", {}))) == 0 ? [] : [lookup(rules.value, "filter", {})]

            content {
              prefix = lookup(filter.value, "prefix", null)
              tags   = lookup(filter.value, "tags", null)
            }
          }

        }
      }
    }
  }

  # Max 1 block - server_side_encryption_configuration
  dynamic "server_side_encryption_configuration" {
    for_each = length(keys(var.server_side_encryption_configuration)) == 0 ? [] : [var.server_side_encryption_configuration]

    content {

      dynamic "rule" {
        for_each = length(keys(lookup(server_side_encryption_configuration.value, "rule", {}))) == 0 ? [] : [lookup(server_side_encryption_configuration.value, "rule", {})]

        content {

          dynamic "apply_server_side_encryption_by_default" {
            for_each = length(keys(lookup(rule.value, "apply_server_side_encryption_by_default", {}))) == 0 ? [] : [
            lookup(rule.value, "apply_server_side_encryption_by_default", {})]

            content {
              sse_algorithm     = apply_server_side_encryption_by_default.value.sse_algorithm
              kms_master_key_id = lookup(apply_server_side_encryption_by_default.value, "kms_master_key_id", null)
            }
          }
        }
      }
    }
  }

  # Max 1 block - object_lock_configuration
  dynamic "object_lock_configuration" {
    for_each = length(keys(var.object_lock_configuration)) == 0 ? [] : [var.object_lock_configuration]

    content {
      object_lock_enabled = object_lock_configuration.value.object_lock_enabled

      dynamic "rule" {
        for_each = length(keys(lookup(object_lock_configuration.value, "rule", {}))) == 0 ? [] : [lookup(object_lock_configuration.value, "rule", {})]

        content {
          default_retention {
            mode  = lookup(lookup(rule.value, "default_retention", {}), "mode")
            days  = lookup(lookup(rule.value, "default_retention", {}), "days", null)
            years = lookup(lookup(rule.value, "default_retention", {}), "years", null)
          }
        }
      }
    }
  }

}
