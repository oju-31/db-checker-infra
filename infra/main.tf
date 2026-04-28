locals {
  az_count       = 2
  namespace_name = "${var.RESOURCE_PREFIX}.local"
  mysql_dns      = "mysql.${local.namespace_name}"
  redis_dns      = "redis.${local.namespace_name}"
  db_password    = substr(replace(uuid(), "-", ""), 0, 24)
  db_root_pass   = replace(uuid(), "-", "")

  tags = merge(var.COMMON_TAGS, {
    ResourceType = "APPLICATION"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-igw"
  })
}

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-public-${count.index + 1}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.RESOURCE_PREFIX}-alb"
  description = "Allow public HTTP traffic to the application load balancer."
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_container_port
  ip_protocol                  = "tcp"
  to_port                      = var.app_container_port
}

resource "aws_security_group" "app" {
  name        = "${var.RESOURCE_PREFIX}-app"
  description = "Allow ALB traffic to PHP tasks and outbound service access."
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-app-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_container_port
  ip_protocol                  = "tcp"
  to_port                      = var.app_container_port
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "data" {
  name        = "${var.RESOURCE_PREFIX}-data"
  description = "Allow PHP tasks to reach MySQL and Redis."
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.RESOURCE_PREFIX}-data-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_app" {
  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 6379
  ip_protocol                  = "tcp"
  to_port                      = 6379
}

resource "aws_vpc_security_group_egress_rule" "data_all" {
  security_group_id = aws_security_group.data.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_lb" "app" {
  name               = "${var.RESOURCE_PREFIX}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = local.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${var.RESOURCE_PREFIX}-app"
  port        = var.app_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.RESOURCE_PREFIX}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = local.namespace_name
  description = "Private service discovery namespace for ${var.RESOURCE_PREFIX}."
  vpc         = aws_vpc.main.id

  tags = local.tags
}

resource "aws_service_discovery_service" "mysql" {
  name = "mysql"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.tags
}

resource "aws_service_discovery_service" "redis" {
  name = "redis"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.RESOURCE_PREFIX}/app"
  retention_in_days = 14

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "mysql" {
  name              = "/ecs/${var.RESOURCE_PREFIX}/mysql"
  retention_in_days = 14

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/ecs/${var.RESOURCE_PREFIX}/redis"
  retention_in_days = 14

  tags = local.tags
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.RESOURCE_PREFIX}/mysql/app-password"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = local.db_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "db_root_password" {
  name                    = "${var.RESOURCE_PREFIX}/mysql/root-password"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_root_password" {
  secret_id     = aws_secretsmanager_secret.db_root_password.id
  secret_string = local.db_root_pass

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.RESOURCE_PREFIX}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.RESOURCE_PREFIX}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.db_root_password.arn
        ]
      }
    ]
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.RESOURCE_PREFIX}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.app_image
      essential = true
      portMappings = [
        {
          containerPort = var.app_container_port
          hostPort      = var.app_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "DB_HOST"
          value = local.mysql_dns
        },
        {
          name  = "DB_USER"
          value = var.database_user
        },
        {
          name  = "DB_NAME"
          value = var.database_name
        },
        {
          name  = "REDIS_HOST"
          value = local.redis_dns
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        }
      ]
      secrets = [
        {
          name      = "DB_PASS"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])

  depends_on = [aws_secretsmanager_secret_version.db_password]

  tags = local.tags
}

resource "aws_ecs_task_definition" "mysql" {
  family                   = "${var.RESOURCE_PREFIX}-mysql"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "mysql"
      image     = var.mysql_image
      essential = true
      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "MYSQL_DATABASE"
          value = var.database_name
        },
        {
          name  = "MYSQL_USER"
          value = var.database_user
        }
      ]
      secrets = [
        {
          name      = "MYSQL_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        },
        {
          name      = "MYSQL_ROOT_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_root_password.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.mysql.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "mysql"
        }
      }
    }
  ])

  depends_on = [
    aws_secretsmanager_secret_version.db_password,
    aws_secretsmanager_secret_version.db_root_password
  ]

  tags = local.tags
}

resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.RESOURCE_PREFIX}-redis"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = var.redis_image
      essential = true
      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.redis.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "redis"
        }
      }
    }
  ])

  tags = local.tags
}

data "aws_region" "current" {}

resource "aws_ecs_service" "mysql" {
  name            = "${var.RESOURCE_PREFIX}-mysql"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mysql.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.data.id]
    subnets          = aws_subnet.public[*].id
  }

  service_registries {
    registry_arn = aws_service_discovery_service.mysql.arn
  }

  tags = local.tags
}

resource "aws_ecs_service" "redis" {
  name            = "${var.RESOURCE_PREFIX}-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.data.id]
    subnets          = aws_subnet.public[*].id
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis.arn
  }

  tags = local.tags
}

resource "aws_ecs_service" "app" {
  name            = "${var.RESOURCE_PREFIX}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.app.id]
    subnets          = aws_subnet.public[*].id
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_container_port
  }

  depends_on = [
    aws_ecs_service.mysql,
    aws_ecs_service.redis,
    aws_lb_listener.http
  ]

  tags = local.tags
}
