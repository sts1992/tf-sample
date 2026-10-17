#!/usr/bin/env python3
"""Run source-level regression and mutation tests without providers or credentials."""
from pathlib import Path
import unittest

from security_checks import block, security_checks

ROOT = Path(__file__).resolve().parents[1]
FILES = {str(p.relative_to(ROOT)): p.read_text() for stage in ('01-infra', '03-apps') for p in (ROOT / stage).glob('*.tf')}


class SecurityTests(unittest.TestCase):
    def test_current_configuration(self):
        for name, ok in security_checks(FILES).items():
            with self.subTest(check=name):
                self.assertTrue(ok, name)

    def test_regressions_are_rejected(self):
        mutations = [
            ('01-infra/variables.tf', 'try(tonumber(split("/", c)[1]) > 0, false)', 'c != "0.0.0.0/0"'),
            ('01-infra/eks.tf', 'enableNetworkPolicy = "true"', 'enableNetworkPolicy = "false"'),
            ('03-apps/variables.tf', 'default     = false', 'default     = true'),
            ('03-apps/workloads.tf', 'var.certificate_arn != "" || var.allow_insecure_http', 'true'),
            ('03-apps/workloads.tf', 'target_port = 8080', 'target_port = 80'),
            ('03-apps/config.tf', 'http://orders:8080', 'http://orders'),
            ('03-apps/network-policies.tf', 'policy_types = ["Ingress", "Egress"]', 'policy_types = ["Ingress"]'),
            ('03-apps/network-policies.tf', '"k8s-app" = "kube-dns"', '"k8s-app" = "anything"'),
            ('03-apps/network-policies.tf', 'orders   = ["ui", "checkout"]', 'orders   = ["ui", "checkout", "catalog"]'),
            ('03-apps/network-policies.tf', 'local.infra.public_subnet_cidrs', '["0.0.0.0/0"]'),
            ('03-apps/network-policies.tf', 'local.infra.data_subnet_cidrs', '["0.0.0.0/0"]'),
            ('03-apps/network-policies.tf', 'checkout = 6379', 'checkout = 5432'),
            ('03-apps/network-policies.tf', 'toset(["carts", "orders"])', 'toset(["ui", "carts", "orders"])'),
            ('03-apps/network-policies.tf', 'except = [local.infra.vpc_cidr, "169.254.0.0/16"]', 'except = []'),
            ('03-apps/network-policies.tf', 'pod_selector {}', 'pod_selector {}\n    egress {}'),
        ]
        for path, before, after in mutations:
            with self.subTest(path=path, mutation=before):
                self.assertIn(before, FILES[path], 'Mutation must change real source')
                changed = dict(FILES)
                changed[path] = changed[path].replace(before, after, 1)
                self.assertFalse(all(security_checks(changed).values()), 'Security regression was not detected')

    def test_block_scanner_ignores_comments_and_quoted_braces(self):
        self.assertEqual(block('resource "x" "y" { value = "}" # }\n nested { flag = true }\n}', 'resource "x" "y"').strip(), 'value = "}" \n nested { flag = true }')


if __name__ == '__main__':
    unittest.main(verbosity=2)
