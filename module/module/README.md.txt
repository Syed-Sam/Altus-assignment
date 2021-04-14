This module will create VPC public, private subnets, route table, internet gateway, Auto scaling group, network load balancer
and s3 bucket.

In main.tf just mention the values of variables and then run terraform plan and terraform apply command. it first install 
all the dependencies and then will start to create resources. 