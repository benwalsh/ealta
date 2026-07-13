# GitHub Actions deploys via OIDC — no long-lived AWS keys in the repo. The workflow
# (.github/workflows/deploy.yml) assumes this role to push to ECR and redeploy the
# ECS Express service. Trust is scoped to this repo's main branch only.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's; AWS also trusts it via its CA store
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.station_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # ECS Express deploy (register task def + roll the service). Task-defs have no ARN
  # to scope to before creation, so these are account-wide — standard for CI deploy.
  statement {
    sid = "EcsDeploy"
    actions = [
      "ecs:RegisterTaskDefinition", "ecs:DescribeExpressGatewayService",
      "ecs:UpdateExpressGatewayService", "ecs:UpdateService",
      "ecs:DescribeServices", "ecs:DescribeClusters"
    ]
    resources = ["*"]
  }

  # Pass only the service's own roles to ECS during a deploy.
  statement {
    sid     = "PassServiceRoles"
    actions = ["iam:PassRole"]
    resources = [
      module.express_service.execution_iam_role_arn,
      module.express_service.task_iam_role_arn,
      module.express_service.infrastructure_iam_role_arn
    ]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.station_name}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
