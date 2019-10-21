provider "aws" {
  region  = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

terraform {
  backend "s3" {}
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config {
    bucket         = "${var.tfstate_bucket}"
    key            = "${var.tfstate_key_vpc}"
    region         = "${var.tfstate_region}"
    profile        = "${var.tfstate_profile}"
    role_arn       = "${var.tfstate_arn}"
  }
}

data "aws_availability_zones" "available" {}

data "aws_security_group" "efs" {
  tags   = "${merge(var.source_security_group_tags,map("Env", "${var.project_env}"))}"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"
}

resource "null_resource" "azs" {
  count    = "${length(local.subnets)}"
  triggers = {
    az = "${element(data.aws_availability_zones.available.names,count.index)}"
  }
}

locals {
  zone_id = "${var.dns_private ? data.terraform_remote_state.vpc.private_zone_id : "" }"
  subnets = "${data.terraform_remote_state.vpc.private_subnets}"
  azs     = "${flatten(null_resource.azs.*.triggers.az)}"
}

module "efs" {
  source     = "git::https://github.com/thanhbn87/terraform-aws-efs.git?ref=0.9.1"
  namespace  = "${var.namespace}"
  stage      = "${var.project_env_short}"
  name       = "${var.name}"
  attributes = ["efs"]

  aws_region         = "${var.aws_region}"
  vpc_id             = "${data.terraform_remote_state.vpc.vpc_id}"
  subnets            = ["${local.subnets}"]
  availability_zones = ["${local.azs}"]
  security_group_id  = "${data.aws_security_group.efs.id}"

  zone_id  = "${local.zone_id}"
  dns_name = "${var.dns_name}"
  tags     = "${merge(var.tags,map("Env", "${var.project_env}"))}"
}
