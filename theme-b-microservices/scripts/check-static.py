#!/usr/bin/env python3
"""Small offline guardrail checks. Not a provider schema validator or AWS test."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
read = lambda p: (root / p).read_text()
infra = "\n".join(p.read_text() for p in (root / "01-infra").glob("*.tf"))
apps = "\n".join(p.read_text() for p in (root / "03-apps").glob("*.tf"))
platform = read("02-platform/main.tf")
checks = {
    "RDS managed passwords (2 databases)": infra.count("manage_master_user_password = true") == 2 or infra.count("manage_master_user_password") == 2,
    "no secret-value data sources": 'data "aws_secretsmanager_secret_version"' not in infra,
    "DynamoDB customer index": '"idx_global_customerId"' in infra and '"customerId"' in infra,
    "IRSA exact service-account subject and audience": 'system:serviceaccount:' in infra and ':aud' in infra and ':sub' in infra,
    "Redis TLS required": 'transit_encryption_mode' in infra and '"required"' in infra,
    "Redis TLS app endpoint": 'rediss://${local.infra.redis_endpoint}' in apps,
    "Orders PostgreSQL certificate validation": 'sslmode=verify-full&sslrootcert=' in apps,
    "SQS app environment": 'RETAIL_ORDERS_MESSAGING_SQS_TOPIC' in apps,
    "no application static AWS keys": 'AWS_ACCESS_KEY_ID' not in apps and 'AWS_SECRET_ACCESS_KEY' not in apps,
    "CSI STS audience": 'audience = "sts.amazonaws.com"' in platform,
    "separate platform and apps states": 'terraform_remote_state" "platform' in apps,
    "Services created before rollout": 'kubernetes_manifest.db_secrets, kubernetes_service_v1.app' in apps,
    "explicit TLS limitation": 'require_secure_transport' in infra and 'OFF' in infra and '非暗号化' in read('README.md'),
    "no secret resources in Terraform state": 'resource "kubernetes_secret' not in apps,
}
policy = json.loads(read("01-infra/policies/aws-load-balancer-controller-v3.6.0.json"))
checks["official ALB IAM policy JSON"] = policy["Version"] == "2012-10-17" and len(policy["Statement"]) > 10
expected = {
    "01-infra/policies/aws-load-balancer-controller-v3.6.0.json": "16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a",
    "03-apps/certs/global-bundle.pem": "fe45bbebf92ad3e27a583bbb2ddd1553c521ed4d49af5514dc0a40372ea5395c",
}
for p, sha in expected.items():
    checks[f"SHA-256 {p}"] = hashlib.sha256((root / p).read_bytes()).hexdigest() == sha
for stage in ("01-infra", "02-platform", "03-apps"):
    checks[f"provider lock {stage}"] = (root / stage / ".terraform.lock.hcl").is_file()
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {label}")
raise SystemExit(0 if all(checks.values()) else 1)
