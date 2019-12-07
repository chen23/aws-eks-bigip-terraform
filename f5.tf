
resource "random_password" "password" {
  length  = 10
  special = false
}

resource "aws_instance" "f5" {

  #F5 BIGIP-14.1.0.3-0.0.6 PAYG-Good 25Mbps-190326002717
  #ami = "ami-00a9fd893d5d15cf6" #east-us-1 
  ami = "ami-04aeb21365c18ca08" #west-us-2

  instance_type               = "m5.xlarge"
  associate_public_ip_address = true
  subnet_id                   = "${aws_subnet.demo[0].id}"
  vpc_security_group_ids      = ["${aws_security_group.f5.id}"]
  user_data                   = "${data.template_file.f5_init.rendered}"
  key_name                    = "mikeo-keypair"
  root_block_device { delete_on_termination = true }

  tags = {
    Name = "${var.cluster-name}-f5"
    Env  = "demo"
  }

}
resource "aws_security_group" "f5" {
  name   = "${var.cluster-name}-f5-sg"
  vpc_id = "${aws_vpc.demo.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.workstation-external-cidr}"]
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["${local.workstation-external-cidr}"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "template_file" "f5_init" {
  template = "${file("./f5.tpl")}"
  vars = {
    password = "${random_password.password.result}"
  }
}
# download rpm
resource "null_resource" "download_as3" {
  provisioner "local-exec" {
    command = "wget ${var.as3_rpm_url} -O ./as3/"
  }
}

# install rpm to BIG-IP
resource "null_resource" "install_as3" {
  provisioner "local-exec" {
    command = "tmp=$(mktemp) && cat helloworld.json | jq '.app1.app1.serviceMain.virtualAddresses |= [${var.vip_address}]' > $tmp && mv $tmp helloworld.json"
    working_dir = "${path.module}/as3"
  }
  provisioner "local-exec" {
    command = "./install_as3.sh ${aws_instance.f5.public_dns}:8443 admin:${random_password.password.result} ${var.as3_rpm}"
    working_dir = "${path.module}/as3"
  }
  depends_on = ["null_resource.download_as3", "aws_instance.f5"]
}

# deploy application using as3
resource "bigip_as3" "helloworld" {
  as3_json    = "${file("as3/helloworld.json")}"
  tenant_name = "app1"
  depends_on  = [null_resource.install_as3]
}

