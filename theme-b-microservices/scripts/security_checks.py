"""Offline source regression guards, not a Terraform parser or network simulator."""
import re


# Preserve quoted strings while removing comments; skip braces inside strings.
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|#[^\n]*|//[^\n]*|/\*.*?\*/|[{}]', re.S)


def uncomment(text):
    return TOKEN.sub(lambda m: "" if m[0].startswith(("#", "//", "/*")) else m[0], text)


def block(text, header):
    text = uncomment(text)
    match = re.search(header + r"\s*\{", text)
    if not match:
        return ""
    start = match.end()
    depth = 1
    for token in TOKEN.finditer(text, start):
        if token[0] == "{":
            depth += 1
        elif token[0] == "}":
            depth -= 1
            if depth == 0:
                return text[start:token.start()]
    return ""


def compact(text):
    return re.sub(r"\s+", "", uncomment(text))


def security_checks(files):
    eks = compact(block(files["01-infra/eks.tf"], r'resource "aws_eks_addon" "this"'))
    network = files["03-apps/network-policies.tf"]
    policy = lambda name: compact(block(network, rf'resource "kubernetes_network_policy_v1" "{name}"'))
    workloads = files["03-apps/workloads.tf"]
    default = policy("default_deny")
    dns = policy("dns")
    ingress = policy("app_ingress")
    ui = policy("ui_ingress")
    egress = policy("app_egress")
    data = policy("data_egress")
    aws = policy("aws_https")
    variables = files["03-apps/variables.tf"]
    http = compact(block(variables, r'variable "allow_insecure_http"'))
    lb = compact(block(workloads, r'resource "kubernetes_ingress_v1" "ui"'))
    service = compact(block(workloads, r'resource "kubernetes_service_v1" "app"'))
    deployment = compact(block(workloads, r'resource "kubernetes_deployment_v1" "app"'))
    config = compact(files["03-apps/config.tf"])
    locals_body = compact(block(network, "locals"))
    scoped = 'namespace=kubernetes_namespace_v1.retail.metadata[0].name'
    app_port = 'ports{port="8080"protocol="TCP"}'
    policies = (default, dns, ingress, ui, egress, data, aws)
    infra_vars = files["01-infra/variables.tf"]
    return {
        "operator and client CIDRs reject every /0 spelling": all('try(tonumber(split("/",c)[1])>0,false)' in compact(block(infra_vars, rf'variable "{name}"')) for name in ('admin_cidrs', 'client_cidrs')),
        "VPC CNI enforces NetworkPolicy": 'each.key=="vpc-cni"?jsonencode({' in eks and 'enableNetworkPolicy="true"' in eks,
        "CNI standard mode explicit": 'NETWORK_POLICY_ENFORCING_MODE="standard"' in eks,
        "all policies scoped to retail": all(scoped in p for p in policies),
        "namespace default-deny both directions": 'pod_selector{}policy_types=["Ingress","Egress"]' in default and 'ingress{' not in default and 'egress{' not in default,
        "DNS selector and TCP/UDP 53": 'to{namespace_selector{match_labels={"kubernetes.io/metadata.name"="kube-system"}}pod_selector{match_labels={"k8s-app"="kube-dns"}}}' in dns and 'ports{port="53"protocol="UDP"}' in dns and 'ports{port="53"protocol="TCP"}' in dns,
        "exact app caller matrix": 'app_callers={catalog=["ui"]carts=["ui"]checkout=["ui"]orders=["ui","checkout"]}' in locals_body,
        "exact app destination matrix": 'app_destinations={ui=["catalog","carts","checkout","orders"]checkout=["orders"]}' in locals_body,
        "application ingress selectors and port": 'for_each=local.app_callers' in ingress and 'pod_selector{match_labels={app=each.key}}' in ingress and 'dynamic"from"{for_each=each.valuecontent{pod_selector{match_labels={app=from.value}}}}' in ingress and app_port in ingress and 'namespace_selector' not in ingress,
        "ALB public-subnet ingress only": 'pod_selector{match_labels={app="ui"}}' in ui and 'for_each=local.infra.public_subnet_cidrs' in ui and 'ip_block{cidr=from.value}' in ui and app_port in ui,
        "application egress selectors and port": 'for_each=local.app_destinations' in egress and 'pod_selector{match_labels={app=each.key}}' in egress and 'dynamic"to"{for_each=each.valuecontent{pod_selector{match_labels={app=to.value}}}}' in egress and app_port in egress and 'namespace_selector' not in egress,
        "per-app database ports and subnets": 'data_ports={catalog=3306,orders=5432,checkout=6379}' in locals_body and 'for_each=local.data_ports' in data and 'pod_selector{match_labels={app=each.key}}' in data and 'for_each=local.infra.data_subnet_cidrs' in data and 'ip_block{cidr=to.value}' in data and 'ports{port=tostring(each.value)protocol="TCP"}' in data,
        "AWS HTTPS limited apps and excluded internal ranges": 'for_each=toset(["carts","orders"])' in aws and 'pod_selector{match_labels={app=each.key}}' in aws and 'cidr="0.0.0.0/0"except=[local.infra.vpc_cidr,"169.254.0.0/16"]' in aws and 'ports{port="443"protocol="TCP"}' in aws,
        "no unrestricted allow rules": not re.search(r'(?:ingress|egress|to|from)\s*\{\s*\}', uncomment(network)),
        "policies created before deployment": all(f'kubernetes_network_policy_v1.{n}' in deployment for n in ('default_deny', 'dns', 'app_ingress', 'ui_ingress', 'app_egress', 'data_egress', 'aws_https')),
        "matching Service container and Ingress ports": 'port=8080target_port=8080' in service and 'container_port=8080' in deployment and 'port{number=8080}' in lb,
        "internal app URLs use Service port": all(f'"http://{a}:8080"' in config for a in ('catalog', 'carts', 'checkout', 'orders')) and '"http://orders"' not in config,
        "HTTP opt-in defaults false": 'type=booldefault=false' in http,
        "HTTP missing certificate requires opt-in": 'condition=var.certificate_arn!=""||var.allow_insecure_http' in lb,
        "HTTPS requires matching host configuration": 'condition=var.certificate_arn==""||var.hostname!=""' in lb,
        "HTTPS redirects cleartext listener": '"alb.ingress.kubernetes.io/ssl-redirect"="443"' in lb,
    }
