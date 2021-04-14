data "aws_ami" "amazon-linux-ami" {
    most_recent = true
    owners      = ["137112412989"]
    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-2.0.20200904.0-x86_64-gp2"]
    }
}

module abc {
    source = "./vpc-ec2-rds-s3"
    product_name = "test1"
    instance_type = "c5.large"
    key_name    = "abc_test"
    nlb_to_application_port = 8080
    user_data_path  =   "test.sh"
    rds_identifier  =   "test1"
    rds_engine  = "mysql"
    rds_engine_version  =   "5.7.19"
    rds_instance_class    = "db.t2.large"
    rds_master_username = "mydb"
    rds_master_password = "YourPwdShouldBeLongAndSecure!"
    rds_port        = 3306
    rds_auth_enabled    = true
    rds_major_engine_version    =   "5.7"
    rds_family  =   "mysql5.7"
    ami_id  =   data.aws_ami.amazon-linux-ami.id
    nlb_public_inbound_cidr = ["103.137.49.34/32"]
    create_bucket = true
    bucket = "test1"
}