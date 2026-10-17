# Provider-free fixture: Terraform parses/renders the real templates without AWS.
locals {
  web = templatefile("${path.module}/../../templates/web.sh.tftpl", {
    region        = "ap-northeast-1", artifact_uri = "s3://test-artifacts/web.zip",
    internal_host = "internal-test.ap-northeast-1.elb.amazonaws.com", resolver = "10.10.0.2"
  })
  app = templatefile("${path.module}/../../templates/app.sh.tftpl", {
    region      = "ap-northeast-1", artifact_uri = "s3://test-artifacts/app.zip",
    secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test",
    writer_host = "test.cluster-example.ap-northeast-1.rds.amazonaws.com",
    reader_host = "test.cluster-ro-example.ap-northeast-1.rds.amazonaws.com"
  })
}
