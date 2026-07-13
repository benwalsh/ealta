# RDS MySQL — the cloud mirror's datastore. Private (no public IP); only the ECS
# Express Mode service can reach it.

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.station_name}-ecs-tasks"
  description = "ECS Express Fargate tasks: egress out, ALB in on the app port"
  vpc_id      = data.aws_vpc.default.id

  # The Express Mode ALB lives in this VPC; allow it to reach the container port.
  ingress {
    description = "App port from the Express Mode ALB (in-VPC)"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  # NB: a SG's description is immutable in AWS — changing it forces a full replace,
  # which can't complete here (RDS ENIs are service-managed and can't be force-
  # detached, and create_before_destroy introduces a dependency cycle). So the SG
  # keeps its original "App Runner" wording; only its ingress *rule* is swapped to
  # the ECS tasks SG (an in-place update). The rule description below is accurate.
  name        = "${var.station_name}-rds"
  description = "MySQL from the App Runner service only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = var.station_name
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "main" {
  identifier     = var.station_name
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # a derived mirror — single-AZ is fine

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false # flip to true once it holds real history

  # utf8mb4 end to end so Irish fadas survive.
  parameter_group_name = aws_db_parameter_group.main.name
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.station_name}-mysql84"
  family = "mysql8.4"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
}
