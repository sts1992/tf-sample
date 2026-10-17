locals {
  oidc_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
  service_accounts = {
    catalog = { namespace = local.namespace, name = "catalog" }
    carts   = { namespace = local.namespace, name = "carts" }
    orders  = { namespace = local.namespace, name = "orders" }
    alb     = { namespace = "kube-system", name = "aws-load-balancer-controller" }
  }
}
resource "aws_iam_role" "pod" {
  for_each = local.service_accounts
  name     = "${var.name}-${each.key}-pod"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }, Action = "sts:AssumeRoleWithWebIdentity",
    Condition = { StringEquals = {
      "${local.oidc_host}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
      "${local.oidc_host}:aud" = "sts.amazonaws.com"
    } }
  }] })
}
resource "aws_iam_role_policy" "catalog" {
  name = "read-catalog-secret"
  role = aws_iam_role.pod["catalog"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"], Resource = aws_db_instance.catalog.master_user_secret[0].secret_arn
  }] })
}
resource "aws_iam_role_policy" "orders" {
  name = "read-orders-secret-and-publish"
  role = aws_iam_role.pod["orders"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"], Resource = aws_db_instance.orders.master_user_secret[0].secret_arn },
    { Effect = "Allow", Action = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.orders.arn }
  ] })
}
resource "aws_iam_role_policy" "carts" {
  name = "carts-table-only"
  role = aws_iam_role.pod["carts"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"],
    Resource = [aws_dynamodb_table.carts.arn, "${aws_dynamodb_table.carts.arn}/index/idx_global_customerId"]
  }] })
}
# Official, version-matched controller policy. Some discovery/create actions require Resource="*".
resource "aws_iam_role_policy" "alb" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.pod["alb"].id
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.0.json")
}
