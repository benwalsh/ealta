# Registry the cloud image is pushed to; App Runner deploys from here.
#   aws ecr get-login-password | docker login --username AWS --password-stdin <url>
#   docker build -t <url>:<tag> . && docker push <url>:<tag>
resource "aws_ecr_repository" "app" {
  name                 = var.station_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the last 10 images so the registry doesn't grow unbounded.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
